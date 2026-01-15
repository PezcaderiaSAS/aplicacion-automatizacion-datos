-- init.sql
-- Script de inicialización de la base de datos para "Aplicación de Automatización de Registro de Datos"
-- Usa UUID por defecto para ids, DECIMAL(10,2) para dinero, TIMESTAMPTZ para fechas.
-- Comentarios explican decisiones de diseño y constraints.

-- Habilitar extensión para generar UUIDs (gen_random_uuid)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =========================
-- Tabla: suppliers
-- Proveedores: almacena datos básicos del proveedor.
-- id: UUID generado por gen_random_uuid()
-- estado: 'activo' o 'inactivo'
-- =========================
CREATE TABLE IF NOT EXISTS suppliers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre TEXT NOT NULL,
  contacto TEXT,
  estado VARCHAR(10) NOT NULL DEFAULT 'activo' CHECK (estado IN ('activo', 'inactivo'))
);

-- =========================
-- Tabla: products
-- Productos con referencia al proveedor. stock >= 0.
-- precio usa DECIMAL(10,2) para precisión financiera.
-- created_at / updated_at como TIMESTAMPTZ para auditoría temporal.
-- =========================
CREATE TABLE IF NOT EXISTS products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sku TEXT NOT NULL UNIQUE, -- índice único implícito por UNIQUE
  nombre TEXT NOT NULL,
  precio DECIMAL(10,2) NOT NULL CHECK (precio >= 0),
  stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
  id_proveedor UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT fk_products_supplier FOREIGN KEY (id_proveedor) REFERENCES suppliers(id) ON DELETE RESTRICT
);

-- Índices adicionales para búsquedas frecuentes:
-- - id_proveedor para consultas por proveedor
-- - lower(nombre) para búsquedas case-insensitive
CREATE INDEX IF NOT EXISTS idx_products_id_proveedor ON products (id_proveedor);
CREATE INDEX IF NOT EXISTS idx_products_lower_nombre ON products (lower(nombre));

-- =========================
-- Tabla: operations_log
-- Auditoría general. detalles como JSONB para flexibilidad.
-- =========================
CREATE TABLE IF NOT EXISTS operations_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo_operacion TEXT NOT NULL,
  fecha TIMESTAMPTZ NOT NULL DEFAULT now(),
  detalles JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_operations_log_tipo ON operations_log (tipo_operacion);

