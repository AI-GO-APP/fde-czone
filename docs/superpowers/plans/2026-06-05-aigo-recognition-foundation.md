# aigo 車牌+磅數辨識地基 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 aigo 雲端端「離線可完成」的地基：兩張自建表的契約、三支 Action（含可本地單元測試的過磅配對邏輯）、部署腳本，讓核心路徑（辨識→雲端→寫回）有可驗證的骨架。

**Architecture:** 業務邏輯寫成 module 層級**純函式**（配對、算淨重、產單號、組列印 payload），本地 pytest 直接 import 測試，不需平台或金鑰；`execute(ctx)` 用假 ctx 測。辨識/OCR 採「secrets 無金鑰即回 mock、有金鑰自動切真呼叫」。主檔走已驗證存在的 Odoo 表，僅過磅紀錄與車籍自建。

**Tech Stack:** Python 3.12（AI GO Action 沙盒：json/re/datetime/httpx 白名單）、pytest 9、AI GO Custom App 部署 API（沿用桌面 `fde-sc1984/scripts/deploy_admin.py` 模式）。

**參考規格：** `docs/superpowers/specs/2026-06-05-aigo-車牌磅數辨識-design.md`

---

## 檔案結構

```
fde-czone/
├─ shared/
│  └─ CONTRACT.md                     # agent↔aigo 契約 + 列印 payload 欄位（契約來源）
├─ aigo-app/
│  ├─ vfs/
│  │  ├─ actions/
│  │  │  ├─ manifest.json             # Action 登錄表
│  │  │  ├─ recognize_plate.py        # 車牌辨識（mock/真切換）
│  │  │  ├─ read_weight.py            # 磅數 OCR（mock/真切換）
│  │  │  └─ weigh.py                  # 過磅配對核心（純函式 + execute）
│  │  ├─ scripts/
│  │  │  └─ refs.py                   # REFS 定義（Odoo 表授權）
│  │  └─ src/
│  │     ├─ main.tsx                  # 最小前端 stub（讓 compile 過）
│  │     └─ App.tsx
│  ├─ scripts/
│  │  └─ deploy.py                    # 部署腳本
│  ├─ tests/
│  │  ├─ conftest.py                  # FakeCtx / FakeDB / sys.path
│  │  ├─ test_ticket_no.py
│  │  ├─ test_net_weight.py
│  │  ├─ test_weigh_decision.py
│  │  ├─ test_print_payload.py
│  │  └─ test_weigh_execute.py
│  └─ pytest.ini
└─ .env.example                       # AIGO_EMAIL / AIGO_PASSWORD / AIGO_APP_ID（值不入 repo）
```

> 沙盒限制：Action 檔在沙盒內**不保證能 import 同目錄其他 .py**，故每支 action 自我完備（純函式放在自己的 module 層級）。本地測試直接 import 該 action 檔取用其純函式。

---

### Task 1: Repo 骨架與契約文件

**Files:**
- Create: `shared/CONTRACT.md`
- Create: `.env.example`
- Create: `aigo-app/pytest.ini`
- Create: `aigo-app/tests/conftest.py`

- [ ] **Step 1: 建立 `.env.example`**

```bash
# 值不入 repo；實際值放本機 .env（已 gitignore）或密碼管理工具
AIGO_EMAIL=admin@czone.com
AIGO_PASSWORD=
AIGO_APP_ID=09718e5c-121d-4e09-af24-8fb3dab5b037
```

- [ ] **Step 2: 建立 `shared/CONTRACT.md`**

```markdown
# agent ↔ aigo 契約

## weigh 請求（agent 用 API Key 呼叫）
| 欄位 | 必填 | 說明 |
|---|---|---|
| image | 是 | base64 或 URL；含車牌、盡量含磅數顯示器 |
| weight | 否 | OCR 失敗/未啟用時的人工讀數（公噸） |
| weigh_operator | 是 | 過磅人員 |
| manual_plate | 否 | 辨識失敗時人工指定車牌 |

## weigh 回應
| 欄位 | 說明 |
|---|---|
| ticket_no | 單號 YYYYMMDD-NNN |
| event | first(一磅) / second(二磅) |
| plate / customer_id / gross_weight / tare_weight / net_weight | 過磅結果 |
| print_payload | 見下 |
| needs_manual | 需人工補的欄位清單，如 ["customer"]、["material"] |

## 列印 payload（對齊 Fast Report SR_ 欄位）
company, SR_Sn(單號), SR_Tn(車號), SR_Date, SR_User(人員),
SR_Direction(進/出), SR_Material(料種), SR_GwTon(毛重), SR_TwTon(空重), SR_NwTon(淨重)
```

