#!/usr/bin/env python3
"""
explorer.py — Task Files Explorer server v1.6 (preview-popup replacement)
=========================================================================
Chain served:  preview-<bot-id>.space-z.ai  ->  platform ingress :81
                ->  127.0.0.1:3000  ->  THIS SERVER

Endpoints:
  GET /                      UI page (explorer-ui/index.html, read per
                             request so UI edits show up without a restart)
  GET /api/files             JSON: download/ + archive/ inventory, stats,
                             the task list parsed from worklog.md, the
                             skill block (stellar-trail version, watcher),
                             a "guard" block (live vs canonical version,
                             watcher liveness, and THIS process's code
                             freshness) and a "resets" block (boot resets +
                             restore counters; missing logs = empty
                             counters, never an error).
                             v1.5: the per-root "files" arrays are CAPPED
                             at ?max= entries per root (default 1000) —
                             each root also carries files_total +
                             files_truncated so a client can page. ?max=0
                             omits the arrays entirely (slim poll mode);
                             stats carries type_counts; roots carry
                             files_total regardless of the cap.
  GET /api/list              v1.5: paginated file list with SERVER-SIDE
                             filter + sort — the scalable browsing path for
                             large inventories (the UI polls a slim
                             /api/files?max=0 for tiles and pages through
                             /api/list for the cards):
                               root=download|archive|all   (default all)
                               q=<substring>               (name/path)
                               type=doc|pdf|img|data|pkg|code|office|other|all
                               task=<task id>              (worklog mapping)
                               sort=mtime|name|size        (default mtime)
                               dir=asc|desc                (default desc)
                               page=1..                    (1-based)
                               per_page=1..500             (default 100)
  GET /api/tasks             JSON: the Session Task list parsed from
                             memory/SESSION-STATE.md (Active + Sealed
                             tables + checkpoint line; missing file =
                             empty structure, never an error)
  GET /file/<label>/<rel>    raw file (path guard: only inside ROOTS);
                             add ?dl=1 to send it as an ATTACHMENT
                             (forced download via Content-Disposition: attachment)
  GET /healthz               health check for explorer.sh / watcher.sh

v1.5 scalability contract (Task 30, evidence 2026-10-23 — v1.4 paid
~420 ms + 4.9 MB PER /api/files hit at 22k files, re-paid every 10 s poll;
parse_tasks alone scaled at ~44 ms per task-section per 22k files):
  - ONE cached inventory shared by /api/files + /api/list; at most one
    rebuild per CACHE_TTL (single-builder lock — a burst of requests
    shares one rebuild, never queues one rebuild per request).
  - parse_tasks uses a token index (O(worklog + files x tasks) set
    lookups) instead of per-(file, task) substring scans. Semantics
    note: a file maps to a task when its name or label/rel path appears
    as a whole token in the task section (how names appear in the
    markdown) — the old substring scan also caught names glued inside
    longer words, which does not occur in the real format.
  - /healthz and /file/ never touch the inventory — they stay O(1) and
    responsive even while a rebuild is in flight.

v1.6 startup-freeze contract (Task 32/34, evidence 2026-10-23 — v1.5 paid
a FULL list re-render + entrance-animation replay on EVERY 10 s poll:
the change detection keyed on inventory_built flipped on every rebuild
because CACHE_TTL 3 s < the 10 s poll interval, so each poll was a cold
rebuild with a fresh timestamp even with ZERO disk changes):
  - content_sig: md5 over (key|mtime|size|type|task) per file plus the
    task digest — changes ONLY when the served data actually changes.
    /api/files and /api/list both expose it; the UI compares it across
    polls (falls back to inventory_built when an old server lacks it).
  - CACHE_TTL 12 s: most 10 s polls hit the warm cache; a real change
    becomes visible within ~2 polls (<= ~22 s).
  - skill/guard/resets are folded into the cached build — computed once
    per rebuild instead of ~2.6 MB of log regex scans + a source md5 per
    request. Their tiles refresh per poll from the cached payload.

At startup the server writes .zscripts/explorer.code-stamp (md5 of its own
source) — the freshness anchor explorer.sh compares. The guardian block
reads assets/integrity.version directly.

Run as a double-fork orphan by explorer.sh (PPID=1, setsid) so it survives
the per-tool-call process cleanup. Binds 127.0.0.1 only.
"""
import hashlib
import json
import os
import re
import sys
import threading
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

# label -> absolute path (the label is used in /file/<label>/ URLs)
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

# v1.5/v1.6 scalability knobs
CACHE_TTL = 12.0                # v1.6: > the 10 s UI poll so most polls hit the warm cache; a change shows within ~2 polls (~22 s). v1.5's 3 s made every poll a cold rebuild — the timestamp flip then triggered spurious client re-renders every 10 s (measured)
API_FILES_DEFAULT_MAX = 1000    # default per-root cap on /api/files arrays
API_LIST_MAX_PER_PAGE = 500     # hard ceiling for /api/list per_page


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


