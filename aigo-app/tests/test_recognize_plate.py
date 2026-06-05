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
