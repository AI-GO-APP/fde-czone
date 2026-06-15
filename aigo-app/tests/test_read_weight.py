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
    assert ctx.response.body["error"]


# parse_weight：把 Gemini 回的文字轉成重量數字（純函式，可單元測）
def test_parse_plain_integer():
    assert read_weight.parse_weight("14540") == 14540.0

def test_parse_strips_thousands_comma_and_unit():
    assert read_weight.parse_weight("14,540 kg") == 14540.0

def test_parse_keeps_decimal_point():
    assert read_weight.parse_weight("145.40") == 145.4

def test_parse_ignores_surrounding_text_and_whitespace():
    assert read_weight.parse_weight(" 顯示器數字是 14540 ") == 14540.0

def test_parse_returns_none_when_no_digits():
    assert read_weight.parse_weight("無法辨識") is None

def test_parse_returns_none_on_empty():
    assert read_weight.parse_weight("") is None
