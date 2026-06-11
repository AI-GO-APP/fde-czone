"""磅數 OCR：secrets 有 gemini_key 時用 Gemini 視覺模型讀地磅顯示器數字，否則回 mock(weight=None)。

地磅顯示器是紅色點矩陣 LED——免費/通用 OCR（OCR.space、ssocr）實測讀不出，
視覺模型 gemini-flash-lite-latest 實測可穩定讀出（手機近拍 6/6 一致），故選此路。
真正接系統的是 CCTV 畫面，清晰度越高越準（見 memory weighbridge-weight-capture）。"""

import re

GEMINI_MODEL = "gemini-flash-lite-latest"
GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"
PROMPT = "圖中地磅紅色點矩陣顯示器顯示的數字是多少?只回數字,不要小數點以外的任何文字。"


def parse_weight(text):
    """把 Gemini 回的文字轉成重量數字；無數字則 None。逗號視為千分位移除、保留小數點。"""
    if not text:
        return None
    cleaned = text.replace(",", "")
    m = re.search(r"-?\d+(?:\.\d+)?", cleaned)
    return float(m.group()) if m else None


def execute(ctx):
    image = ctx.params.get("image")
    if not image:
        ctx.response.json({"error": "缺少 image"})
        return

    key = ctx.secrets.get("gemini_key")
    if not key:
        # 未設金鑰：不假裝讀到數字，回 None 讓上游改用人工讀數
        ctx.response.json({"weight": None, "confidence": 0.0, "mock": True})
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
        ctx.response.json({"weight": None, "confidence": 0.0, "mock": False})
        return
    ctx.response.json({"weight": parse_weight(text), "confidence": 0.0, "mock": False})
