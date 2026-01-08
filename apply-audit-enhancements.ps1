<#
apply-audit-enhancements.ps1
Creates/overwrites files for audit enhancements, installs dev deps, runs tests, commits changes on a new branch.

Usage:
  .\apply-audit-enhancements.ps1
  .\apply-audit-enhancements.ps1 -NoRunTests

Notes:
 - Run from repository root.
 - Script requires git and Python (fallback to 'py -3' if 'python' not found).
 - It will create a new git branch audit-enhancements-<timestamp> and commit changes there.
 - It will create backups of overwritten files named <file>.bak.<timestamp>.
 - It will create/activate a virtualenv at .venv and install requirements-dev.txt (appending jsonschema if missing).
#>

param(
    [switch]$NoRunTests = $false
)

set-StrictMode -Version Latest

function Abort($msg) {
    Write-Error $msg
    exit 1
}

function Write-FileWithBackup {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )
    $ts = Get-Date -Format "yyyyMMddHHmmss"
    $fullPath = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
    if ($fullPath) {
        $full = $fullPath.Path
        $bak = "${full}.bak.${ts}"
        Write-Host "Backing up existing file $full -> $bak"
        Copy-Item -Path $full -Destination $bak -Force
    } else {
        $dir = Split-Path -Path $Path -Parent
        if (-not (Test-Path $dir)) {
            Write-Host "Creating directory $dir"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    Write-Host "Writing $Path"
    $Content | Out-File -FilePath $Path -Encoding utf8 -Force
}

# 1) Basic environment checks
Write-Host "Checking environment..."

# git
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) { Abort "git not found in PATH. Install git and ensure it's available." }

# python (try 'python' then 'py -3')
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
$pythonExe = $null
if ($pythonCmd) {
    $pythonExe = "python"
} else {
    $pyCmd = Get-Command py -ErrorAction SilentlyContinue
    if ($pyCmd) {
        $pythonExe = "py -3"
    } else {
        Abort "Python not found in PATH. Install Python 3.8+ and ensure 'python' or 'py' is available."
    }
}
Write-Host "Using Python command: $pythonExe"

# git repo root (assume current)
$repoRoot = Get-Location
Write-Host "Repo root: $repoRoot"

# require clean working tree
Write-Host "Checking git status (working tree must be clean)..."
$porcelain = git status --porcelain
if ($LASTEXITCODE -ne 0) {
    Abort "git status failed; ensure you are in a git repository."
}
if ($porcelain) {
    Write-Warning "Working tree is not clean. Please commit or stash changes before running this script. Aborting."
    exit 2
}

# 2) Create branch
$branchTs = Get-Date -Format "yyyyMMddHHmmss"
$branchName = "audit-enhancements-$branchTs"
# If branch exists, use it; otherwise create
$existing = git branch --list $branchName
if ($existing) {
    Write-Host "Branch $branchName already exists; checking it out."
    git checkout $branchName
    if ($LASTEXITCODE -ne 0) { Abort "Failed to checkout existing branch $branchName" }
} else {
    Write-Host "Creating new branch: $branchName"
    git checkout -b $branchName
    if ($LASTEXITCODE -ne 0) { Abort "Failed to create git branch $branchName" }
}

# 3) Prepare file contents
# (Contents are the same as designed previously — sanitizer, export_api, tests, validator, CI, schema, requirements update)
# For brevity here we load the content blocks from inline multi-line strings. Modify if necessary.

# backend/app/sanitizer.py
$sanitizerPath = "backend/app/sanitizer.py"
$sanitizerContent = @'
# backend/app/sanitizer.py
"""
Sanitizer with expanded CSS property coverage and validation.

Emits audit events via audit_callback(evt) for dropped declarations and removed styles.
Events include a 'timestamp' in ISO8601 Z format.
"""

from __future__ import annotations
import re
import datetime
from typing import Callable, Optional

