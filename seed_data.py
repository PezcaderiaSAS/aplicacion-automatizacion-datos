#!/usr/bin/env python3
"""
seed_data.py

Conecta a la base de datos local y:
  * Inserta 50 proveedores
  * Inserta 200 productos
  * Simula 100 movimientos de inventario
  * Crea 20 órdenes transaccionales
  * Prueba triggers y función ACID

Uso: python seed_data.py
"""

import os
import time
import random
from decimal import Decimal
import uuid
from faker import Faker
from dotenv import load_dotenv
import psycopg2
from psycopg2 import sql
from psycopg2.extras import execute_values, DictCursor, Json as PsycopgJson
import json

load_dotenv()

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = int(os.getenv("DB_PORT", 5432))
DB_NAME = os.getenv("POSTGRES_DB", os.getenv("DB_NAME", "appdb"))
DB_USER = os.getenv("POSTGRES_USER", "appuser")
DB_PASS = os.getenv("POSTGRES_PASSWORD", "AppUserPass123!")

RETRY_SECONDS = 5
MAX_RETRIES = 12

fake = Faker()
Faker.seed(42)
random.seed(42)

def wait_for_db():
    tries = 0
    while tries < MAX_RETRIES:
        try:
            conn = psycopg2.connect(
                host=DB_HOST, port=DB_PORT, dbname=DB_NAME, user=DB_USER, password=DB_PASS
            )
            conn.close()
            print("✔ Database reachable")
            return
        except Exception as e:
            tries += 1
            print(f"DB not ready ({tries}/{MAX_RETRIES}), retrying in {RETRY_SECONDS}s...")
            time.sleep(RETRY_SECONDS)
    raise RuntimeError("Could not connect to the database after multiple retries")

def bulk_insert_suppliers(conn, n=50):
    suppliers = []
    for i in range(n):
        name = fake.company()[:200]
        contact = f"{fake.email()} | {fake.phone_number()}"
        suppliers.append((name, contact))
    with conn.cursor() as cur:
        execute_values(
            cur,
            "INSERT INTO suppliers (nombre, contacto) VALUES %s RETURNING id, nombre",
            suppliers,
            template=None,
            page_size=100
        )
        rows = cur.fetchall()
        supplier_ids = [r[0] for r in rows]
    conn.commit()
    print(f"Inserted {len(supplier_ids)} suppliers")
    return supplier_ids

def bulk_insert_products(conn, supplier_ids, n=200):
    products = []
    sku_set = set()
    for i in range(1, n+1):
        sku = f"SKU-{i:05d}"
        if sku in sku_set:
            sku = f"SKU-{uuid.uuid4().hex[:8]}"
        sku_set.add(sku)
        name = fake.word().title() + " " + fake.word().title()
        precio = round(random.uniform(1, 1000), 2)
        stock = random.randint(0, 100)
        id_proveedor = random.choice(supplier_ids)
        products.append((sku, name, Decimal(str(precio)), stock, id_proveedor))
    with conn.cursor() as cur:
        execute_values(
            cur,
            """INSERT INTO products (sku, nombre, precio, stock, id_proveedor)
               VALUES %s RETURNING id, sku, stock""",
            products,
            template=None,
            page_size=200
        )
        rows = cur.fetchall()
        product_rows = [{"id": r[0], "sku": r[1], "stock": r[2]} for r in rows]
    conn.commit()
    print(f"Inserted {len(product_rows)} products")
    return product_rows

def simulate_movements(conn, product_rows, n=100):
    stock_map = {p["id"]: p["stock"] for p in product_rows}
    movements_done = 0
    movements_failed = 0

    for i in range(n):
        prod = random.choice(product_rows)
        prod_id = prod["id"]
        current_stock = stock_map.get(prod_id, 0)
        tipo = "entrada" if random.random() < 0.6 else "salida"
        qty = random.randint(1, 25)

        if tipo == "salida" and current_stock < qty:
            tipo = "entrada"

        try:
            with conn.cursor() as cur:
                cur.execute(
                    """INSERT INTO inventory_movements (id_producto, tipo, cantidad, nota)
                       VALUES (%s, %s, %s, %s) RETURNING id""",
                    (prod_id, tipo, qty, f"Simulación {i+1}")
                )
                mov_id = cur.fetchone()[0]
            conn.commit()
            if tipo == "entrada":
                stock_map[prod_id] = current_stock + qty
            else:
                stock_map[prod_id] = current_stock - qty
            movements_done += 1
        except Exception as e:
            conn.rollback()
            movements_failed += 1

    print(f"Movements attempted: {n}, succeeded: {movements_done}, failed: {movements_failed}")
    return movements_done, movements_failed

def simulate_orders(conn, product_rows, n=20):
    orders_done = 0
    orders_failed = 0
    product_ids = [p['id'] for p in product_rows]

    for i in range(n):
        num_lines = random.randint(1, 5)
        chosen = random.sample(product_ids, k=num_lines)
        lines = []

        with conn.cursor() as cur:
            for pid in chosen:
                cur.execute("SELECT precio, stock FROM products WHERE id = %s", (pid,))
                row = cur.fetchone()
                if not row:
                    continue
                precio, stock = row
                max_qty = max(1, min(5, stock))
                qty = random.randint(1, max_qty)
                lines.append({
                    'product_id': str(pid),
                    'cantidad': qty,
                    'precio_unit': float(precio)
                })

        if not lines:
            continue

        cliente = fake.name()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT fn_create_order(%s, %s::jsonb)", (cliente, PsycopgJson(lines)))
                order_id = cur.fetchone()[0]
            conn.commit()
            orders_done += 1
            print(f"Order created: {order_id} for {cliente} with {len(lines)} lines")
        except Exception as e:
            conn.rollback()
            orders_failed += 1
            print(f"Order failed (#{i+1}): {e}")

    print(f"Orders attempted: {n}, succeeded: {orders_done}, failed: {orders_failed}")
    return orders_done, orders_failed

def show_summary(conn):
    with conn.cursor(cursor_factory=DictCursor) as cur:
        cur.execute("SELECT count(*) FROM suppliers")
        suppliers_count = cur.fetchone()[0]
        cur.execute("SELECT count(*) FROM products")
        products_count = cur.fetchone()[0]
        cur.execute("SELECT count(*) FROM inventory_movements")
        movements_count = cur.fetchone()[0]
        cur.execute("SELECT count(*) FROM operations_log")
        logs_count = cur.fetchone()[0]

    print(f"Summary: suppliers={suppliers_count}, products={products_count}, inventory_movements={movements_count}, operations_log={logs_count}")

def main():
    wait_for_db()
    conn = psycopg2.connect(host=DB_HOST, port=DB_PORT, dbname=DB_NAME, user=DB_USER, password=DB_PASS)
    try:
        supplier_ids = bulk_insert_suppliers(conn, n=50)
        products = bulk_insert_products(conn, supplier_ids, n=200)
        simulate_movements(conn, products, n=100)
        simulate_orders(conn, products, n=20)
        show_summary(conn)
    finally:
        conn.close()

if __name__ == "__main__":
    main()
