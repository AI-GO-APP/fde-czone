# vfs/scripts/refs.py
"""DB References：Odoo 主檔唯讀；x_ 自建表（過磅紀錄、車籍）也需 ref 才能被 action 存取。

⚠️ 實測：真平台的 ctx.db.query_object 連 x_ Custom Object 都要 AppDataReference，
否則回 403「App 未被授權存取表」（與 sc1984 舊文件「x_ 不需 ref」不符，見 PLATFORM_NOTES.md）。
"""

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
    {"table_name": "x_czone_weighing",
     "columns": ["ticket_no", "plate", "customer_id", "material_id", "gross_weight",
                 "tare_weight", "net_weight", "unit_price", "amount", "first_weigh_at",
                 "second_weigh_at", "status", "has_manifest", "settle_status", "settled_at",
                 "weigh_operator", "plate_source", "plate_confidence", "weight_source",
                 "image_ref", "note"],
     "permissions": ["read", "create", "update"]},
    {"table_name": "x_czone_vehicle",
     "columns": ["plate", "default_customer_id", "default_material_id",
                 "manual_only", "note", "active"],
     "permissions": ["read", "create", "update"]},
    {"table_name": "x_czone_live_weight",
     "columns": ["key", "weight", "at", "server_at", "state"],
     "permissions": ["read", "create", "update"]},
]
