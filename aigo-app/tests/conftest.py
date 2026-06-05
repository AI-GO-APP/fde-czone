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
    """模擬 ctx.db：Custom Object(x_) 用 query_object 讀、insert_object/update_object 寫。"""
    def __init__(self, weighing=None, vehicle=None):
        self._w = [dict(r) for r in (weighing or [])]
        self._v = [dict(r) for r in (vehicle or [])]
        self.inserted = []
        self.updated = []
    def query_object(self, slug, limit=500, **kw):
        if slug == "x_czone_weighing":
            return [dict(r) for r in self._w]
        if slug == "x_czone_vehicle":
            return [dict(r) for r in self._v]
        return []
    def insert_object(self, slug, data):
        row = {**data, "id": f"new-{len(self.inserted) + 1}"}
        self.inserted.append((slug, row))
        if slug == "x_czone_weighing":
            self._w.append(row)
        return row
    def update_object(self, slug, record_id, data):
        self.updated.append((slug, record_id, data))
        for r in self._w:
            if r.get("id") == record_id:
                r.update(data)
        return {"success": True}


class FakeCtx:
    def __init__(self, params, db=None, secrets=None):
        self.params = params
        self.db = db or FakeDB()
        self.secrets = secrets or {}
        self.response = FakeResponse()