- [ ] **Step 3: 建立 `aigo-app/pytest.ini`**

```ini
[pytest]
testpaths = tests
python_files = test_*.py
```

- [ ] **Step 4: 建立 `aigo-app/tests/conftest.py`**

```python
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
```

- [ ] **Step 5: 驗證 pytest 可收集（尚無測試）**

Run: `cd aigo-app && python3 -m pytest -q`
Expected: `no tests ran`（不報 import 錯）

- [ ] **Step 6: Commit**

```bash
git add shared/CONTRACT.md .env.example aigo-app/pytest.ini aigo-app/tests/conftest.py
git commit -m "chore: 建立 aigo-app 骨架與 agent↔aigo 契約，為地基鋪設可測試基礎"
```

---

### Task 2: 單號產生（純函式 TDD）

**Files:**
- Create: `aigo-app/vfs/actions/weigh.py`
- Test: `aigo-app/tests/test_ticket_no.py`

- [ ] **Step 1: 寫失敗測試**

```python
# tests/test_ticket_no.py
from weigh import make_ticket_no

def test_ticket_no_pads_sequence_to_three_digits():
    assert make_ticket_no("20260602", 1) == "20260602-001"

def test_ticket_no_keeps_three_digits_for_large_seq():
    assert make_ticket_no("20260602", 42) == "20260602-042"
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `cd aigo-app && python3 -m pytest tests/test_ticket_no.py -v`
Expected: FAIL（`ModuleNotFoundError: No module named 'weigh'`）

- [ ] **Step 3: 建立 `weigh.py` 並寫最小實作**

```python
# vfs/actions/weigh.py
"""過磅配對 Action：辨識結果→查車籍→判斷一磅/二磅→配對算淨重→寫表→回列印 payload。"""
from datetime import datetime

WEIGHING_TABLE = "x_czone_weighing"
VEHICLE_TABLE = "x_czone_vehicle"
STATUS_OPEN = "open"
STATUS_DONE = "done"


def make_ticket_no(date_str, seq):
    """date_str='YYYYMMDD'，seq 從 1 起。回 'YYYYMMDD-001'。"""
    return f"{date_str}-{seq:03d}"
```

- [ ] **Step 4: 跑測試確認通過**

Run: `cd aigo-app && python3 -m pytest tests/test_ticket_no.py -v`
Expected: PASS（2 passed）

- [ ] **Step 5: Commit**

```bash
git add aigo-app/vfs/actions/weigh.py aigo-app/tests/test_ticket_no.py
git commit -m "feat: 單號採當日流水格式，便於現場辨識與對帳"
```

---

### Task 3: 淨重計算（純函式 TDD）

**Files:**
- Modify: `aigo-app/vfs/actions/weigh.py`
- Test: `aigo-app/tests/test_net_weight.py`

- [ ] **Step 1: 寫失敗測試**

```python
# tests/test_net_weight.py
from weigh import compute_net_weight

def test_net_weight_is_gross_minus_tare():
    assert compute_net_weight(25.0, 10.0) == 15.0

def test_net_weight_rounds_to_three_decimals():
    assert compute_net_weight(25.1239, 10.0) == 15.124

def test_net_weight_accepts_numeric_strings():
    assert compute_net_weight("25", "10") == 15.0
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `cd aigo-app && python3 -m pytest tests/test_net_weight.py -v`
Expected: FAIL（`ImportError: cannot import name 'compute_net_weight'`）

- [ ] **Step 3: 加入實作（append 到 weigh.py，`make_ticket_no` 之後）**

```python
def compute_net_weight(gross, tare):
    """淨重 = 毛重 − 空重，單位公噸，取小數 3 位。"""
    return round(float(gross) - float(tare), 3)
```

- [ ] **Step 4: 跑測試確認通過**

Run: `cd aigo-app && python3 -m pytest tests/test_net_weight.py -v`
Expected: PASS（3 passed）

- [ ] **Step 5: Commit**

```bash
git add aigo-app/vfs/actions/weigh.py aigo-app/tests/test_net_weight.py
git commit -m "feat: 淨重取小數三位，符合公噸計量精度"
```

---

### Task 4: 一磅/二磅判定與紀錄建構（純函式 TDD）

**Files:**
- Modify: `aigo-app/vfs/actions/weigh.py`
- Test: `aigo-app/tests/test_weigh_decision.py`

- [ ] **Step 1: 寫失敗測試**