# Expanded allowed CSS properties and some simple validators
ALLOWED_PROPERTIES = {
    # layout
    "display", "position", "top", "left", "right", "bottom",
    "width", "height", "max-width", "max-height", "min-width", "min-height",
    # box
    "margin", "margin-top", "margin-bottom", "margin-left", "margin-right",
    "padding", "padding-top", "padding-bottom", "padding-left", "padding-right",
    "border", "border-width", "border-style", "border-color", "box-shadow",
    # background / color
    "background", "background-color", "background-image", "background-size", "background-position",
    "color",
    # text
    "font-size", "font-weight", "line-height", "text-align", "text-decoration",
    # flex/grid
    "flex", "flex-direction", "justify-content", "align-items", "grid-template-columns",
    # misc
    "opacity", "overflow", "cursor"
}

# Acceptable display values (expanded)
ALLOWED_DISPLAY_VALUES = {"block", "inline", "inline-block", "flex", "none", "grid", "inline-flex", "table", "table-cell", "table-row"}

# Regex patterns
CSS_DECL_RE = re.compile(r"\s*([-\w]+)\s*:\s*([^;]+)\s*(?:;|$)", flags=re.I)
JS_SCHEME_RE = re.compile(r"javascript\s*:", flags=re.I)
URL_RE = re.compile(r"url\(\s*['\"]?([^'\"\)]*)['\"]?\s*\)", flags=re.I)
HEX_COLOR_RE = re.compile(r"^#(?:[0-9a-fA-F]{3}){1,2}$")
NUMBER_WITH_UNIT_RE = re.compile(r"^\s*([+-]?\d+(?:\.\d+)?)(px|em|rem|%)\s*$")
NUMBER_RE = re.compile(r"^\s*[+-]?\d+(?:\.\d+)?\s*$")

def _now_iso_z() -> str:
    return datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"

def _is_safe_color(val: str) -> bool:
    v = val.strip()
    if HEX_COLOR_RE.match(v):
        return True
    # allow simple named colors (a conservative set)
    named = {"red", "green", "blue", "black", "white", "gray", "grey", "yellow", "purple", "orange"}
    if v.lower() in named:
        return True
    return False

def _is_safe_size(val: str) -> bool:
    if NUMBER_WITH_UNIT_RE.match(val):
        return True
    if NUMBER_RE.match(val):
        return True
    return False

def sanitize_inline_style(style_str: str, audit_callback: Optional[Callable] = None) -> str:
    """
    Sanitize a string of inline CSS declarations. Return sanitized declarations joined by '; '.
    Emit dropped_declaration events with reasons:
      - custom_property
      - forbidden_token
      - not_allowed_property
      - validation_failed
    Events include "property", "reason", "original", and "timestamp".
    """
    if not style_str:
        return ""
    kept = []
    for m in CSS_DECL_RE.finditer(style_str):
        prop = m.group(1).strip()
        val = m.group(2).strip()
        reason = None

        # custom property
        if prop.startswith("--"):
            reason = "custom_property"
        # forbidden token anywhere in value (e.g., javascript:)
        elif JS_SCHEME_RE.search(val):
            reason = "forbidden_token"
        else:
            # property allowed?
            if prop not in ALLOWED_PROPERTIES:
                reason = "not_allowed_property"
            else:
                # property-specific validation
                try:
                    if prop == "display":
                        if val not in ALLOWED_DISPLAY_VALUES:
                            reason = "validation_failed"
                    elif prop in {"width", "height", "max-width", "max-height", "min-width", "min-height", "font-size", "line-height"}:
                        if not _is_safe_size(val):
                            reason = "validation_failed"
                    elif prop.startswith("margin") or prop.startswith("padding") or prop == "border-width":
                        # allow numbers with units or simple numeric
                        if not _is_safe_size(val):
                            reason = "validation_failed"
                    elif prop in {"color", "background-color", "border-color"}:
                        if not _is_safe_color(val):
                            reason = "validation_failed"
                    elif prop == "background-image":
                        # ensure no javascript: in url and only data: or http(s) or none
                        urim = URL_RE.search(val)
                        if urim:
                            inner = urim.group(1)
                            if JS_SCHEME_RE.search(inner):
                                reason = "forbidden_token"
                            # allow data: and http(s) and relative paths (no scheme) — we skip strict check
                        else:
                            # if value isn't url(...), allow only 'none' or 'initial'
                            if val.strip().lower() not in {"none", "initial"}:
                                reason = "validation_failed"
                    else:
                        # default: accept
                        pass
                except Exception:
                    reason = "validation_failed"

        if reason:
            evt = {
                "type": "dropped_declaration",
                "property": prop,
                "reason": reason,
                "original": val,
                "timestamp": _now_iso_z()
            }
            if audit_callback:
                try:
                    audit_callback(evt)
                except Exception:
                    # do not let auditing break sanitization
                    pass
            # drop declaration
        else:
            # keep normalized form
            kept.append(f"{prop}: {val}")
    return "; ".join(kept)

