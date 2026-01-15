# REFERENCIA RÁPIDA

## 🚀 Comandos Rápidos (Copiar/Pegar)

### Iniciar todo
```powershell
cd "c:\Users\usuario\OneDrive\Documentos\Documentos Pezca\Frios\Nueva App"
docker-compose up -d
```

### Ver estado de contenedores
```powershell
docker-compose ps
```

### Ver logs de Postgres
```powershell
docker-compose logs -f db
```

### Poblar base de datos
```powershell
python .\reset_db.py
python .\seed_data.py
```

### Ver datos (consola)
```powershell
python .\demo_queries.py
```

### Acceso pgAdmin
```
URL:      http://localhost:8080
Email:    admin@example.com
Password: AdminPass123!
```

### Conexión Postgres desde Python
```python
import psycopg2

conn = psycopg2.connect(
    host="localhost",
    port=5432,
    database="appdb",
    user="appuser",
    password="AppUserPass123!"
)
cur = conn.cursor()
# ... ejecutar queries ...
conn.close()
```

### Conexión Postgres desde línea de comandos
```powershell
# Necesitas psql instalado (viene con Postgres)
psql -h localhost -U appuser -d appdb -c "SELECT COUNT(*) FROM orders;"
```

---

## 📊 Queries Clave

### Orden específica y sus líneas
```sql
SELECT o.order_number, o.cliente, o.total, ol.cantidad, ol.precio_unit, p.sku, p.nombre
FROM orders o
JOIN order_lines ol ON o.id = ol.order_id
JOIN products p ON ol.product_id = p.id
WHERE o.order_number = 1005
ORDER BY ol.id;
```

### Auditoría de movimientos de un producto
```sql
SELECT m.tipo, m.cantidad, m.fecha, m.nota
FROM inventory_movements m
WHERE m.id_producto = (SELECT id FROM products WHERE sku = 'SKU-00001' LIMIT 1)
ORDER BY m.fecha DESC;
```

### Stock disponible (bajo stock)
```sql
SELECT sku, nombre, stock, precio
FROM products
WHERE stock < 20
ORDER BY stock ASC
LIMIT 20;
```

### Resumen de órdenes
```sql
SELECT 
  COUNT(*) as total_orders,
  SUM(total) as total_revenue,
  AVG(total) as avg_order_value,
  COUNT(DISTINCT cliente) as unique_customers
FROM orders
WHERE estado = 'placed';
```

---

## 🗂️ Archivos Principales

| Archivo | Descripción |
|---------|-------------|
| `docker-compose.yml` | Orquestación de servicios (Postgres + pgAdmin) |
| `.env` | Variables de entorno (NO compartir en producción) |
| `init.sql` | Schema SQL con tablas, triggers, funciones |
| `seed_data.py` | Inserta 50 suppliers, 200 products, simula órdenes |
| `reset_db.py` | Trunca tablas para reiniciar datos |
| `demo_queries.py` | Muestra datos en consola |
| `requirements.txt` | Dependencias Python (psycopg2, Faker, python-dotenv) |
| `README.md` | Instrucciones básicas |
| `DOCUMENTACION_COMPLETA.md` | Documentación técnica detallada |
| `ACCESO_Y_VERIFICACION.md` | Cómo acceder y verificar datos |
| `QUICK_REFERENCE.md` | Este archivo |

---

## 🔑 Claves y Características

### Triggers (Automáticos)
1. **Stock Audit Trigger** → Registra cambios de stock en `operations_log`
2. **Stock Adjustment Trigger** → Decrementa stock cuando se crea un movimiento 'salida'

### Función Transaccional ACID
- **fn_create_order()** → Crea orden completa (atomicidad garantizada)
- Bloquea filas de productos
- Verifica stock
- Si falla: ROLLBACK automático

### Constraints (Protección de Datos)
- Stock >= 0 (CHECK)
- Cantidad > 0 (CHECK)
- SKU único (UNIQUE)
- Foreign Keys con RESTRICT/CASCADE

---

## 📈 Estadísticas Ejecutadas

```
Suppliers:            50
Products:             200
Inventory Movements:  146
Orders Created:       17 exitosas + 3 fallidas
Audit Logs:           409 registros
```

---

## 🎯 Próximos Pasos (Opcionales)

1. Crear función `fn_cancel_order()` para cancelar pedidos
2. Añadir tabla `payments` para pagos
3. Implementar dashboard con Metabase o Grafana
4. Crear API REST con FastAPI o Flask
5. Migrar a AWS RDS o Google Cloud SQL

---

## 📞 Comandos de Emergencia

```powershell
# Parar todo sin borrar datos
docker-compose stop

# Reanudar servicios
docker-compose start

# Reiniciar todo (mantiene volúmenes)
docker-compose restart

# Detener y eliminar contenedores (mantiene datos)
docker-compose down

# Detener y eliminar TODO (incluye volúmenes de datos)
docker-compose down -v

# Ver contenedores activos
docker ps -a

# Ver logs en tiempo real
docker logs -f <container_name>

# Acceder a la terminal de Postgres
docker exec -it app_db psql -U appuser -d appdb
```

---

**Última actualización:** 15 de Enero de 2026
**Estado:** ✅ Operacional