```python
# tests/test_weigh_decision.py
from weigh import decide_event, build_first_record, build_second_update, STATUS_OPEN, STATUS_DONE

def test_no_open_record_means_first_weigh():
    assert decide_event(None) == "first"

def test_existing_open_record_means_second_weigh():
    assert decide_event({"id": "x", "status": STATUS_OPEN}) == "second"

def test_first_record_holds_gross_and_is_open():
    rec = build_first_record(
        ticket_no="20260602-001", plate="ABC-1234", customer_id="cust-1",
        weight=25.0, now_iso="2026-06-02T11:57:18", plate_source="alpr",
        plate_confidence=0.93, weight_source="manual",
        weigh_operator="王小明", image_ref=None,
    )
    assert rec["gross_weight"] == 25.0
    assert rec["tare_weight"] is None
    assert rec["net_weight"] is None
    assert rec["status"] == STATUS_OPEN
    assert rec["material_id"] is None

def test_second_update_fills_tare_net_and_marks_done():
    open_rec = {"gross_weight": 25.0}
    upd = build_second_update(open_rec, weight=10.0, now_iso="2026-06-02T12:05:54")
    assert upd["tare_weight"] == 10.0
    assert upd["net_weight"] == 15.0
    assert upd["second_weigh_at"] == "2026-06-02T12:05:54"
    assert upd["status"] == STATUS_DONE
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `cd aigo-app && python3 -m pytest tests/test_weigh_decision.py -v`
Expected: FAIL（`ImportError: cannot import name 'decide_event'`）

- [ ] **Step 3: 加入實作（append 到 weigh.py）**

```python
def decide_event(open_record):
    """無 open 紀錄→'first'(一磅)；有→'second'(二磅)。"""
    return "second" if open_record else "first"


def build_first_record(ticket_no, plate, customer_id, weight, now_iso,
                       plate_source, plate_confidence, weight_source,
                       weigh_operator, image_ref):
    """一磅：建立新過磅紀錄的完整欄位 dict。"""
    return {
        "ticket_no": ticket_no,
        "plate": plate,
        "customer_id": customer_id,
        "material_id": None,
        "gross_weight": float(weight),
        "tare_weight": None,
        "net_weight": None,
        "unit_price": None,
        "amount": None,
        "first_weigh_at": now_iso,
        "second_weigh_at": None,
        "status": STATUS_OPEN,
        "has_manifest": False,
        "settle_status": "unsettled",
        "settled_at": None,
        "weigh_operator": weigh_operator,
        "plate_source": plate_source,
        "plate_confidence": plate_confidence,
        "weight_source": weight_source,
        "image_ref": image_ref,
        "note": "",
    }


def build_second_update(open_record, weight, now_iso):
    """二磅：回傳要 update 的欄位 dict（空重/淨重/出場時間/完成）。"""
    return {
        "tare_weight": float(weight),
        "net_weight": compute_net_weight(open_record["gross_weight"], weight),
        "second_weigh_at": now_iso,
        "status": STATUS_DONE,
    }
```

- [ ] **Step 4: 跑測試確認通過**

Run: `cd aigo-app && python3 -m pytest tests/test_weigh_decision.py -v`
Expected: PASS（4 passed）

- [ ] **Step 5: Commit**

```bash
git add aigo-app/vfs/actions/weigh.py aigo-app/tests/test_weigh_decision.py
git commit -m "feat: 以車號有無未完成紀錄判定一磅/二磅，支撐連續車與同車多次過磅"
```

---

### Task 5: 列印 payload 建構（純函式 TDD）

**Files:**
- Modify: `aigo-app/vfs/actions/weigh.py`
- Test: `aigo-app/tests/test_print_payload.py`

- [ ] **Step 1: 寫失敗測試**

```python
# tests/test_print_payload.py
from weigh import build_print_payload

def test_payload_maps_record_to_fast_report_fields():
    record = {
        "ticket_no": "20260602-001", "plate": "ABC-1234",
        "first_weigh_at": "2026-06-02T11:57:18", "second_weigh_at": None,
        "weigh_operator": "王小明", "material_name": "廢木料-棧板",
        "gross_weight": 25.0, "tare_weight": None, "net_weight": None,
    }
    payload = build_print_payload(record, "進")
    assert payload["company"] == "薪榮環保股份有限公司"
    assert payload["SR_Sn"] == "20260602-001"
    assert payload["SR_Tn"] == "ABC-1234"
    assert payload["SR_Date"] == "2026-06-02T11:57:18"
    assert payload["SR_User"] == "王小明"
    assert payload["SR_Direction"] == "進"
    assert payload["SR_Material"] == "廢木料-棧板"
    assert payload["SR_GwTon"] == 25.0

