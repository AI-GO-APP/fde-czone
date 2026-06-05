from weigh import compute_net_weight

def test_net_weight_is_gross_minus_tare():
    assert compute_net_weight(25.0, 10.0) == 15.0

def test_net_weight_rounds_to_three_decimals():
    assert compute_net_weight(25.1239, 10.0) == 15.124

def test_net_weight_accepts_numeric_strings():
    assert compute_net_weight("25", "10") == 15.0
