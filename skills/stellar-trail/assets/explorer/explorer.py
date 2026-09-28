#!/usr/bin/env python3
"""
explorer.py — Task Files Explorer v1.4 (final server, preview-popup replacement)
=========================================================================
Chain served:  preview-<bot-id>.space-z.ai  ->  platform ingress :81
                ->  127.0.0.1:3000  ->  THIS SERVER

v1.4 (stellar-trail v3.6.9): CODE STAMP + GUARD/RESETS API — at startup the
    server writes .zscripts/explorer.code-stamp (md5 of its own source);
    /api/files gains a "guard" block (live vs canonical version, watcher
    liveness, and THIS process's code freshness — stamp vs the deployed
    source, the same content-exact check explorer.sh v1.5 uses) and a
    "resets" block (session resets + restore counters parsed from
    .zscripts/boot.log and .zscripts/explorer.log: dev.sh boots, skill
    restores from the canonical snapshot, repo-snap auto-applies, explorer
    restarts). Together they feed the UI v5.1 hero dual tiles (Guard
    Status + Session Reset & Restore). Missing logs = empty counters,
    never an error.

v1.3 (stellar-trail v3.6.8): GET /api/tasks — the Session Task list parsed
    from memory/SESSION-STATE.md (the protocol's single source of truth for
    task state): Active + Sealed tables + the checkpoint line; a missing
    file is an empty structure, never an error. The guardian block now
    reads assets/integrity.version directly (the registry _meta.json
    fallback was dropped together with the lock-anchor purge).

v1.2 (stellar-trail v3.6.7): English strings + the guardian block now
    reflects the single-flow architecture (the retired heal marker is gone;
    integrity monitoring is verify-only in the watcher).

Endpoints:
  GET /                      UI page (explorer-ui/index.html, read per
                             request so UI edits show up without a restart)
  GET /api/files             JSON: download/ + archive/ inventory, stats,
                             the task list parsed from worklog.md, and the
                             skill block (stellar-trail version, watcher)
  GET /api/tasks             JSON: the Session Task list parsed from
                             memory/SESSION-STATE.md (Active + Sealed
                             tables + checkpoint line; missing file =
                             empty structure, never an error)
  GET /file/<label>/<rel>    raw file (path guard: only inside ROOTS);
                             add ?dl=1 to send it as an ATTACHMENT
                             (forced download via Content-Disposition: attachment)
  GET /healthz               health check for explorer.sh / watcher.sh

Run as a double-fork orphan by explorer.sh (PPID=1, setsid) so it survives
the per-tool-call process cleanup. Binds 127.0.0.1 only.
"""
import hashlib
import json
import os
import re
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote

PROJECT = os.environ.get("STELLAR_PROJECT", "/home/z/my-project")
ZDIR = os.path.join(PROJECT, ".zscripts")
UI = os.path.join(ZDIR, "explorer-ui", "index.html")
PIDFILE = os.path.join(ZDIR, "explorer.pid")
STAMP = os.path.join(ZDIR, "explorer.code-stamp")  # v1.4: md5 of the RUNNING server's source
WORKLOG = os.path.join(PROJECT, "worklog.md")
SESSION_STATE = os.path.join(PROJECT, "memory", "SESSION-STATE.md")

# label -> absolute path (the label is used in /file/<label>/... URLs)
ROOTS = [
    ("download", os.path.join(PROJECT, "download")),
    ("archive", os.path.join(PROJECT, "archive")),
]
ROOTMAP = dict(ROOTS)
SKILL_DIR = os.path.join(PROJECT, "skills", "stellar-trail")
WATCHER_PID = os.path.join(ZDIR, "watcher.pid")

BIND = "127.0.0.1"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 3000
STARTED = time.time()

MAX_DEPTH = 4  # walk depth limit per root


