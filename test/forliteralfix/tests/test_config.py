def test_mode(monkeypatch):
    monkeypatch.setenv("APPTOOL_RENDER_MODE", "none")

def test_only(monkeypatch):
    monkeypatch.setenv("APPTOOL_TEST_ONLY", "1")
