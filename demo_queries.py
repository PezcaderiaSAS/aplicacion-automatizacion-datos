#!/usr/bin/env python3
"""
demo_queries.py

Ejecuta consultas de demostración contra la base de datos poblada
para mostrar:
- Órdenes creadas
- Líneas de órdenes
- Auditoría (operations_log)
"""

import os
import psycopg2
from dotenv import load_dotenv
from psycopg2.extras import RealDictCursor

load_dotenv()

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = int(os.getenv("DB_PORT", 5432))
DB_NAME = os.getenv("POSTGRES_DB", "appdb")
DB_USER = os.getenv("POSTGRES_USER", "appuser")
DB_PASS = os.getenv("POSTGRES_PASSWORD", "AppUserPass123!")

def main():
    conn = psycopg2.connect(
        host=DB_HOST, port=DB_PORT, dbname=DB_NAME, user=DB_USER, password=DB_PASS
    )
    
    print("\n" + "=" * 80)
    print("TOP 5 ÓRDENES CREADAS")
    print("=" * 80)
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            "SELECT id, order_number, cliente, total, estado, fecha FROM orders ORDER BY fecha DESC LIMIT 5"
        )
        for row in cur.fetchall():
            print(
                f"Order #{row['order_number']} | Cliente: {row['cliente']} | "
                f"Total: ${row['total']} | Estado: {row['estado']}"
            )

    print("\n" + "=" * 80)
    print("LÍNEAS DE PRIMERA ORDEN")
    print("=" * 80)
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute("SELECT id, order_number FROM orders ORDER BY fecha ASC LIMIT 1")
        first_order = cur.fetchone()
        if first_order:
            cur.execute(
                """
                SELECT ol.cantidad, ol.precio_unit, ol.subtotal, p.sku, p.nombre
                FROM order_lines ol
                JOIN products p ON ol.product_id = p.id
                WHERE ol.order_id = %s
                """,
                (first_order["id"],),
            )
            print(f"Order #{first_order['order_number']}:")
            for row in cur.fetchall():
                print(
                    f"  {row['sku']} | {row['nombre']} | Qty: {row['cantidad']} | "
                    f"Unit: ${row['precio_unit']} | Subtotal: ${row['subtotal']}"
                )

    print("\n" + "=" * 80)
    print("ÚLTIMOS 10 CAMBIOS DE STOCK (auditoría)")
    print("=" * 80)
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            """
            SELECT tipo_operacion, fecha, 
                   (detalles->>'product_id')::TEXT as product_id,
                   (detalles->>'old_stock')::INT as old_stock, 
                   (detalles->>'new_stock')::INT as new_stock
            FROM operations_log
            WHERE tipo_operacion = 'stock_update'
            ORDER BY fecha DESC
            LIMIT 10
            """
        )
        print("Type: stock_update")
        for row in cur.fetchall():
            print(
                f"  Product: {row['product_id'][:8]}... | "
                f"{row['old_stock']} → {row['new_stock']} | {row['fecha']}"
            )

    print("\n" + "=" * 80)
    print("RESUMEN DE AUDITORÍA POR TIPO")
    print("=" * 80)
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            "SELECT tipo_operacion, COUNT(*) as count FROM operations_log GROUP BY tipo_operacion"
        )
        for row in cur.fetchall():
            print(f"  {row['tipo_operacion']}: {row['count']} registros")

    print("\n" + "=" * 80)
    print("ESTADÍSTICAS GENERALES")
    print("=" * 80)
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute("SELECT COUNT(*) as count FROM suppliers")
        print(f"Suppliers: {cur.fetchone()['count']}")
        cur.execute("SELECT COUNT(*) as count FROM products")
        print(f"Products: {cur.fetchone()['count']}")
        cur.execute("SELECT COUNT(*) as count FROM orders")
        print(f"Orders: {cur.fetchone()['count']}")
        cur.execute("SELECT COUNT(*) as count FROM order_lines")
        print(f"Order Lines: {cur.fetchone()['count']}")
        cur.execute("SELECT COUNT(*) as count FROM inventory_movements")
        print(f"Inventory Movements: {cur.fetchone()['count']}")
        cur.execute("SELECT COUNT(*) as count FROM operations_log")
        print(f"Operations Log (audits): {cur.fetchone()['count']}")

    conn.close()
    print("\n✔ Demo queries complete\n")

if __name__ == "__main__":
    main()
