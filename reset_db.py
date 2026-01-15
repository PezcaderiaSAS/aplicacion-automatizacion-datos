#!/usr/bin/env python3
"""
reset_db.py

Trunca las tablas principales y resetea las secuencias para preparar la base de datos
para un nuevo ciclo de seeding sin conflictos de claves únicas.
"""

import os
import psycopg2
from dotenv import load_dotenv

load_dotenv()

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = int(os.getenv("DB_PORT", 5432))
DB_NAME = os.getenv("POSTGRES_DB", "appdb")
DB_USER = os.getenv("POSTGRES_USER", "appuser")
DB_PASS = os.getenv("POSTGRES_PASSWORD", "AppUserPass123!")

def reset_db():
    conn = psycopg2.connect(host=DB_HOST, port=DB_PORT, dbname=DB_NAME, user=DB_USER, password=DB_PASS)
    try:
        with conn.cursor() as cur:
            # Truncate en orden de dependencias (FKs)
            print("Truncating tables...")
            cur.execute("TRUNCATE TABLE order_lines CASCADE;")
            cur.execute("TRUNCATE TABLE orders CASCADE;")
            cur.execute("TRUNCATE TABLE inventory_movements CASCADE;")
            cur.execute("TRUNCATE TABLE operations_log CASCADE;")
            cur.execute("TRUNCATE TABLE products CASCADE;")
            cur.execute("TRUNCATE TABLE suppliers CASCADE;")
            
            # Reset sequence
            print("Resetting sequences...")
            cur.execute("ALTER SEQUENCE order_number_seq RESTART WITH 1000;")
            
            conn.commit()
            print("✔ Database reset complete")
    except Exception as e:
        conn.rollback()
        print(f"Error during reset: {e}")
        raise
    finally:
        conn.close()

if __name__ == "__main__":
    reset_db()