def test_payload_date_prefers_second_weigh_time():
    record = {"first_weigh_at": "A", "second_weigh_at": "B"}
    assert build_print_payload(record, "出")["SR_Date"] == "B"

def test_payload_material_defaults_to_empty():
    assert build_print_payload({}, "進")["SR_Material"] == ""
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `cd aigo-app && python3 -m pytest tests/test_print_payload.py -v`
Expected: FAIL（`ImportError: cannot import name 'build_print_payload'`）

- [ ] **Step 3: 加入實作（append 到 weigh.py）**

```python
def build_print_payload(record, direction):
    """組三聯磅單列印 payload（對齊 Fast Report SR_ 欄位）。"""
    return {
        "company": "薪榮環保股份有限公司",
        "SR_Sn": record.get("ticket_no"),
        "SR_Tn": record.get("plate"),
        "SR_Date": record.get("second_weigh_at") or record.get("first_weigh_at"),
        "SR_User": record.get("weigh_operator"),
        "SR_Direction": direction,
        "SR_Material": record.get("material_name") or "",
        "SR_GwTon": record.get("gross_weight"),
        "SR_TwTon": record.get("tare_weight"),
        "SR_NwTon": record.get("net_weight"),
    }
```

- [ ] **Step 4: 跑測試確認通過**

Run: `cd aigo-app && python3 -m pytest tests/test_print_payload.py -v`
Expected: PASS（3 passed）

- [ ] **Step 5: Commit**

```bash
git add aigo-app/vfs/actions/weigh.py aigo-app/tests/test_print_payload.py
git commit -m "feat: 列印 payload 對齊 Fast Report 欄位，銜接三聯磅單版面"
```

---

### Task 6: `weigh.execute(ctx)` 整合（用假 ctx TDD）

**Files:**
- Modify: `aigo-app/vfs/actions/weigh.py`
- Test: `aigo-app/tests/test_weigh_execute.py`

- [ ] **Step 1: 寫失敗測試**

```python
# tests/test_weigh_execute.py
import weigh
from conftest import FakeCtx, FakeDB

def test_first_weigh_inserts_open_record_with_default_customer():
    db = FakeDB(weighing=[], vehicle=[{"plate": "ABC-1234", "default_customer_id": "cust-1"}])
    ctx = FakeCtx({"plate": "ABC-1234", "weight": 25.0, "weigh_operator": "王小明",
                   "now": "2026-06-02T11:57:18"}, db=db)
    weigh.execute(ctx)
    assert ctx.response.body["event"] == "first"
    assert ctx.response.body["ticket_no"] == "20260602-001"
    assert ctx.response.body["customer_id"] == "cust-1"
    assert len(db.inserted) == 1
    assert db.inserted[0][1]["status"] == "open"

def test_second_weigh_updates_matching_open_record():
    open_rec = {"id": "rec-1", "plate": "ABC-1234", "status": "open",
                "gross_weight": 25.0, "ticket_no": "20260602-001",
                "first_weigh_at": "2026-06-02T11:57:18"}
    db = FakeDB(weighing=[open_rec], vehicle=[])
    ctx = FakeCtx({"plate": "ABC-1234", "weight": 10.0, "weigh_operator": "王小明",
                   "now": "2026-06-02T12:05:54"}, db=db)
    weigh.execute(ctx)
    assert ctx.response.body["event"] == "second"
    assert ctx.response.body["net_weight"] == 15.0
    assert db.updated[0][1] == "rec-1"
    assert db.updated[0][2]["status"] == "done"
    assert ctx.response.body["needs_manual"] == ["material"]

def test_missing_weight_returns_error():
    ctx = FakeCtx({"plate": "ABC-1234", "weigh_operator": "王小明"})
    weigh.execute(ctx)
    assert ctx.response.err is not None

def test_first_weigh_without_known_vehicle_flags_manual_customer():
    db = FakeDB(weighing=[], vehicle=[])
    ctx = FakeCtx({"plate": "NEW-9999", "weight": 20.0, "weigh_operator": "王",
                   "now": "2026-06-02T09:00:00"}, db=db)
    weigh.execute(ctx)
    assert ctx.response.body["customer_id"] is None
    assert ctx.response.body["needs_manual"] == ["customer"]
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `cd aigo-app && python3 -m pytest tests/test_weigh_execute.py -v`
Expected: FAIL（`AttributeError: module 'weigh' has no attribute 'execute'`）

- [ ] **Step 3: 加入 helper 與 execute（append 到 weigh.py）**

```python
def _today_seq(ctx, date_str):
    rows = ctx.db.query_object(WEIGHING_TABLE, limit=500)
    return sum(1 for r in rows if str(r.get("ticket_no", "")).startswith(date_str)) + 1


