import sys, os
ACTIONS = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "vfs", "actions"))
sys.path.insert(0, ACTIONS)


class FakeResponse:
    def __init__(self):
        self.body = None
        self.err = None
    def json(self, data):
        self.body = data
    def error(self, msg):
        self.err = msg


class FakeDB:
    """模擬 ctx.db：Custom Object(x_) 用 query_object 讀、insert_object/update_object 寫。
    以 slug -> rows 的字典儲存，支援任意 x_ 表。"""
    def __init__(self, weighing=None, vehicle=None, live=None):
        self._store = {
            "x_czone_weighing": [dict(r) for r in (weighing or [])],
            "x_czone_vehicle": [dict(r) for r in (vehicle or [])],
            "x_czone_live_weight": [dict(r) for r in (live or [])],
        }
        self.inserted = []
        self.updated = []
    def query_object(self, slug, limit=500, **kw):
        return [dict(r) for r in self._store.get(slug, [])]
    def insert_object(self, slug, data):
        row = {**data, "id": f"new-{len(self.inserted) + 1}"}
        self.inserted.append((slug, row))
        self._store.setdefault(slug, []).append(row)
        return row
    def update_object(self, slug, record_id, data):
        self.updated.append((slug, record_id, data))
        for r in self._store.get(slug, []):
            if r.get("id") == record_id:
                r.update(data)
        return {"success": True}


class FakeCtx:
    def __init__(self, params, db=None, secrets=None):
        self.params = params
        self.db = db or FakeDB()
        self.secrets = secrets or {}
        self.response = FakeResponse()
