import stress_report

LINES = """STRESS vm cow PASS iters=20 procs=1 secs=3.5 ops=812/s maxlat=41ms seed=7
STRESS mmap sync UNSUP reason="msync: ENOSYS"
STRESS fs append FAIL what=nul off=0x3e000 want=a5c3 got=0000 seed=7
noise line
"""


def test_parse():
    rows = stress_report.parse(LINES)
    assert [r["result"] for r in rows] == ["PASS", "UNSUP", "FAIL"]
    assert rows[0]["ops"] == 812 and rows[0]["maxlat"] == 41
    assert rows[0]["secs"] == 3.5 and rows[0]["seed"] == 7
    assert rows[1]["reason"] == "msync: ENOSYS"
    assert rows[2]["off"] == "0x3e000" and rows[2]["got"] == "0000"


def test_summarize():
    s = stress_report.summarize(stress_report.parse(LINES))
    assert s["counts"]["vm"]["PASS"] == 1 and s["counts"]["fs"]["FAIL"] == 1
    assert s["fails"] == ["STRESS fs append FAIL what=nul off=0x3e000 want=a5c3 got=0000 seed=7"]
    assert s["rates"]["vm.cow"] == {"ops": 812, "maxlat": 41}


def test_summarize_repeats_take_max():
    text = ("STRESS vm cow PASS iters=1 procs=1 secs=1.0 ops=100/s maxlat=50ms seed=1\n"
            "STRESS vm cow PASS iters=1 procs=4 secs=1.0 ops=300.5/s maxlat=20ms seed=1\n")
    s = stress_report.summarize(stress_report.parse(text))
    assert s["rates"]["vm.cow"] == {"ops": 300.5, "maxlat": 50}


def test_compare():
    a = {"rates": {"vm.cow": {"ops": 800, "maxlat": 40}, "x.y": {"ops": 1, "maxlat": 1}}}
    b = {"rates": {"vm.cow": {"ops": 400, "maxlat": 90}}}
    assert stress_report.compare(a, b) == [("vm.cow", 800, 400, -50.0, 40, 90)]