# v1.5: filename-candidate tokenizer — keep the chars that occur in real
# artifact names; markdown structure (spaces, backticks, parens, commas,
# pipes, quotes) is the delimiter set.
_TOKEN_SPLIT = re.compile(r"[^A-Za-z0-9_./@+-]+")


def parse_tasks(roots):
    """Parse 'Task ID: n / Task: ...' sections from worklog.md, then map each
    file to the LAST task that mentions its file name.

    v1.5 token-index algorithm (was: per-(file, task) substring scans —
    O(tasks x files x section-bytes), ~44 ms per task per 22k files, so an
    un-rotated 30-section worklog paid ~1.3 s per /api/files request):
    tokenize each section once (O(worklog bytes)), then one O(1) set
    lookup per (file, task). A file maps when its name or label/rel path
    appears as a WHOLE TOKEN in the section — exactly how file names occur
    in the worklog's markdown (bullets, backticks, parens)."""
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
            title = re.sub(r"\s+", " ", title)[:600]  # v1.6: full text for the UI v4.1 rail (v1.5's 90 cut mid-sentence)
            tasks.append({"id": m_id.group(1), "title": title,
                          "sec": sec, "tokens": None})
    all_files = [f for r in roots for f in r["files"]]
    mapping = {}
    for t in tasks:  # chronological order; the later task overwrites -> wins
        t["tokens"] = set(m for m in _TOKEN_SPLIT.split(t["sec"]) if len(m) > 2)
        hits = [f["key"] for f in all_files
                if f["name"] in t["tokens"] or f["key"] in t["tokens"]]
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


def build_inventory():
    """v1.5: the expensive part — full walk + task mapping + type counts —
    built ONCE per CACHE_TTL and shared by every /api/files and /api/list
    request. The returned dict is treated as READ-ONLY by all consumers
    (handlers copy/slice; they never mutate)."""
    roots = []
    total_n = total_s = 0
    last_m = 0
    type_counts = {}
    for label, path in ROOTS:
        files = walk_root(label, path)
        roots.append({"label": label, "path": path, "files": files,
                      "files_total": len(files)})
        total_n += len(files)
        total_s += sum(f["size"] for f in files)
        if files:
            last_m = max([last_m] + [f["mtime"] for f in files])
        for f in files:
            type_counts[f["type"]] = type_counts.get(f["type"], 0) + 1
    tasks = parse_tasks(roots)

    # v1.6: content signature — flips ONLY when the served data actually
    # changes (file set / mtimes / sizes / types / task attribution + the
    # task list itself). A rebuild that changes nothing yields the SAME
    # signature; the v1.5 timestamp flipped every rebuild, which made the
    # UI re-render the whole list + replay entrance animations on every
    # 10 s poll (measured — the startup "UI freeze" root cause).
    h = hashlib.md5()
    for r in roots:
        h.update(("root:%s\n" % r["label"]).encode("utf-8"))
        for f in r["files"]:
            h.update(("%s|%d|%d|%s|%s\n" % (
                f["key"], f["mtime"], f["size"], f["type"],
                f.get("task") or "")).encode("utf-8"))
    for t in tasks:
        h.update(("task:%s|%s|%d\n" % (t["id"], t["title"], t["count"])).encode("utf-8"))

    return {
        "built": time.strftime("%Y-%m-%d %H:%M:%S"),
        "built_epoch": time.time(),
        "content_sig": h.hexdigest(),
        "stats": {
            "total_files": total_n,
            "total_size": total_s,
            "roots": len(roots),
            "last_modified": last_m or None,
            "type_counts": type_counts,
        },
        "roots": roots,
        "tasks": tasks,
        # v1.6: folded per-request reads — computed once per rebuild and
        # served from the cache (they change rarely; the UI tiles refresh
        # per poll from this payload)
        "skill": skill_info(),
        "guard": guard_info(),
        "resets": reset_restore_info(),
    }


_cache = {"data": None, "built_at": 0.0}
_cache_lock = threading.Lock()


def get_inventory():
    """v1.5: cached inventory accessor — at most ONE rebuild per CACHE_TTL.
    A request inside the TTL gets the cached copy instantly; concurrent
    requests after expiry share a single rebuild (single-builder lock —
    no rebuild stampede, no per-request re-walk). The first build ever
    (cold cache) is the only synchronous wait."""
    now = time.time()
    c = _cache["data"]
    if c is not None and now - _cache["built_at"] < CACHE_TTL:
        return c
    with _cache_lock:
        if _cache["data"] is not None and time.time() - _cache["built_at"] < CACHE_TTL:
            return _cache["data"]  # another thread rebuilt it while we waited
        data = build_inventory()
        _cache["data"] = data
        _cache["built_at"] = time.time()
        return data


