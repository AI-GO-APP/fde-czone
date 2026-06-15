import recognize_plate
from conftest import FakeCtx

def test_returns_mock_when_no_gemini_key():
    ctx = FakeCtx({"image": "<base64>"}, secrets={})
    recognize_plate.execute(ctx)
    assert ctx.response.body["mock"] is True
    assert "plate" in ctx.response.body

def test_errors_when_no_image():
    ctx = FakeCtx({}, secrets={})
    recognize_plate.execute(ctx)
    assert ctx.response.body["error"]


# parse_plate：把 Gemini 回的文字正規化成車牌（大寫、去空白/連字號、需含字母+數字）
def test_parse_keeps_letters_and_digits_strip_hyphen():
    assert recognize_plate.parse_plate("KEP-2758") == "KEP2758"

def test_parse_uppercases_and_trims():
    assert recognize_plate.parse_plate("  lag-988 ") == "LAG988"

def test_parse_extracts_plate_from_sentence():
    assert recognize_plate.parse_plate("車牌號碼為 KEP-2758") == "KEP2758"

def test_parse_returns_none_on_none_keyword():
    assert recognize_plate.parse_plate("NONE") is None

def test_parse_returns_none_on_empty():
    assert recognize_plate.parse_plate("") is None
