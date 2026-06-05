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
    """模擬 ctx.db：x_ 表用 query_object，insert 自動配 id，update 就地改。"""
    def __init__(self, weighing=None, vehicle=None):
        self._w = [dict(r) for r in (weighing or [])]
        self._v = [dict(r) for r in (vehicle or [])]
        self.inserted = []
        self.updated = []
    def query_object(self, table, limit=500, **kw):
        if table == "x_czone_weighing":
            return [dict(r) for r in self._w]
        if table == "x_czone_vehicle":
            return [dict(r) for r in self._v]
        return []
    def insert(self, table, data):
        row = {**data, "id": f"new-{len(self.inserted) + 1}"}
        self.inserted.append((table, row))
        if table == "x_czone_weighing":
            self._w.append(row)
        return row
    def update(self, table, row_id, data):
        self.updated.append((table, row_id, data))
        for r in self._w:
            if r.get("id") == row_id:
                r.update(data)
        return {"success": True}


class FakeCtx:
    def __init__(self, params, db=None, secrets=None):
        self.params = params
        self.db = db or FakeDB()
        self.secrets = secrets or {}
        self.response = FakeResponse()