def api_files_payload(inv, max_per_root):
    """/api/files response — shape-compatible with v1.4 plus the v1.5 cap
    fields. max_per_root < 0 = the default cap; 0 = omit the arrays."""
    if max_per_root is None:
        max_per_root = API_FILES_DEFAULT_MAX
    roots_out = []
    for r in inv["roots"]:
        entry = {"label": r["label"], "path": r["path"],
                 "files_total": r["files_total"]}
        if max_per_root > 0:
            entry["files"] = r["files"][:max_per_root]
            entry["files_truncated"] = r["files_total"] > max_per_root
        else:
            entry["files"] = []
            entry["files_truncated"] = r["files_total"] > 0
        roots_out.append(entry)
    return {
        "server": {
            "pid": os.getpid(),
            "started": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(STARTED)),
            "started_epoch": STARTED,
            "port": PORT,
        },
        "generated": time.strftime("%Y-%m-%d %H:%M:%S"),
        "inventory_built": inv["built"],
        "content_sig": inv["content_sig"],  # v1.6: stable change signal (timestamp-free)
        "stats": inv["stats"],
        "roots": roots_out,
        "tasks": inv["tasks"],
        "skill": inv["skill"],    # v1.6: folded into the cached build
        "guard": inv["guard"],
        "resets": inv["resets"],
    }


def _int_arg(query, key, default, lo, hi):
    try:
        v = int(query.get(key, [str(default)])[0])
    except (KeyError, ValueError):
        v = default
    return max(lo, min(hi, v))


_SORT_KEYS = {
    "name": lambda f: (f["name"].lower(), f["mtime"]),
    "size": lambda f: (f["size"], f["name"].lower()),
    "mtime": lambda f: (f["mtime"], f["name"].lower()),
}


def api_list_payload(inv, query):
    """v1.5: /api/list — paginated, filtered, sorted file list served from
    the shared cached inventory. This is the scalable browsing path: the
    response is bounded by per_page (<= 500), never by the inventory size."""
    root = query.get("root", ["all"])[0]
    if root not in ROOTMAP and root != "all":
        root = "all"
    q = query.get("q", [""])[0].strip().lower()
    type_f = query.get("type", ["all"])[0]
    if type_f not in ("doc", "pdf", "img", "data", "pkg", "code", "office", "other"):
        type_f = "all"
    task = query.get("task", [""])[0].strip()
    sort_col = query.get("sort", ["mtime"])[0]
    if sort_col not in _SORT_KEYS:
        sort_col = "mtime"
    sort_dir = query.get("dir", ["desc"])[0]
    if sort_dir not in ("asc", "desc"):
        sort_dir = "desc"
    per_page = _int_arg(query, "per_page", 100, 1, API_LIST_MAX_PER_PAGE)

    files = [f for r in inv["roots"] if root == "all" or r["label"] == root
             for f in r["files"]]
    if type_f != "all":
        files = [f for f in files if f["type"] == type_f]
    if task:
        files = [f for f in files if f.get("task") == task]
    if q:
        files = [f for f in files
                 if q in f["rel"].lower() or q in f["name"].lower()]
    files.sort(key=_SORT_KEYS[sort_col], reverse=(sort_dir == "desc"))

    total = len(files)
    pages = max(1, -(-total // per_page))
    page = _int_arg(query, "page", 1, 1, pages)
    start = (page - 1) * per_page
    return {
        "root": root, "q": q, "type": type_f, "task": task,
        "sort": sort_col, "dir": sort_dir,
        "page": page, "per_page": per_page, "pages": pages, "total": total,
        "files": files[start:start + per_page],
        "inventory_built": inv["built"],
        "content_sig": inv["content_sig"],  # v1.6: stable change signal
        "server_pid": os.getpid(),
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
        q = parse_qs(query, keep_blank_values=True)
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
            max_per_root = _int_arg(q, "max", API_FILES_DEFAULT_MAX, 0, 100000)
            inv = get_inventory()
            self._send(200, json.dumps(api_files_payload(inv, max_per_root),
                                       ensure_ascii=False),
                       "application/json; charset=utf-8")
            return
        if path == "/api/list":
            inv = get_inventory()
            self._send(200, json.dumps(api_list_payload(inv, q),
                                       ensure_ascii=False),
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


class ExplorerServer(ThreadingHTTPServer):
    """v1.6: listen backlog 64 — socketserver's default queue of 5 lets the
    kernel DROP SYNs during a 20-request burst, so dropped clients wait ~1 s
    for the SYN retransmit (measured on BOTH v1.5 and v1.6 — an environment
    behavior, not a v1.6 regression; it broke the burst budget in the task30
    harness). 64 covers page-load bursts (initial meta+list) and validator
    storms with margin."""
    request_queue_size = 64


if __name__ == "__main__":
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))
    with open(STAMP, "w") as f:  # v1.4: content-exact freshness anchor
        f.write(_code_md5() + "\n")      # (explorer.sh --ensure compares this)
    print("[explorer] START pid %s bind %s:%d ui %s"
          % (os.getpid(), BIND, PORT, UI), flush=True)
    try:
        ExplorerServer((BIND, PORT), Handler).serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        for _f in (PIDFILE, STAMP):
            try:
                os.remove(_f)
            except OSError:
                pass
