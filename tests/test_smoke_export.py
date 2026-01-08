import os
from pathlib import Path
from backend.app.export_api import ExportRequest, export_project

def test_export_smoke(tmp_path, monkeypatch):
    # Use a temporary EXPORT_DIR so test is isolated
    monkeypatch.setenv("EXPORT_DIR", str(tmp_path))
    monkeypatch.setenv("ALLOW_RETURN_AUDIT_EVENTS", "true")
    # small HTML that should produce an index.html and audit.jsonl
    html = "<html><body><div style=\"display:block; color: red;\">hello</div></body></html>"
    req = ExportRequest(name="smoke-test", html=html, assets={}, export_type="static")
    resp = export_project(req, persist_audit=True, return_audit_events=True)
    assert resp.get("status") == "ok"
    export_dir = Path(resp.get("export_dir"))
    assert export_dir.exists() and export_dir.is_dir()
    assert (export_dir / "index.html").is_file()
    # audit.jsonl may be present when persist_audit=True and there were audit events
    assert (export_dir / "audit.jsonl").exists()
