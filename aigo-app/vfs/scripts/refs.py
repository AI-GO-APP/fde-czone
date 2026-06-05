# vfs/scripts/refs.py
"""DB References：本案只讀 Odoo 主檔；過磅紀錄與車籍為 x_ 自建表，走 query_object，不在此列。"""

REFS = [
    {"table_name": "customers",
     "columns": ["id", "name", "vat", "customer_type", "payment_term",
                 "short_name", "phone", "contact_person", "active"],
     "permissions": ["read"]},
    {"table_name": "product_templates",
     "columns": ["id", "name", "categ_id", "standard_price", "uom_id", "active"],
     "permissions": ["read"]},
    {"table_name": "product_products",
     "columns": ["id", "product_tmpl_id", "default_code", "standard_price", "active"],
     "permissions": ["read"]},
    {"table_name": "product_supplierinfo",
     "columns": ["id", "partner_id", "supplier_id", "product_id", "price",
                 "date_start", "date_end"],
     "permissions": ["read"]},
]
