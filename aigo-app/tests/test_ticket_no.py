from weigh import make_ticket_no

def test_ticket_no_pads_sequence_to_three_digits():
    assert make_ticket_no("20260602", 1) == "20260602-001"

def test_ticket_no_keeps_three_digits_for_large_seq():
    assert make_ticket_no("20260602", 42) == "20260602-042"