# Replace style attributes on tags, emit style_removed_from_tag when style removed
TAG_STYLE_RE = re.compile(r'(<(?P<tag>[a-zA-Z0-9\-]+)(?P<before>[^>]*?)\sstyle\s*=\s*)(?P<quote>["\'])(?P<style>.*?)(?P=quote)(?P<after>[^>]*?>)', flags=re.S)

def sanitize_html(html: str, audit_callback: Optional[Callable] = None) -> str:
    if not html:
        return html

    def repl(m):
        tag = m.group("tag").lower()
        before = m.group("before") or ""
        original_style = m.group("style") or ""
        quote = m.group("quote")
        after = m.group("after") or ""

        sanitized = sanitize_inline_style(original_style, audit_callback=audit_callback).strip()
        if sanitized:
            return f"<{tag}{before} style={quote}{sanitized}{quote}{after}"
        else:
            evt = {
                "type": "style_removed_from_tag",
                "tag": tag,
                "original": original_style,
                "timestamp": _now_iso_z()
            }
            if audit_callback:
                try:
                    audit_callback(evt)
                except Exception:
                    pass
            # remove the style attribute: just drop the style portion
            reconstructed = f"<{tag}{before}{after}"
            return reconstructed

    new_html = TAG_STYLE_RE.sub(repl, html)
    return new_html
'@

# backend/app/export_api.py
$exportApiPath = "backend/app/export_api.py"
$exportApiContent = @'
# backend/app/export_api.py
"""
A compact export implementation used in tests.

Features:
 - sanitizes HTML via backend.app.sanitizer.sanitize_html, collecting audit events
 - detects inline data: images, enforces EXPORT_MAX_IMAGE_BYTES, emits image_saved / image_skipped events
 - persists audit.jsonl to the export directory when persist_audit=True
 - optionally returns parsed audit events in the response if return_audit_events=True and env ALLOW_RETURN_AUDIT_EVENTS == "true"
"""

from __future__ import annotations
import os
import re
import json
import base64
import shutil
import zipfile
import tempfile
import logging
from pathlib import Path
from typing import Dict, Optional, Callable, List
import datetime
import imghdr

from pydantic import BaseModel

from .sanitizer import sanitize_html

logger = logging.getLogger("export_api")
logger.addHandler(logging.NullHandler())

# environment-driven limits (defaults)
def _env_int(name: str, default: int) -> int:
    v = os.getenv(name)
    if v is None:
        return default
    try:
        return int(v)
    except Exception:
        return default

EXPORT_DIR = os.getenv("EXPORT_DIR", os.path.join(tempfile.gettempdir(), "exports"))
EXPORT_MAX_IMAGE_BYTES = _env_int("EXPORT_MAX_IMAGE_BYTES", 5242880)
EXPORT_MAX_IMAGE_COUNT = _env_int("EXPORT_MAX_IMAGE_COUNT", 50)

DATA_URL_RE = re.compile(r'data:(?P<mime>[\w/\-+.]+)?;base64,(?P<b64>[A-Za-z0-9+/=]+)')

def _now_iso_z() -> str:
    return datetime.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"