def _find_open(ctx, plate):
    rows = ctx.db.query_object(WEIGHING_TABLE, limit=500)
    opens = [r for r in rows if r.get("plate") == plate and r.get("status") == STATUS_OPEN]
    opens.sort(key=lambda r: r.get("first_weigh_at", ""))
    return opens[0] if opens else None


def _lookup_vehicle(ctx, plate):
    for r in ctx.db.query_object(VEHICLE_TABLE, limit=500):
        if r.get("plate") == plate:
            return r
    return None


def execute(ctx):
    p = ctx.params
    plate = p.get("plate")
    weight = p.get("weight")
    if not plate or weight is None:
        ctx.response.error("缺少 plate 或 weight")
        return

    now = p.get("now") or datetime.utcnow().isoformat()
    open_rec = _find_open(ctx, plate)

    if decide_event(open_rec) == "first":
        veh = _lookup_vehicle(ctx, plate)
        customer_id = veh.get("default_customer_id") if veh else None
        date_str = now[:10].replace("-", "")
        ticket_no = make_ticket_no(date_str, _today_seq(ctx, date_str))
        rec = build_first_record(
            ticket_no, plate, customer_id, weight, now,
            p.get("plate_source", "manual"), p.get("plate_confidence"),
            p.get("weight_source", "manual"), p.get("weigh_operator", ""),
            p.get("image_ref"),
        )
        ctx.db.insert(WEIGHING_TABLE, rec)
        ctx.response.json({
            "ticket_no": ticket_no, "event": "first", "plate": plate,
            "customer_id": customer_id, "gross_weight": rec["gross_weight"],
            "tare_weight": None, "net_weight": None,
            "manual_only": bool(veh.get("manual_only")) if veh else False,
            "print_payload": build_print_payload(rec, "進"),
            "needs_manual": [] if customer_id else ["customer"],
        })
    else:
        upd = build_second_update(open_rec, weight, now)
        ctx.db.update(WEIGHING_TABLE, open_rec["id"], upd)
        merged = {**open_rec, **upd}
        ctx.response.json({
            "ticket_no": open_rec.get("ticket_no"), "event": "second",
            "plate": plate, "customer_id": open_rec.get("customer_id"),
            "gross_weight": open_rec.get("gross_weight"),
            "tare_weight": upd["tare_weight"], "net_weight": upd["net_weight"],
            "print_payload": build_print_payload(merged, "出"),
            "needs_manual": ["material"],
        })
```

- [ ] **Step 4: 跑測試確認通過**

Run: `cd aigo-app && python3 -m pytest tests/test_weigh_execute.py -v`
Expected: PASS（4 passed）

- [ ] **Step 5: 跑全部測試**

Run: `cd aigo-app && python3 -m pytest -v`
Expected: PASS（全綠，共 16 passed）

- [ ] **Step 6: Commit**

```bash
git add aigo-app/vfs/actions/weigh.py aigo-app/tests/test_weigh_execute.py
git commit -m "feat: weigh 串接配對與寫表，未知車與二磅各自標記人工補欄位"
```

---

### Task 7: `recognize_plate` Action（mock/真切換）

**Files:**
- Create: `aigo-app/vfs/actions/recognize_plate.py`
- Test: `aigo-app/tests/test_recognize_plate.py`

- [ ] **Step 1: 寫失敗測試**

```python
# tests/test_recognize_plate.py
import recognize_plate
from conftest import FakeCtx

def test_returns_mock_when_no_alpr_key():
    ctx = FakeCtx({"image": "<base64>"}, secrets={})
    recognize_plate.execute(ctx)
    assert ctx.response.body["mock"] is True
    assert "plate" in ctx.response.body

def test_errors_when_no_image():
    ctx = FakeCtx({}, secrets={})
    recognize_plate.execute(ctx)
    assert ctx.response.err is not None
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `cd aigo-app && python3 -m pytest tests/test_recognize_plate.py -v`
Expected: FAIL（`ModuleNotFoundError: No module named 'recognize_plate'`）

- [ ] **Step 3: 寫實作**

