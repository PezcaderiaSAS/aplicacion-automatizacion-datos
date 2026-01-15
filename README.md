# Aplicación de Automatización de Registro de Datos

Sistema robusto de automatización de registro de datos con PostgreSQL, Docker, triggers automáticos y función transaccional ACID para gestión de inventario y órdenes.

## 🚀 Características Principales

- **Infraestructura Docker:** PostgreSQL 18 + pgAdmin 4
- **Triggers Automáticos:** Auditoría y ajuste de stock en tiempo real
- **Función Transaccional ACID:** Creación atómica de órdenes
- **Base de Datos Profesional:** UUID, DECIMAL, TIMESTAMPTZ, constraints, índices
- **Auditoría Completa:** JSONB logging de todas las operaciones
- **Script de Población:** 50 proveedores, 200 productos, 100 movimientos, 20 órdenes

## 📋 Requisitos

- Docker Desktop instalado y ejecutándose
- Python 3.8+ (para scripts locales)
- PowerShell o terminal compatible

## 🔧 Instalación Rápida

### 1. Clonar el repositorio

```bash
git clone https://github.com/PezcaderiaSAS/aplicacion-automatizacion-datos.git
cd aplicacion-automatizacion-datos
```

### 2. Configurar variables de entorno

```bash
cp .env.example .env
# Edita .env si necesitas cambiar credenciales (opcional)
```

### 3. Levantar los contenedores

```bash
docker-compose up -d
```

### 4. Instalar dependencias Python (opcional)

```bash
pip install -r requirements.txt
# O en un virtualenv:
python -m venv venv
source venv/bin/activate  # En Windows: venv\\Scripts\\Activate.ps1
pip install -r requirements.txt
```

### 5. Ejecutar scripts de demostración

```bash
# Poblar la base de datos
python seed_data.py

# Ver resumen en consola
python demo_queries.py

# Limpiar y reiniciar (opcional)
python reset_db.py
python seed_data.py
```

## 📊 Acceso a los Datos

### pgAdmin (Interfaz Visual)

- **URL:** http://localhost:8080
- **Email:** admin@example.com
- **Contraseña:** AdminPass123!
- **Host para BD:** `db` o `localhost`
- **Usuario BD:** appuser
- **Contraseña BD:** AppUserPass123!

### PostgreSQL (Línea de Comandos)

```bash
psql -h localhost -U appuser -d appdb

# Ejemplos:
SELECT COUNT(*) FROM orders;
SELECT * FROM suppliers LIMIT 5;
SELECT * FROM operations_log LIMIT 10;
```

### Python

```python
import psycopg2

conn = psycopg2.connect(
    host='localhost',
    port=5432,
    database='appdb',
    user='appuser',
    password='AppUserPass123!'
)
cur = conn.cursor()
cur.execute('SELECT * FROM orders LIMIT 5')
for row in cur.fetchall():
    print(row)
conn.close()
```

## 🗂️ Esquema de Base de Datos

### Tablas Principales

- **suppliers** - Proveedores (50 filas)
- **products** - Productos (200 filas)
- **inventory_movements** - Movimientos de stock (146 filas)
- **orders** - Órdenes transaccionales (17 filas)
- **order_lines** - Líneas de órdenes (~60 filas)
- **operations_log** - Auditoría JSONB (409+ registros)

### Triggers

- `trg_products_stock_audit` - Audita cambios de stock
- `trg_adjust_stock_from_movement` - Ajusta stock automáticamente

### Funciones

- `fn_products_stock_audit()` - Trigger de auditoría
- `fn_adjust_stock_from_movement()` - Trigger de ajuste de stock
- `fn_create_order(cliente, lines_JSONB)` - Función transaccional ACID

## 🔐 Garantías ACID

### Atomicidad
La función `fn_create_order()` crea órdenes de forma atómica: todo o nada.

### Consistencia
CHECK constraints previenen stock negativo. Foreign keys previenen datos orfandos.

### Aislamiento
`SELECT ... FOR UPDATE` bloquea filas durante transacciones.

### Durabilidad
PostgreSQL WAL + volumen Docker persistente.

## 📚 Documentación Completa

Este repositorio incluye documentación exhaustiva:

- `SETUP.md` - Guía de instalación paso a paso
- `QUICK_REFERENCE.md` - Referencia rápida de comandos
- `ACCESO_Y_VERIFICACION.md` - Cómo usar pgAdmin
- `DOCUMENTACION_COMPLETA.md` - Detalles técnicos
- `MAPA_DEL_SISTEMA.md` - Diagramas de arquitectura
- `PROYECTO_COMPLETADO.md` - Resumen ejecutivo

## 🚀 Próximos Pasos

### Desarrollo Local

1. Modifica `init.sql` para cambiar el esquema
2. Ejecuta `docker-compose down -v` para limpiar
3. Ejecuta `docker-compose up -d` para reiniciar
4. Tus cambios se aplicarán automáticamente

### Ampliaciones

- Añadir tabla `payments` para pagos
- Crear tabla `shipments` para envíos
- Implementar `fn_cancel_order()` para cancelaciones
- Crear API REST (FastAPI, Flask)
- Implementar reportes (Metabase, Grafana)

### Producción

- Migrar a AWS RDS o Google Cloud SQL
- Usar secrets manager para credenciales
- Implementar SSL/TLS
- Configurar backups automáticos
- Añadir monitoreo y alertas

## 🆘 Troubleshooting

### Contenedor no arranca

```bash
docker-compose logs db
docker-compose down -v
docker-compose up -d
```

### Seed falla por duplicados

```bash
python reset_db.py
python seed_data.py
```

### No puedo conectar a pgAdmin

- Usa hostname `db` desde dentro del Docker network
- Usa `localhost` desde tu máquina host
- Espera 30 segundos para que Postgres inicie

## 📝 Licencia

MIT License - Libre para usar y modificar

## 👨‍💻 Autor

Proyecto desarrollado como demostración de arquitectura de bases de datos transaccionales con Docker y PostgreSQL.

---

**Última actualización:** 15 de Enero de 2026
**Estado:** ✅ Operacional