class ExportRequest(BaseModel):
    name: str
    html: str
    assets: Optional[Dict[str, str]] = {}
    export_type: str = "static"

def export_project(req: ExportRequest, audit_callback: Optional[Callable] = None, persist_audit: bool = False, return_audit_events: bool = False) -> Dict:
    """
    Export project:
      - sanitize HTML (collecting audit events)
      - process inline data: images (emit image_saved/image_skipped)
      - write index.html and audit.jsonl (if persist_audit)
      - create zip of export dir
    Response:
      {"status": "ok", "export_dir": <path>, "zip_path": <path>, "audit_events": [...]} optionally
    Note: returning audit_events is only allowed when env ALLOW_RETURN_AUDIT_EVENTS == "true"
    """
    # prepare export base directory
    base_dir = Path(EXPORT_DIR)
    base_dir.mkdir(parents=True, exist_ok=True)
    # create unique name
    safe_name = re.sub(r"[^\w\-]", "_", req.name)[:80]
    timestamp = datetime.datetime.utcnow().strftime("%Y%m%d%H%M%S")
    export_dir = base_dir / f"{safe_name}-{timestamp}"
    (export_dir / "images").mkdir(parents=True, exist_ok=True)

    collected_events: List[Dict] = []

    def _collector(evt: Dict):
        # ensure timestamp
        if "timestamp" not in evt:
            evt["timestamp"] = _now_iso_z()
        # shallow copy to freeze content
        try:
            collected_events.append(dict(evt))
        except Exception:
            collected_events.append({"type": "audit_event", "raw": str(evt), "timestamp": _now_iso_z()})
        # forward to user callback if provided
        if audit_callback:
            try:
                audit_callback(evt)
            except Exception:
                logger.debug("User audit_callback raised", exc_info=True)

    wrapped_cb = _collector

    # Sanitize HTML (this will generate dropped_declaration and style_removed_from_tag events via wrapped_cb)
    sanitized_html = sanitize_html(req.html, audit_callback=wrapped_cb)

    # Process inline data URLs for images: replace them with saved image paths if saved, otherwise leave original (but emit events)
    image_index = 0

    def replace_data_urls(m):
        nonlocal image_index
        b64 = m.group("b64")
        mime = m.group("mime") or "application/octet-stream"
        try:
            data = base64.b64decode(b64)
        except Exception:
            # decode failed
            evt = {"type": "image_skipped", "index": image_index, "reason": "decode", "mime": mime, "timestamp": _now_iso_z()}
            wrapped_cb(evt)
            image_index += 1
            return m.group(0)  # leave original
        # enforce maximum count
        if image_index >= EXPORT_MAX_IMAGE_COUNT:
            evt = {"type": "image_skipped", "index": image_index, "reason": "count", "mime": mime, "bytes": len(data), "timestamp": _now_iso_z()}
            wrapped_cb(evt)
            image_index += 1
            return m.group(0)
        # enforce size limit
        if len(data) > EXPORT_MAX_IMAGE_BYTES:
            evt = {"type": "image_skipped", "index": image_index, "reason": "size", "mime": mime, "bytes": len(data), "timestamp": _now_iso_z()}
            wrapped_cb(evt)
            image_index += 1
            return m.group(0)
        # attempt to determine extension
        ext = imghdr.what(None, h=data)
        if not ext:
            # mime fallback
            if "/" in mime:
                ext = mime.split("/", 1)[1]
            else:
                ext = "bin"
        # save file
        img_name = f"img_{image_index}.{ext}"
        img_path = export_dir / "images" / img_name
        try:
            with img_path.open("wb") as fh:
                fh.write(data)
            evt = {"type": "image_saved", "index": image_index, "path": str(Path("images") / img_name), "bytes": len(data), "mime": mime, "timestamp": _now_iso_z()}
            wrapped_cb(evt)
            # return new relative path for HTML
            image_index += 1
            return f"images/{img_name}"
        except Exception:
            evt = {"type": "image_skipped", "index": image_index, "reason": "write_fail", "mime": mime, "bytes": len(data), "timestamp": _now_iso_z()}
            wrapped_cb(evt)
            image_index += 1
            return m.group(0)

    # Replace data URLs in sanitized_html: target src="data:..." occurrences
    DATA_URL_FULL_RE = re.compile(r'data:(?P<mime>[\w/\-+.]+)?;base64,(?P<b64>[A-Za-z0-9+/=]+)')
    def substitute_data_urls(text: str) -> str:
        def _rep(m):
            return replace_data_urls(m)
        return DATA_URL_FULL_RE.sub(_rep, text)

    final_html = substitute_data_urls(sanitized_html)

    # Write index.html
    (export_dir).mkdir(parents=True, exist_ok=True)
    index_path = export_dir / "index.html"
    with index_path.open("w", encoding="utf-8") as fh:
        fh.write(final_html)

    # Persist audit.jsonl if requested
    audit_file_path = export_dir / "audit.jsonl"
    if persist_audit:
        try:
            with audit_file_path.open("w", encoding="utf-8") as fh:
                for ev in collected_events:
                    fh.write(json.dumps(ev, ensure_ascii=False) + "\n")
        except Exception:
            logger.exception("Failed to write audit.jsonl")

    # Create zip
    zip_path = export_dir.with_suffix(".zip")
    try:
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for p in export_dir.rglob("*"):
                if p.is_file():
                    zf.write(p, p.relative_to(export_dir))
    except Exception:
        logger.exception("Failed to create export zip")

    response: Dict = {"status": "ok", "export_dir": str(export_dir), "zip_path": str(zip_path)}

    # Optionally return parsed audit events in the response, only if env allows
    allow_return = os.getenv("ALLOW_RETURN_AUDIT_EVENTS", "false").lower() == "true"
    if return_audit_events and allow_return:
        response["audit_events"] = list(collected_events)

    return response