```python
# vfs/actions/recognize_plate.py
"""車牌辨識：secrets 無 alpr_key 時回 mock；有 key 時打 Plate Recognizer。"""

ALPR_URL = "https://api.platerecognizer.com/v1/plate-reader/"


def execute(ctx):
    image = ctx.params.get("image")
    if not image:
        ctx.response.error("缺少 image")
        return

    key = ctx.secrets.get("alpr_key")
    if not key:
        ctx.response.json({"plate": "MOCK-0000", "confidence": 0.0, "mock": True})
        return

    # 真呼叫（HTTP 細節於 Spike 用真實金鑰+測試圖驗證並校正）
    import httpx
    resp = httpx.post(
        ALPR_URL,
        headers={"Authorization": f"Token {key}"},
        data={"regions": "tw", "upload": image},
        timeout=20,
    )
    data = resp.json()
    results = data.get("results", [])
    if not results:
        ctx.response.json({"plate": None, "confidence": 0.0, "mock": False})
        return
    top = results[0]
    ctx.response.json({
        "plate": top.get("plate", "").upper(),
        "confidence": top.get("score", 0.0),
        "mock": False,
    })
```

- [ ] **Step 4: 跑測試確認通過**

Run: `cd aigo-app && python3 -m pytest tests/test_recognize_plate.py -v`
Expected: PASS（2 passed）

- [ ] **Step 5: Commit**

```bash
git add aigo-app/vfs/actions/recognize_plate.py aigo-app/tests/test_recognize_plate.py
git commit -m "feat: 車牌辨識以金鑰有無切換 mock/真呼叫，金鑰未到位也能跑通流程"
```

---

### Task 8: `read_weight` Action（mock/真切換）

**Files:**
- Create: `aigo-app/vfs/actions/read_weight.py`
- Test: `aigo-app/tests/test_read_weight.py`

- [ ] **Step 1: 寫失敗測試**

```python
# tests/test_read_weight.py
import read_weight
from conftest import FakeCtx

def test_returns_mock_when_ocr_disabled():
    ctx = FakeCtx({"image": "<base64>"}, secrets={})
    read_weight.execute(ctx)
    assert ctx.response.body["mock"] is True
    assert ctx.response.body["weight"] is None  # mock 不假裝讀到重量

def test_errors_when_no_image():
    ctx = FakeCtx({}, secrets={})
    read_weight.execute(ctx)
    assert ctx.response.err is not None
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `cd aigo-app && python3 -m pytest tests/test_read_weight.py -v`
Expected: FAIL（`ModuleNotFoundError: No module named 'read_weight'`）

- [ ] **Step 3: 寫實作**

```python
# vfs/actions/read_weight.py
"""磅數 OCR：未啟用(secrets 無 ocr_enabled)時回 mock(weight=None)，由 weigh 改吃人工輸入。
七段顯示器 OCR 的真實實作待客戶提供清晰畫面、驗證可行性後補上（規格第 5、10 節）。"""


def execute(ctx):
    image = ctx.params.get("image")
    if not image:
        ctx.response.error("缺少 image")
        return

    if not ctx.secrets.get("ocr_enabled"):
        # 未啟用：不假裝讀到數字，回 None 讓上游改用人工讀數
        ctx.response.json({"weight": None, "confidence": 0.0, "mock": True})
        return

    # 真 OCR 待實作（Spike 後）；先以未啟用行為回應，避免回假數字誤導現場
    ctx.response.json({"weight": None, "confidence": 0.0, "mock": False})
```

- [ ] **Step 4: 跑測試確認通過**

Run: `cd aigo-app && python3 -m pytest tests/test_read_weight.py -v`
Expected: PASS（2 passed）

- [ ] **Step 5: Commit**

```bash
git add aigo-app/vfs/actions/read_weight.py aigo-app/tests/test_read_weight.py
git commit -m "feat: 磅數 OCR 未啟用時回空值而非假數字，避免誤導現場過磅"
```

---

### Task 9: Action manifest 與 REFS 定義

**Files:**
- Create: `aigo-app/vfs/actions/manifest.json`
- Create: `aigo-app/vfs/scripts/refs.py`
- Create: `aigo-app/vfs/src/main.tsx`
- Create: `aigo-app/vfs/src/App.tsx`

- [ ] **Step 1: 建立 `manifest.json`**

```json
{
  "actions": [
    {"name": "recognize_plate", "file": "recognize_plate.py", "description": "車牌辨識"},
    {"name": "read_weight", "file": "read_weight.py", "description": "磅數 OCR"},
    {"name": "weigh", "file": "weigh.py", "description": "過磅配對與寫表"}
  ]
}
```

- [ ] **Step 2: 建立 `refs.py`（Odoo 表授權；x_ 表不需授權層）**

```python
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
```

- [ ] **Step 3: 建立最小前端 stub（讓 compile 通過）**

```tsx
// vfs/src/App.tsx
export default function App() {
  return <div style={{ padding: 24 }}>薪榮地磅 — aigo 後端地基（UI 待後續階段）</div>;
}
```

```tsx
// vfs/src/main.tsx
import { createRoot } from "react-dom/client";
import App from "./App";

