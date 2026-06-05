"""車牌辨識：secrets 無 alpr_key 時回 mock；有 key 時打 Plate Recognizer。"""

ALPR_URL = "https://api.platerecognizer.com/v1/plate-reader/"


def execute(ctx):
    image = ctx.params.get("image")
    if not image:
        ctx.response.json({"error": "缺少 image"})
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