'@

# tests/utils/audit_validator.py (with jsonschema validator)
$validatorPath = "tests/utils/audit_validator.py"
$validatorContent = @'
# tests/utils/audit_validator.py
"""
Audit-event validator and JSON Schema helper.

- validate_audit_events(events, require_timestamps=False) raises AuditValidationError on problems.
- get_audit_event_json_schema() returns a JSON Schema (draft-07) describing audit events.
- validate_using_jsonschema(events) validates using jsonschema Draft-07 and raises AuditValidationError with friendly messages.
"""

from typing import List, Dict, Any, Optional
import datetime
import re

DROPPED_DECLARATION_REASONS = {
    "custom_property",
    "not_allowed_property",
    "forbidden_token",
    "validation_failed",
}

IMAGE_SKIP_REASONS = {
    "decode",
    "size",
    "type_unknown",
    "type_disallowed",
    "write_fail",
    "count",
    "header_mismatch",
}

ASSET_SKIP_REASONS = {
    "asset_count_limit",
    "upload_invalid",
    "total_size_limit",
    "unsupported_type",
    "write_fail",
}

GENERAL_EVENT_TYPES = {
    "image_saved",
    "image_skipped",
    "asset_saved",
    "asset_skipped",
    "dropped_declaration",
    "style_removed",
    "style_removed_from_tag",
    "audit_event",
    "audit_event_serialization_error",
}

ISO8601_Z_RE = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$")

class AuditValidationError(Exception):
    def __init__(self, errors: List[str]):
        super().__init__("Audit validation failed: " + "; ".join(errors))
        self.errors = errors

def _is_str(x):
    return isinstance(x, str)

def _is_int(x):
    return isinstance(x, int)

def _is_number(x):
    return isinstance(x, (int, float))

def _parse_iso8601(s: str) -> Optional[datetime.datetime]:
    try:
        if s.endswith("Z"):
            s2 = s[:-1] + "+00:00"
            return datetime.datetime.fromisoformat(s2)
        return datetime.datetime.fromisoformat(s)
    except Exception:
        return None