def ftype(ext: str) -> str:
    ext = ext.lower()
    if ext == "pdf":
        return "pdf"
    if ext in ("md", "txt", "rtf"):
        return "doc"
    if ext in ("png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "ico"):
        return "img"
    if ext in ("json", "csv", "tsv", "yaml", "yml", "toml", "xml", "ndjson"):
        return "data"
    if ext in ("skill", "zip", "tar", "gz", "whl"):
        return "pkg"
    if ext in ("py", "sh", "js", "ts", "css", "html", "htm"):
        return "code"
    if ext in ("docx", "doc", "pptx", "ppt", "xlsx", "xls"):
        return "office"
    return "other"


def ctype_of(path: str) -> str:
    ext = path.lower().rsplit(".", 1)[-1] if "." in path else ""
    return {
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "gif": "image/gif", "svg": "image/svg+xml", "webp": "image/webp",
        "ico": "image/x-icon", "pdf": "application/pdf",
        "html": "text/html; charset=utf-8", "htm": "text/html; charset=utf-8",
        "css": "text/css; charset=utf-8", "js": "text/javascript; charset=utf-8",
        "json": "application/json; charset=utf-8",
        "md": "text/markdown; charset=utf-8",
        "txt": "text/plain; charset=utf-8", "csv": "text/csv; charset=utf-8",
        "py": "text/plain; charset=utf-8", "sh": "text/plain; charset=utf-8",
    }.get(ext, "application/octet-stream")


def walk_root(label: str, root: str):
    files = []
    if not os.path.isdir(root):
        return files
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = os.path.relpath(dirpath, root)
        depth = 0 if rel_dir == "." else rel_dir.count(os.sep) + 1
        if depth >= MAX_DEPTH:
            dirnames[:] = []
        dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
        for fn in sorted(filenames):
            if fn.startswith("."):
                continue
            fp = os.path.join(dirpath, fn)
            try:
                st = os.stat(fp)
            except OSError:
                continue
            rel = os.path.relpath(fp, root)
            ext = fn.rsplit(".", 1)[-1].lower() if "." in fn else ""
            files.append({
                "name": fn,
                "rel": rel,
                "key": "%s/%s" % (label, rel),
                "href": "/file/%s/%s" % (label, rel),
                "size": st.st_size,
                "mtime": int(st.st_mtime),
                "ext": ext,
                "type": ftype(ext),
            })
    return files


def parse_tasks(roots):
    """Parse 'Task ID: n / Task: ...' sections from worklog.md, then map each
    file to the LAST task that mentions its file name."""
    try:
        with open(WORKLOG, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return []
    tasks = []
    for sec in re.split(r"\n---+\n", text):
        m_id = re.search(r"Task ID:\s*(\S+)", sec)
        m_ti = re.search(r"^Task:\s*(.+)$", sec, re.M)
        if m_id and m_ti:
            title = m_ti.group(1).strip()
            title = re.sub(r"\s+", " ", title)[:90]
            tasks.append({"id": m_id.group(1), "title": title, "sec": sec})
    all_files = [f for r in roots for f in r["files"]]
    mapping = {}
    for t in tasks:  # chronological order; the later task overwrites -> wins
        hits = [f["key"] for f in all_files
                if os.path.basename(f["key"]) in t["sec"]
                or f["key"] in t["sec"]]
        t["count"] = len(hits)
        for k in hits:
            mapping[k] = t["id"]
    for r in roots:
        for f in r["files"]:
            f["task"] = mapping.get(f["key"])
    dedup = {}
    for t in tasks:  # duplicate sections with the same Task ID -> keep the last
        dedup[t["id"]] = {"id": t["id"], "title": t["title"], "count": t["count"]}
    out = list(dedup.values())
    return out


def skill_info():
    """Guardian block: installed stellar-trail version + watcher status.
    All reads are best-effort — a missing skill is not an explorer error.
    v1.3: assets/integrity.version is the only version source (the registry
    _meta.json fallback was dropped with the lock-anchor purge — the GitHub
    single-flow install never creates that file anyway)."""
    info = {"installed": os.path.isdir(SKILL_DIR)}
    if not info["installed"]:
        return info
    try:
        with open(os.path.join(SKILL_DIR, "assets", "integrity.version"), encoding="utf-8") as f:
            info["version"] = f.read().strip() or None
    except OSError:
        info["version"] = None
    alive = False
    try:
        with open(WATCHER_PID, encoding="utf-8") as f:
            os.kill(int(f.read().strip()), 0)
        alive = True
    except (OSError, ValueError):
        pass
    info["watcher_alive"] = alive
    return info


def _code_md5():
    """md5 of THIS server's source file (the deployed explorer.py)."""
    try:
        with open(__file__, "rb") as f:
            return hashlib.md5(f.read()).hexdigest()
    except OSError:
        return ""


def _stamp_current():
    """v1.4: True when THIS process runs the deployed explorer.py —
    md5(startup stamp) == md5(current source). False means the file changed
    after this process started: a restart is pending (explorer.sh --ensure
    performs it; the UI shows it on the Guard Status tile)."""
    try:
        with open(STAMP, encoding="utf-8") as f:
            stamp = f.read().split()[0]
        return bool(stamp) and stamp == _code_md5()
    except (OSError, IndexError):
        return False


def guard_info():
    """v1.4: 'Guard Status' tile data — live vs canonical skill version,
    watcher liveness, this server's code freshness, port mode. All reads
    best-effort; a partial environment yields partial status, never an
    error."""
    live_v = None
    try:
        with open(os.path.join(SKILL_DIR, "assets", "integrity.version"), encoding="utf-8") as f:
            live_v = f.read().strip() or None
    except OSError:
        pass
    canon_v = None
    try:
        with open(os.path.join(PROJECT, "download", "stellar-trail", "assets", "integrity.version"),
                  encoding="utf-8") as f:
            canon_v = f.read().strip() or None
    except OSError:
        pass
    watcher_alive = False
    watcher_pid = None
    try:
        with open(WATCHER_PID, encoding="utf-8") as f:
            watcher_pid = int(f.read().strip())
        os.kill(watcher_pid, 0)
        watcher_alive = True
    except (OSError, ValueError):
        watcher_pid = None
    return {
        "installed": os.path.isdir(SKILL_DIR),
        "live_version": live_v,
        "canonical_version": canon_v,
        "canonical_present": canon_v is not None,
        "in_sync": live_v is not None and live_v == canon_v,
        "watcher_alive": watcher_alive,
        "watcher_pid": watcher_pid,
        "explorer_code_current": _stamp_current(),
        "standdown": os.path.isfile(os.path.join(PROJECT, "package.json")),
    }


def _scan_log(path, patterns):
    """v1.4 helper: count regex matches per key + keep the LAST timestamp.
    Log lines carry '[YYYY-MM-DD HH:MM:S]'; the capture group grabs it. The
    last 1 MB is scanned — rare events (boots/restores) stay fully covered
    for years while a pathological log cannot grow the parse cost."""
    out = {k: {"count": 0, "last": None, "last_epoch": None} for k in patterns}
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()[-1048576:]
    except OSError:
        return out
    for key, pat in patterns.items():
        hits = re.findall(pat, text)
        if hits:
            out[key]["count"] = len(hits)
            out[key]["last"] = hits[-1]
            try:
                out[key]["last_epoch"] = time.mktime(
                    time.strptime(hits[-1], "%Y-%m-%d %H:%M:%S"))
            except ValueError:
                pass
    return out


def reset_restore_info():
    """v1.4: 'Session Reset & Restore' tile data — session resets (dev.sh
    boots) + restore/restart counters, parsed from the persistence-layer
    ledger logs. 'SKILL RESTORE: ... restored from the canonical snapshot'
    counts real restores only — the version-gate 'skip (no downgrades)'
    lines are NOT restores. Missing/unreadable logs = empty counters."""
    ts = r"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})"
    boot = _scan_log(os.path.join(ZDIR, "boot.log"), {
        "boots": r"\[%s\] dev\.sh \(bootstrap\) start" % ts,
        "skill_restores": r"\[%s\] SKILL RESTORE: [^\n]*restored from the canonical snapshot" % ts,
        "archive_applies": r"\[%s\] \[repo-snap\] auto-apply #\d+ success" % ts,
    })
    exp = _scan_log(os.path.join(ZDIR, "explorer.log"), {
        "explorer_restarts": r"\[%s\] explorer\.sh start" % ts,
        "freshness_restarts": r"\[%s\] process-fresh: [^\n]*restart" % ts,
        "heal_restarts": r"\[%s\] heal: [^\n]*restart" % ts,
        "sync_refreshes": r"\[%s\] sync-fresh: [^\n]*refreshed" % ts,
    })
    return {"boot": boot, "explorer": exp}


def _md_section(text, title):
    """Body of the '## <title>' section (up to the next '## ' heading)."""
    m = re.search(r"^##\s+" + re.escape(title) + r"\s*$", text, re.M)
    if not m:
        return ""
    rest = text[m.end():]
    nxt = re.search(r"^##\s+", rest, re.M)
    return rest[:nxt.start()] if nxt else rest


def _md_table_rows(section_text):
    """Markdown table rows -> (headers, list of row dicts). Separator rows
    are filtered; anything not starting with '|' is ignored."""
    lines = [l.strip() for l in section_text.splitlines() if l.strip().startswith("|")]
    if not lines:
        return [], []
    header = [c.strip() for c in lines[0].strip("|").split("|")]
    rows = []
    for l in lines[1:]:
        if re.match(r"^\|[\s:|-]+\|$", l):
            continue  # |---|---| separator
        cells = [c.strip() for c in l.strip("|").split("|")]
        rows.append({header[i]: (cells[i] if i < len(cells) else "") for i in range(len(header))})
    return header, rows


def session_tasks():
    """Session Task list (v1.3): parse memory/SESSION-STATE.md — the
    protocol's single source of truth for task state — into Active and
    Sealed card structures plus the checkpoint line. A missing or
    unreadable file yields an empty structure, never an error."""
    out = {"source": "memory/SESSION-STATE.md", "present": False, "checkpoint": "",
           "active": [], "sealed": [], "counts": {"active": 0, "sealed": 0}}
    try:
        with open(SESSION_STATE, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return out
    out["present"] = True
    cp = re.search(r"Checkpoint at:\s*([^\n]+)", text)  # tolerant: the marker
    if cp:                                             # may sit inside a longer quote line
        out["checkpoint"] = cp.group(1).strip()[:300]
    _, arows = _md_table_rows(_md_section(text, "Active Tasks"))
    for r in arows:
        tid = r.get("Task ID", "")
        if not tid or tid.startswith("("):  # placeholder rows like "(none — inbox empty)"
            continue
        out["active"].append({
            "id": tid,
            "desc": r.get("Description", "")[:400],
            "phase": r.get("Phase", ""),
            "status": r.get("Status", ""),
            "updated": r.get("Updated", ""),
        })
    _, srows = _md_table_rows(_md_section(text, "Sealed Tasks"))
    for r in srows:
        tid = r.get("Task ID", "")
        if not tid or tid.startswith("("):
            continue
        out["sealed"].append({
            "id": tid,
            "outcome": r.get("Outcome (one line)", "")[:300],
            "artifact": r.get("Artifact", "")[:200],
            "sealed": r.get("Sealed", ""),
        })
    out["counts"] = {"active": len(out["active"]), "sealed": len(out["sealed"])}
    return out


def build_api():
    roots = []
    total_n = total_s = 0
    last_m = 0
    for label, path in ROOTS:
        files = walk_root(label, path)
        roots.append({"label": label, "path": path, "files": files})
        total_n += len(files)
        total_s += sum(f["size"] for f in files)
        last_m = max([last_m] + [f["mtime"] for f in files])
    tasks = parse_tasks(roots)
    return {
        "server": {
            "pid": os.getpid(),
            "started": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(STARTED)),
            "started_epoch": STARTED,
            "port": PORT,
        },
        "generated": time.strftime("%Y-%m-%d %H:%M:%S"),
        "stats": {
            "total_files": total_n,
            "total_size": total_s,
            "roots": len(roots),
            "last_modified": last_m or None,
        },
        "roots": roots,
        "tasks": tasks,
        "skill": skill_info(),   # v1.3 compat (kept); the UI tiles read "guard"
        "guard": guard_info(),   # v1.4: Guard Status tile
        "resets": reset_restore_info(),  # v1.4: Session Reset & Restore tile
    }


def safe_path(label: str, rel: str):
    """Return the absolute path only when rel stays inside the label's root."""
    root = ROOTMAP.get(label)
    if not root or not rel or rel.startswith("/"):
        return None
    if ".." in unquote(rel).split("/"):
        return None
    p = os.path.normpath(os.path.join(root, unquote(rel)))
    rp, rb = os.path.realpath(p), os.path.realpath(root)
    if not rp.startswith(rb + os.sep):
        return None
    return rp if os.path.isfile(rp) else None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _no_store(self):
        self.send_header("Cache-Control", "no-store")

    def _send(self, code, body, ctype="text/plain; charset=utf-8", inline_name=None):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        if inline_name:
            self.send_header("Content-Disposition",
                             'inline; filename="%s"' % inline_name.replace('"', ""))
        self._no_store()
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_HEAD(self):  # noqa: N802
        self.do_GET()

    def do_GET(self):  # noqa: N802
        path, _, query = self.path.partition("?")
        if path == "/healthz":
            self._send(200, "ok")
            return
        if path == "/" or path == "/index.html":
            try:
                with open(UI, "rb") as f:
                    self._send(200, f.read(), "text/html; charset=utf-8")
            except OSError:
                self._send(500, "UI index.html not found")
            return
        if path == "/api/files":
            self._send(200, json.dumps(build_api(), ensure_ascii=False),
                       "application/json; charset=utf-8")
            return
        if path == "/api/tasks":
            self._send(200, json.dumps(session_tasks(), ensure_ascii=False),
                       "application/json; charset=utf-8")
            return
        if path.startswith("/file/"):
            rest = path[len("/file/"):]
            label, _, rel = rest.partition("/")
            fp = safe_path(label, rel)
            if not fp:
                self._send(403, "File access denied (outside the allowed root)")
                return
            size = os.path.getsize(fp)
            name = os.path.basename(fp)
            # ?dl=1 -> attachment (forced download); default inline (preview)
            dl = parse_qs(query).get("dl", ["0"])[0] in ("1", "true", "yes")
            disp = "attachment" if dl else "inline"
            self.send_response(200)
            self.send_header("Content-Type", ctype_of(fp))
            self.send_header("Content-Length", str(size))
            self.send_header("Content-Disposition",
                             '%s; filename="%s"' % (disp, name.replace('"', "")))
            self._no_store()
            self.end_headers()
            if self.command == "HEAD":
                return
            with open(fp, "rb") as f:
                while True:
                    chunk = f.read(65536)
                    if not chunk:
                        break
                    try:
                        self.wfile.write(chunk)
                    except BrokenPipeError:
                        return
            return
        self._send(404, "Not Found")

    def log_message(self, fmt, *args):
        sys.stdout.write("[%s] %s\n" % (
            time.strftime("%Y-%m-%d %H:%M:%S"), fmt % args))
        sys.stdout.flush()


if __name__ == "__main__":
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))
    with open(STAMP, "w") as f:  # v1.4: content-exact freshness anchor
        f.write(_code_md5() + "\n")      # (explorer.sh --ensure compares this)
    print("[explorer] START pid %s bind %s:%d ui %s"
          % (os.getpid(), BIND, PORT, UI), flush=True)
    try:
        ThreadingHTTPServer((BIND, PORT), Handler).serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        for _f in (PIDFILE, STAMP):
            try:
                os.remove(_f)
            except OSError:
                pass
