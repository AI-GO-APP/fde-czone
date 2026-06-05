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