createRoot(document.getElementById("root")!).render(<App />);
```

- [ ] **Step 4: 驗證 JSON 與 Python 語法**

Run: `cd aigo-app && python3 -c "import json; json.load(open('vfs/actions/manifest.json'))" && python3 -c "import ast; ast.parse(open('vfs/scripts/refs.py').read())" && echo OK`
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add aigo-app/vfs/actions/manifest.json aigo-app/vfs/scripts/refs.py aigo-app/vfs/src/
git commit -m "chore: 登錄三支 action 並定義 Odoo 主檔讀取授權，備妥可部署的 VFS"
```

---

### Task 10: 部署腳本（沿用 sc1984 模式）

**Files:**
- Create: `aigo-app/scripts/deploy.py`

- [ ] **Step 1: 寫部署腳本**

> 改寫自桌面 `fde-sc1984/scripts/deploy_admin.py`：REFS 改 import 自 `vfs/scripts/refs.py`，VFS 目錄指向 `aigo-app/vfs`，app_id 走環境變數。

```python
# aigo-app/scripts/deploy.py
"""薪榮 aigo 內部應用部署：登入→設 References→上傳 VFS→編譯→發布。
用法：set -a && source .env && set +a && python3 aigo-app/scripts/deploy.py"""
import json, sys, os, urllib.request, urllib.error

API_BASE = "https://ai-go.app/api/v1"
HERE = os.path.dirname(__file__)
VFS_DIR = os.path.join(HERE, "..", "vfs")
sys.path.insert(0, os.path.join(HERE, "..", "vfs", "scripts"))
from refs import REFS


def _req(method, url, headers, data=None, timeout=30):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


def _env(key):
    val = os.environ.get(key, "").strip()
    if not val:
        sys.exit(f"❌ 環境變數 {key} 未設定")
    return val


def login(email, password):
    s, b = _req("POST", f"{API_BASE}/auth/login",
                {"Content-Type": "application/json"},
                {"email": email, "password": password})
    if s != 200 or not b.get("access_token"):
        sys.exit(f"❌ 登入失敗：{s} {b}")
    return b["access_token"]


def ensure_references(h, app_id):
    s, b = _req("GET", f"{API_BASE}/refs/apps/{app_id}", h)
    existing = {x["table_name"]: x for x in (b if s == 200 else [])}
    for t in REFS:
        tn = t["table_name"]
        if tn in existing:
            s2, _ = _req("PATCH", f"{API_BASE}/refs/{existing[tn]['id']}", h,
                         {"columns": t["columns"], "permissions": t["permissions"]})
        else:
            s2, _ = _req("POST", f"{API_BASE}/refs/apps/{app_id}", h, t)
        print(f"  [{tn}] {s2}")


def read_vfs(vfs_dir):
    vfs = {}
    for root, _, files in os.walk(vfs_dir):
        for fname in files:
            full = os.path.join(root, fname)
            rel = os.path.relpath(full, vfs_dir).replace(os.sep, "/")
            with open(full, "r", encoding="utf-8") as f:
                vfs[rel] = f.read()
    return vfs


def main():
    email, password, app_id = _env("AIGO_EMAIL"), _env("AIGO_PASSWORD"), _env("AIGO_APP_ID")
    print("[1/4] 登入...")
    h = {"Authorization": f"Bearer {login(email, password)}", "Content-Type": "application/json"}
    print("[2/4] 設定 DB References...")
    ensure_references(h, app_id)
    print("[3/4] 上傳 VFS...")
    vfs = read_vfs(VFS_DIR)
    s, b = _req("PUT", f"{API_BASE}/builder/apps/{app_id}/source", h, {"vfs_state": vfs}, timeout=60)
    print(f"  上傳: {s}")
    if s != 200:
        sys.exit(f"❌ 上傳失敗：{b}")
    print("[3.5/4] 編譯...")
    s, b = _req("GET", f"{API_BASE}/builder/apps/{app_id}", h)
    slug = b.get("slug", app_id)
    s2, r = _req("POST", f"{API_BASE}/compile/compile/{slug}", h, {}, timeout=60)
    if not r.get("success"):
        sys.exit(f"❌ 編譯失敗：{r.get('error')}")
    print("  編譯：成功")
    print("[4/4] 發布...")
    s, b = _req("POST", f"{API_BASE}/builder/apps/{app_id}/publish", h, {"published_assets": {}})
    print(f"  發布: {s}")
    if s not in (200, 201):
        sys.exit(f"❌ 發布失敗：{b}")
    print("✅ 部署完成")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: 驗證腳本語法（不實際呼叫平台）**

Run: `cd aigo-app && python3 -c "import ast; ast.parse(open('scripts/deploy.py').read()); print('syntax OK')"`
Expected: `syntax OK`

- [ ] **Step 3: Commit**

```bash
git add aigo-app/scripts/deploy.py
git commit -m "chore: 部署腳本沿用 sc1984 驗證過的登入→授權→上傳→編譯→發布流程"
```

---

### Task 11: 部署與寫回 smoke test（需平台，對應 Spike）

> ⚠️ 本任務會對 **live 薪榮內部應用**寫入（建立 refs、上傳 actions）。執行前向使用者確認。不需 ALPR 金鑰（辨識走 mock）。對應工單第 0 節「aigo 寫回 smoke test」「對外連線 smoke test」。

**Files:**
- Create: `aigo-app/tests/smoke_weigh.py`（手動執行的整合腳本，非 pytest）

- [ ] **Step 1: 本機準備 `.env`（值不入 repo）**

```bash
cp .env.example .env
# 編輯 .env 填入 AIGO_PASSWORD（從密碼管理工具取得）
```

- [ ] **Step 2: 執行部署**

Run: `cd /home/username/桌面/fde-czone && set -a && source .env && set +a && python3 aigo-app/scripts/deploy.py`
Expected: 各 ref 回 200/201、`編譯：成功`、`✅ 部署完成`

- [ ] **Step 3: 寫 smoke test 腳本（呼叫 weigh action 跑一磅→二磅）**

```python
# aigo-app/tests/smoke_weigh.py
"""手動整合測試：登入後連呼叫 weigh 兩次（同車牌），驗證一磅→二磅→淨重。
用法：set -a && source .env && set +a && python3 aigo-app/tests/smoke_weigh.py"""
import json, os, urllib.request, urllib.error

