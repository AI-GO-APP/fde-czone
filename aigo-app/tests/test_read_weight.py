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