-- =========================
-- Tabla: inventory_movements
-- Registra entradas/salidas físicas/virtuales de inventario.
-- tipo: 'entrada' | 'salida'
-- cantidad > 0
-- =========================
CREATE TABLE IF NOT EXISTS inventory_movements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  id_producto UUID NOT NULL,
  tipo VARCHAR(10) NOT NULL CHECK (tipo IN ('entrada', 'salida')),
  cantidad INTEGER NOT NULL CHECK (cantidad > 0),
  fecha TIMESTAMPTZ NOT NULL DEFAULT now(),
  nota TEXT,
  CONSTRAINT fk_movement_product FOREIGN KEY (id_producto) REFERENCES products(id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_inventory_movements_id_producto ON inventory_movements (id_producto);

-- =========================
-- Función: fn_products_stock_audit
-- Trigger para auditar cambios en la columna stock de products.
-- Inserta registro en operations_log con detalles relevantes (old/new).
-- Observaciones:
-- - Se ejecuta AFTER INSERT y AFTER UPDATE para capturar creación y cambios.
-- - Usa jsonb_build_object para estructura flexible.
-- =========================
CREATE OR REPLACE FUNCTION fn_products_stock_audit() RETURNS TRIGGER AS $$
BEGIN
  -- Si es UPDATE y el stock cambió, loguear cambio de stock
  IF TG_OP = 'UPDATE' AND NEW.stock IS DISTINCT FROM OLD.stock THEN
    INSERT INTO operations_log (tipo_operacion, fecha, detalles)
    VALUES (
      'stock_update',
      now(),
      jsonb_build_object(
        'product_id', NEW.id,
        'sku', NEW.sku,
        'old_stock', OLD.stock,
        'new_stock', NEW.stock,
        'changed_at', now(),
        'changed_by', current_user,
        'source', TG_ARGV -- optional args
      )
    );
  ELSIF TG_OP = 'INSERT' THEN
    -- registrar creación de producto con stock inicial
    INSERT INTO operations_log (tipo_operacion, fecha, detalles)
    VALUES (
      'product_insert',
      now(),
      jsonb_build_object(
        'product_id', NEW.id,
        'sku', NEW.sku,
        'new_stock', NEW.stock,
        'created_at', now(),
        'created_by', current_user
      )
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger que invoca la función anterior
DROP TRIGGER IF EXISTS trg_products_stock_audit ON products;
CREATE TRIGGER trg_products_stock_audit
  AFTER INSERT OR UPDATE ON products
  FOR EACH ROW
  EXECUTE FUNCTION fn_products_stock_audit();

-- =========================
-- Función: fn_adjust_stock_from_movement
-- Ajusta el stock en la tabla products cuando se inserta un inventory_movement.
-- Reglas:
-- - Para 'entrada' suma cantidad.
-- - Para 'salida' resta cantidad, pero solo si hay stock suficiente.
-- - Si no hay producto o stock insuficiente se lanza ERROR (evita inconsistencias).
-- - AFTER INSERT en movements para mantener la integridad transaccional:
--   la inserción del movimiento y la actualización de stock se realizan en la misma transacción;
--   si falla el update, se revierte la inserción.
-- =========================
CREATE OR REPLACE FUNCTION fn_adjust_stock_from_movement() RETURNS TRIGGER AS $$
DECLARE
  updated_count INTEGER;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.tipo = 'entrada' THEN
      UPDATE products
      SET stock = stock + NEW.cantidad,
          updated_at = now()
      WHERE id = NEW.id_producto;
      GET DIAGNOSTICS updated_count = ROW_COUNT;

      IF updated_count = 0 THEN
        RAISE EXCEPTION 'Producto no encontrado: %', NEW.id_producto;
      END IF;

    ELSIF NEW.tipo = 'salida' THEN
      -- Decrementar solo si hay stock suficiente
      UPDATE products
      SET stock = stock - NEW.cantidad,
          updated_at = now()
      WHERE id = NEW.id_producto AND stock >= NEW.cantidad;
      GET DIAGNOSTICS updated_count = ROW_COUNT;

      IF updated_count = 0 THEN
        RAISE EXCEPTION 'Stock insuficiente o producto no encontrado para id: %', NEW.id_producto;
      END IF;

    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger que ajusta el stock después de insertar un movimiento
DROP TRIGGER IF EXISTS trg_adjust_stock_from_movement ON inventory_movements;
CREATE TRIGGER trg_adjust_stock_from_movement
  AFTER INSERT ON inventory_movements
  FOR EACH ROW
  EXECUTE FUNCTION fn_adjust_stock_from_movement();

-- =========================
-- TABLAS ADICIONALES: orders, order_lines
-- Modelado de pedidos transaccionales. Cada order tiene multiple order_lines.
-- Reglas de diseño:
--  - ids UUID
--  - order_number secuencial para referencia humana (sequence)
--  - estado: placed | cancelled | fulfilled
--  - total calculado y almacenado para consultas rápidas
--  - order_lines referencia a products; ON DELETE CASCADE para mantener consistencia histórica
-- =========================

-- Secuencia para números de orden legibles
CREATE SEQUENCE IF NOT EXISTS order_number_seq START 1000;

CREATE TABLE IF NOT EXISTS orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number BIGINT NOT NULL DEFAULT nextval('order_number_seq'),
  cliente TEXT NOT NULL,
  total DECIMAL(12,2) NOT NULL CHECK (total >= 0),
  estado VARCHAR(20) NOT NULL DEFAULT 'placed' CHECK (estado IN ('placed','cancelled','fulfilled')),
  fecha TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by TEXT DEFAULT current_user
);

CREATE INDEX IF NOT EXISTS idx_orders_fecha ON orders (fecha);

CREATE TABLE IF NOT EXISTS order_lines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL,
  product_id UUID NOT NULL,
  cantidad INTEGER NOT NULL CHECK (cantidad > 0),
  precio_unit DECIMAL(10,2) NOT NULL CHECK (precio_unit >= 0),
  subtotal DECIMAL(12,2) NOT NULL CHECK (subtotal >= 0),
  CONSTRAINT fk_orderlines_order FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
  CONSTRAINT fk_orderlines_product FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_order_lines_order_id ON order_lines (order_id);
CREATE INDEX IF NOT EXISTS idx_order_lines_product_id ON order_lines (product_id);

-- =========================
-- Función transaccional: fn_create_order
-- Crea un pedido con sus líneas de forma atómica:
--  - Bloquea filas de products con SELECT ... FOR UPDATE para evitar race conditions
--  - Verifica stock suficiente para cada línea
--  - Actualiza stock, inserta order, order_lines e inventory_movements
--  - Inserta un registro en operations_log con detalle del pedido
-- Si alguna verificación falla, la función hace RAISE EXCEPTION y toda la transacción se revierte.
-- =========================

CREATE OR REPLACE FUNCTION fn_create_order(p_cliente TEXT, p_lines JSONB, p_created_by TEXT DEFAULT current_user) RETURNS UUID AS $$
DECLARE
  v_order_id UUID := gen_random_uuid();
  v_total NUMERIC := 0;
  v_line JSONB;
  v_product_id UUID;
  v_cantidad INTEGER;
  v_precio DECIMAL(10,2);
  v_stock INTEGER;
  v_subtotal DECIMAL(12,2);
BEGIN
  -- Recorremos las líneas para verificar y bloquear productos
  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    v_product_id := (v_line ->> 'product_id')::UUID;
    v_cantidad := (v_line ->> 'cantidad')::INTEGER;
    v_precio := (v_line ->> 'precio_unit')::DECIMAL;

    IF v_cantidad <= 0 THEN
      RAISE EXCEPTION 'Cantidad inválida para producto %', v_product_id;
    END IF;

    -- Bloqueo de fila para evitar carreras (concurrency)
    SELECT stock INTO v_stock FROM products WHERE id = v_product_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Producto no encontrado: %', v_product_id;
    END IF;

    IF v_stock < v_cantidad THEN
      RAISE EXCEPTION 'Stock insuficiente para producto %: disponible %, requerido %', v_product_id, v_stock, v_cantidad;
    END IF;

    v_subtotal := ROUND(v_precio * v_cantidad::NUMERIC, 2);
    v_total := v_total + v_subtotal;
  END LOOP;

  -- Insertar order principal
  INSERT INTO orders (id, order_number, cliente, total, estado, fecha, created_by)
  VALUES (v_order_id, nextval('order_number_seq'), p_cliente, v_total, 'placed', now(), p_created_by);

  -- Volver a iterar para insertar lineas y actualizar stock
  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    v_product_id := (v_line ->> 'product_id')::UUID;
    v_cantidad := (v_line ->> 'cantidad')::INTEGER;
    v_precio := (v_line ->> 'precio_unit')::DECIMAL;
    v_subtotal := ROUND(v_precio * v_cantidad::NUMERIC, 2);

    -- Insertar order_line
    INSERT INTO order_lines (order_id, product_id, cantidad, precio_unit, subtotal)
    VALUES (v_order_id, v_product_id, v_cantidad, v_precio, v_subtotal);

    -- Actualizar stock
    UPDATE products SET stock = stock - v_cantidad, updated_at = now() WHERE id = v_product_id;

    -- Registrar movimiento de inventario (salida)
    INSERT INTO inventory_movements (id_producto, tipo, cantidad, fecha, nota)
    VALUES (v_product_id, 'salida', v_cantidad, now(), jsonb_build_object('order_id', v_order_id)::text);
  END LOOP;

  -- Registrar en operations_log la creación del pedido
  INSERT INTO operations_log (tipo_operacion, fecha, detalles)
  VALUES (
    'order_created', now(),
    jsonb_build_object('order_id', v_order_id, 'cliente', p_cliente, 'total', v_total, 'lines', p_lines, 'created_by', p_created_by)
  );

  RETURN v_order_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Índice para operaciones sobre operaciones de pedidos
CREATE INDEX IF NOT EXISTS idx_operations_log_order_created ON operations_log ((detalles->>'order_id')) WHERE tipo_operacion = 'order_created';
