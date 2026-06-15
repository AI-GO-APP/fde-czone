"""車牌辨識：secrets 有 gemini_key 時用 Gemini 視覺模型讀車牌，否則回 mock。

原用 Plate Recognizer；改 Gemini flash-lite 以「車牌+磅數共用一支 API」省成本/簡化架構。
實測（2 樣本）flash-lite 兩張全對（KEP2758、LAG988），Plate Recognizer 把 K 誤讀為 M。
⚠️ 樣本仍少、視覺模型有「幻覺出合理但錯車牌」風險、無信心分數——待早中晚樣本大量比測再定生死
（見 memory weighbridge-weight-capture / 車牌比測）。"""

import re

GEMINI_MODEL = "gemini-flash-lite-latest"
GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"
PROMPT = "讀出這張圖中車輛的台灣車牌號碼。只回車牌(字母與數字,可含連字號),沒看到就回 NONE,不要其他文字。"


def parse_plate(text):
    """把 Gemini 回的文字正規化成車牌：大寫、去空白與連字號、需同時含字母與數字；無則 None。"""
    if not text:
        return None
    up = text.upper()
    best = None
    for token in re.findall(r"[A-Z0-9]+(?:-[A-Z0-9]+)*", up):
        s = token.replace("-", "")
        if (any(c.isalpha() for c in s) and any(c.isdigit() for c in s)
                and 4 <= len(s) <= 8 and (best is None or len(s) > len(best))):
            best = s
    return best


def execute(ctx):
    image = ctx.params.get("image")
    if not image:
        ctx.response.json({"error": "缺少 image"})
        return

    key = ctx.secrets.get("gemini_key")
    if not key:
        ctx.response.json({"plate": "MOCK-0000", "confidence": 0.0, "mock": True})
        return

    import httpx
    resp = httpx.post(
        GEMINI_URL.format(model=GEMINI_MODEL, key=key),
        json={"contents": [{"parts": [
            {"text": PROMPT},
            {"inline_data": {"mime_type": "image/jpeg", "data": image}},
        ]}]},
        timeout=30,
    )
    data = resp.json()
    try:
        text = data["candidates"][0]["content"]["parts"][0]["text"]
    except (KeyError, IndexError):
        ctx.response.json({"plate": None, "confidence": None, "mock": False})
        return
    # Gemini 不回信心分數，confidence 留 None（誠實標示無分數）
    ctx.response.json({"plate": parse_plate(text), "confidence": None, "mock": False})