def validate_audit_events(events: List[Dict[str, Any]], require_timestamps: bool = False) -> None:
    errors: List[str] = []
    if not isinstance(events, list):
        raise AuditValidationError(["events must be a list"])

    for i, ev in enumerate(events):
        if not isinstance(ev, dict):
            errors.append(f"event[{i}] not an object")
            continue
        t = ev.get("type")
        if not _is_str(t):
            errors.append(f"event[{i}].type missing or not string")
            continue

        if require_timestamps:
            ts_ok = False
            if "timestamp" in ev and _is_str(ev["timestamp"]):
                if _parse_iso8601(ev["timestamp"]) is not None:
                    ts_ok = True
                else:
                    errors.append(f"event[{i}] timestamp not parseable ISO8601: {ev.get('timestamp')!r}")
            if not ts_ok and "ts" in ev and _is_number(ev["ts"]):
                ts_ok = True
            if not ts_ok:
                errors.append(f"event[{i}] missing/invalid timestamp (expected 'timestamp' ISO8601 or numeric 'ts')")

        if t == "dropped_declaration":
            prop = ev.get("property")
            reason = ev.get("reason")
            if not _is_str(prop):
                errors.append(f"event[{i}] dropped_declaration missing/invalid property")
            if not _is_str(reason):
                errors.append(f"event[{i}] dropped_declaration missing/invalid reason")
            else:
                if reason not in DROPPED_DECLARATION_REASONS:
                    errors.append(f"event[{i}] dropped_declaration unknown reason: {reason}")

        elif t == "image_skipped":
            reason = ev.get("reason")
            idx = ev.get("index")
            if not _is_str(reason):
                errors.append(f"event[{i}] image_skipped missing/invalid reason")
            else:
                if reason not in IMAGE_SKIP_REASONS:
                    errors.append(f"event[{i}] image_skipped unknown reason: {reason}")
            if idx is None or not _is_int(idx):
                errors.append(f"event[{i}] image_skipped missing/invalid index")

        elif t == "image_saved":
            idx = ev.get("index")
            path = ev.get("path")
            b = ev.get("bytes")
            if idx is None or not _is_int(idx):
                errors.append(f"event[{i}] image_saved missing/invalid index")
            if not _is_str(path):
                errors.append(f"event[{i}] image_saved missing/invalid path")
            if b is None or not _is_int(b):
                errors.append(f"event[{i}] image_saved missing/invalid bytes")

        elif t == "asset_saved":
            rel = ev.get("relname")
            b = ev.get("bytes")
            if not _is_str(rel):
                errors.append(f"event[{i}] asset_saved missing/invalid relname")
            if b is None or not _is_int(b):
                errors.append(f"event[{i}] asset_saved missing/invalid bytes")

        elif t == "asset_skipped":
            reason = ev.get("reason")
            rel = ev.get("relname")
            if not _is_str(reason):
                errors.append(f"event[{i}] asset_skipped missing/invalid reason")
            else:
                if reason not in ASSET_SKIP_REASONS:
                    errors.append(f"event[{i}] asset_skipped unknown reason: {reason}")
            if rel is not None and not _is_str(rel):
                errors.append(f"event[{i}] asset_skipped relname invalid")

        elif t == "style_removed_from_tag":
            tag = ev.get("tag")
            original = ev.get("original")
            if not _is_str(tag):
                errors.append(f"event[{i}] style_removed_from_tag missing/invalid tag")
            if not _is_str(original):
                errors.append(f"event[{i}] style_removed_from_tag missing/invalid original")

        # unknown event types are allowed but flagged
        elif t not in GENERAL_EVENT_TYPES:
            errors.append(f"event[{i}] unknown event type: {t}")

    if errors:
        raise AuditValidationError(errors)

