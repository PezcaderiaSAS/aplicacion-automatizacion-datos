# ACCESO Y VERIFICACIÓN FINAL

## 🌐 Acceso a pgAdmin

**URL:** http://localhost:8080

**Credenciales de Login:**
```
Email:    admin@example.com
Password: AdminPass123!
```

### Agregar Conexión a Postgres

1. En pgAdmin, haz clic en **"Add New Server"** (ícono + en la esquina superior izquierda)
2. Rellena los campos:
   - **Name:** `Local Postgres` (o el nombre que prefieras)
   - **Host name/address:** `db` (si estás dentro de Docker) o `localhost` (si desde tu máquina)
   - **Port:** `5432`
   - **Maintenance database:** `postgres`
   - **Username:** `appuser`
   - **Password:** `AppUserPass123!`
3. Haz clic en **"Save"**

### Explorar las Tablas

Una vez conectado:
1. Expande el servidor en el árbol izquierdo
2. Navega a **Databases** → **appdb** → **Schemas** → **public** → **Tables**
3. Verás las tablas creadas:
   - `suppliers` (50 filas)
   - `products` (200 filas)
   - `orders` (17-20 filas dependiendo de la ejecución)
   - `order_lines` (múltiples líneas por orden)
   - `inventory_movements` (146 filas)
   - `operations_log` (409 filas de auditoría)

---

## 🧪 Consultas de Verificación Rápida

Haz clic en **"Tools"** → **"Query Tool"** en pgAdmin y copia/pega estas consultas:

### 1. Contar todas las tablas
```sql
SELECT 
  (SELECT COUNT(*) FROM suppliers) as suppliers,
  (SELECT COUNT(*) FROM products) as products,
  (SELECT COUNT(*) FROM orders) as orders,
  (SELECT COUNT(*) FROM order_lines) as order_lines,
  (SELECT COUNT(*) FROM inventory_movements) as movements,
  (SELECT COUNT(*) FROM operations_log) as audit_logs;
```

### 2. Ver top 5 órdenes creadas
```sql
SELECT order_number, cliente, total, estado, fecha
FROM orders
ORDER BY fecha DESC
LIMIT 5;
```

### 3. Ver detalles de la primera orden
```sql
SELECT 
  o.order_number,
  o.cliente,
  o.total,
  ol.cantidad,
  ol.precio_unit,
  ol.subtotal,
  p.sku,
  p.nombre
FROM orders o
JOIN order_lines ol ON o.id = ol.order_id
JOIN products p ON ol.product_id = p.id
ORDER BY o.fecha ASC
LIMIT 10;
```

### 4. Ver últimos cambios de stock (auditoría)
```sql
SELECT 
  (detalles->>'sku') as sku,
  (detalles->>'old_stock')::INT as old_stock,
  (detalles->>'new_stock')::INT as new_stock,
  fecha
FROM operations_log
WHERE tipo_operacion = 'stock_update'
ORDER BY fecha DESC
LIMIT 20;
```

### 5. Ver ordenes creadas (auditoría)
```sql
SELECT 
  (detalles->>'order_id') as order_id,
  (detalles->>'cliente') as cliente,
  (detalles->>'total') as total,
  fecha
FROM operations_log
WHERE tipo_operacion = 'order_created'
ORDER BY fecha DESC
LIMIT 20;
```

### 6. Resumen de stock por supplier
```sql
SELECT 
  s.nombre as supplier,
  COUNT(p.id) as total_products,
  SUM(p.stock) as total_stock,
  AVG(p.precio) as avg_price
FROM suppliers s
LEFT JOIN products p ON s.id = p.id_proveedor
GROUP BY s.id, s.nombre
ORDER BY total_stock DESC
LIMIT 10;
```

---

## 🔄 Simular Orden Fallida (Prueba ACID)

En la consola Python o query tool de pgAdmin, ejecuta:

```python
# Opción 1: Desde Python
import psycopg2
import json

conn = psycopg2.connect("dbname=appdb user=appuser password=AppUserPass123! host=localhost port=5432")
cur = conn.cursor()

# Obtén un producto con poco stock
cur.execute("SELECT id, stock FROM products WHERE stock < 5 LIMIT 1")
product_id, stock = cur.fetchone()

# Intenta crear una orden que exceda el stock
lines = json.dumps([
    {
        "product_id": str(product_id),
        "cantidad": stock + 10,  # Solicita más de lo disponible
        "precio_unit": 100.00
    }
])

try:
    cur.execute(f"SELECT fn_create_order('Test Cliente', '{lines}'::jsonb)")
    print("Order created (unexpected!)")
except Exception as e:
    print(f"Order failed as expected: {e}")
    conn.rollback()

conn.close()
```

```sql
-- Opción 2: Desde SQL en pgAdmin
-- Obtén el ID de un producto con poco stock
SELECT id FROM products WHERE stock < 5 LIMIT 1;

-- Copia el ID y ejecuta (reemplaza 'PRODUCT_ID'):
SELECT fn_create_order(
  'Test Cliente Fallido',
  '[
    {"product_id": "PRODUCT_ID", "cantidad": 999, "precio_unit": 100.00}
  ]'::jsonb
);

-- Deberías obtener error: "Stock insuficiente..."
-- Verifica que NO se creó la orden ni se movió el stock:
SELECT COUNT(*) FROM orders WHERE cliente = 'Test Cliente Fallido';  -- Deberá ser 0
```

---

## 📊 Exportar Datos

### Exportar tabla a CSV
1. En pgAdmin, haz clic derecho en una tabla (ej. `orders`)
2. Selecciona **"Backup"** o **"Export"** (en algunas versiones)
3. O en Query Tool, ejecuta:
   ```sql
   COPY orders TO '/tmp/orders.csv' WITH (FORMAT csv, HEADER);
   ```

---

## 🧹 Limpiar y Reiniciar

### Opción 1: Truncar tablas (mantener schema)
```powershell
python .\reset_db.py
python .\seed_data.py  # Reinicia con nuevos datos
```

### Opción 2: Reiniciar Docker completamente
```powershell
docker-compose down -v  # Elimina contenedores y volúmenes
docker-compose up -d   # Reinicia (init.sql se ejecuta de nuevo)
# Espera 20-30 segundos, luego:
python .\seed_data.py
```

### Opción 3: Detener Docker (sin borrar datos)
```powershell
docker-compose stop    # Pausa servicios
docker-compose start   # Reanuda servicios
```

---

## 🎯 Checklist de Verificación Final

- [ ] `docker-compose ps` muestra ambos contenedores (db + pgadmin) en estado "Up"
- [ ] Puedo conectarme a http://localhost:8080 con credentials de `.env`
- [ ] Agrego conexión a "db" en pgAdmin (hostname: `db` o `localhost`)
- [ ] Veo las 6 tablas en la Base de datos `appdb`
- [ ] Ejecuto consulta de conteo: veo 50 suppliers, 200 products, 17+ orders, etc.
- [ ] Veo auditoría: 409+ registros en `operations_log`
- [ ] Intento simular orden fallida: obtengo error "Stock insuficiente" y NO se crea la orden
- [ ] Ejecuto `python .\demo_queries.py` y veo resumen en consola

---

## 🆘 Troubleshooting

| Problema | Solución |
|----------|----------|
| `docker-compose up -d` falla | Verifica que Docker Desktop esté corriendo |
| Postgres no inicia | `docker-compose logs db` para ver error de init.sql |
| No puedo conectar desde pgAdmin | Usa hostname `db` (no `localhost`) para conexiones internas |
| Seed falla por duplicados | Ejecuta `python .\reset_db.py` antes de re-ejecutar seed |
| Terminal PowerShell inestable | Abre una terminal nueva, navega al directorio y reinicia |
| pgAdmin muestra "server unavailable" | Espera 30s más, Postgres puede tardar en inicializar |

---

## 📞 Contacto / Preguntas

Los archivos están documentados. Consulta:
- `DOCUMENTACION_COMPLETA.md` para detalles técnicos
- `README.md` para instrucciones rápidas
- `init.sql` para ver el esquema completo con comentarios

---

**¡Proyecto completado exitosamente!** ✅
