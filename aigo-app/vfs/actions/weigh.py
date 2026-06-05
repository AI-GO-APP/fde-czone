"""過磅配對 Action：辨識結果→查車籍→判斷一磅/二磅→配對算淨重→寫表→回列印 payload。"""
from datetime import datetime

WEIGHING_TABLE = "x_czone_weighing"
VEHICLE_TABLE = "x_czone_vehicle"
STATUS_OPEN = "open"
STATUS_DONE = "done"


def make_ticket_no(date_str, seq):
    """date_str='YYYYMMDD'，seq 從 1 起。回 'YYYYMMDD-001'。"""
    return f"{date_str}-{seq:03d}"