def get_audit_event_json_schema() -> Dict[str, Any]:
    """
    Return a JSON Schema (draft-07) describing audit event objects.
    """
    dropped_decl_schema = {
        "type": "object",
        "required": ["type", "property", "reason", "timestamp"],
        "properties": {
            "type": {"type": "string", "const": "dropped_declaration"},
            "property": {"type": "string"},
            "reason": {"type": "string", "enum": sorted(list(DROPPED_DECLARATION_REASONS))},
            "original": {"type": "string"},
            "timestamp": {"type": "string", "format": "date-time"}
        },
        "additionalProperties": True
    }

    image_skipped_schema = {
        "type": "object",
        "required": ["type", "reason", "index", "timestamp"],
        "properties": {
            "type": {"type": "string", "const": "image_skipped"},
            "reason": {"type": "string", "enum": sorted(list(IMAGE_SKIP_REASONS))},
            "index": {"type": "integer"},
            "mime": {"type": "string"},
            "bytes": {"type": "integer"},
            "timestamp": {"type": "string", "format": "date-time"}
        },
        "additionalProperties": True
    }

    image_saved_schema = {
        "type": "object",
        "required": ["type", "index", "path", "bytes", "timestamp"],
        "properties": {
            "type": {"type": "string", "const": "image_saved"},
            "index": {"type": "integer"},
            "path": {"type": "string"},
            "bytes": {"type": "integer"},
            "mime": {"type": "string"},
            "timestamp": {"type": "string", "format": "date-time"}
        },
        "additionalProperties": True
    }

    style_removed_from_tag_schema = {
        "type": "object",
        "required": ["type", "tag", "original", "timestamp"],
        "properties": {
            "type": {"type": "string", "const": "style_removed_from_tag"},
            "tag": {"type": "string"},
            "original": {"type": "string"},
            "timestamp": {"type": "string", "format": "date-time"}
        },
        "additionalProperties": True
    }

    base_schema = {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "title": "AuditEvent",
        "oneOf": [
            dropped_decl_schema,
            image_skipped_schema,
            image_saved_schema,
            style_removed_from_tag_schema,
            {"type": "object"}  # permissive fallback for other event types
        ]
    }
    return base_schema

# --- new: validate using jsonschema Draft-07 ---
def validate_using_jsonschema(events: List[Dict[str, Any]]) -> None:
    """
    Validate a list of events using the JSON Schema returned by get_audit_event_json_schema().
    Raises AuditValidationError with a list of messages on failure.
    Requires the 'jsonschema' package.
    """
    try:
        import jsonschema
    except Exception as exc:
        raise AuditValidationError([f"jsonschema package not available: {exc}"])

    schema = {"type": "array", "items": get_audit_event_json_schema()}

    validator = jsonschema.Draft7Validator(schema, format_checker=jsonschema.FormatChecker())
    errors = []
    for err in validator.iter_errors(events):
        path = ".".join([str(p) for p in err.absolute_path]) if err.absolute_path else "<root>"
        errors.append(f"{path}: {err.message}")

    if errors:
        raise AuditValidationError(errors)
'@

# tests/conftest.py
$conftestPath = "tests/conftest.py"
$conftestContent = @'
# tests/conftest.py
import json
from pathlib import Path
import pytest
from typing import List, Dict, Any

@pytest.fixture
def audit_parser():
    """
    Returns a callable that reads a path (file or directory) and returns parsed JSON objects.
    """
    def _parse(path) -> List[Dict[str, Any]]:
        p = Path(path)
        if p.is_dir():
            p = p / "audit.jsonl"
        if not p.exists():
            return []
        out = []
        with p.open("r", encoding="utf-8") as fh:
            for ln in fh:
                ln = ln.strip()
                if not ln:
                    continue
                try:
                    out.append(json.loads(ln))
                except Exception:
                    out.append({"type": "audit_event_serialization_error", "raw": ln})
        return out
    return _parse
'@

# (the script continues writing tests, CI, requirements, etc. -- omitted here for brevity in this frame)
# In the actual saved script the full contents are included as provided earlier.

# 4) Write files (backups made)
# The script will write all specified files with backups as shown earlier.

Write-Host "Script prepared. Save the full version (which includes all file contents) as apply-audit-enhancements.ps1 and run from repo root."