API = "https://ai-go.app/api/v1"


def req(method, path, headers, data=None):
    body = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(f"{API}{path}", data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


def main():
    app_id = os.environ["AIGO_APP_ID"]
    s, b = req("POST", "/auth/login", {"Content-Type": "application/json"},
               {"email": os.environ["AIGO_EMAIL"], "password": os.environ["AIGO_PASSWORD"]})
    h = {"Authorization": f"Bearer {b['access_token']}", "Content-Type": "application/json"}
    run = f"/actions/apps/{app_id}/run/weigh"

    print("一磅：", req("POST", run, h,
          {"plate": "SMOKE-001", "weight": 25.0, "weigh_operator": "smoke", "now": "2026-06-05T09:00:00"})[1])
    print("二磅：", req("POST", run, h,
          {"plate": "SMOKE-001", "weight": 10.0, "weigh_operator": "smoke", "now": "2026-06-05T09:30:00"})[1])


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: 執行 smoke test**

Run: `cd /home/username/桌面/fde-czone && set -a && source .env && set +a && python3 aigo-app/tests/smoke_weigh.py`
Expected: 一磅回 `event=first`、二磅回 `event=second` 且 `net_weight=15.0`

> 若一磅/二磅未正確配對，先確認 czone 是否已建立 `x_czone_weighing`、`x_czone_vehicle` 自建表（規格第 3.2 節「待驗證」）；未建則先於平台建表再重跑。

- [ ] **Step 5: Commit**

```bash
git add aigo-app/tests/smoke_weigh.py
git commit -m "test: 加入過磅一磅→二磅整合 smoke test，驗證寫回與配對在平台跑通"
```

---

## 完成定義

- `cd aigo-app && python3 -m pytest -v` 全綠（單號、淨重、配對、payload、execute、辨識、OCR）。
- `weigh.py`、`recognize_plate.py`、`read_weight.py` 可在 secrets 無金鑰下回 mock 跑通。
- 部署腳本可登入→設授權→上傳→編譯→發布。
- （需平台）smoke test 驗證一磅→二磅→淨重 寫回正確。

## 不在本計畫（後續）
管理/查詢 UI、結帳 `settle`、電子發票、廢棄物申報、庫存、標案；真實 ALPR/OCR 呼叫的最終校正（待金鑰與清晰畫面 → Spike）。
