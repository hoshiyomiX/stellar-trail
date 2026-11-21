#!/usr/bin/env python3
"""
explorer.py — Task Files Explorer server v1.13 (zscripts-root + file manager)
=========================================================================
v1.13 (Task 84 / v5.7.10, owner orders "Task File Explorer hanya mengolah
direktori .zscripts/ saja" + "Add feature Task File Manager: delete files
dan multi selection action option" + "add force copy files ke ..zscripts/
jika di folder download (default z.ai path) masih ada"):
  · ROOTS = .zscripts/ ONLY — the download/ + archive/ roots are retired;
    owner deliveries reach the file manager via the watcher v2.5 duty-2d
    importer (download/ -> .zscripts/, MOVE semantics) instead of being
    served in place.
  · Operational files are HIDDEN at the .zscripts root (dev.sh, explorer.*,
    watcher.*, stellar-trail-canonical/, *.pid/*.log/... — the persistence
    layer's own surface) and WRITE-PROTECTED: the delete/zip/move/copy
    endpoints refuse any path whose first component is operational, and
    any path with a dotfile component.
  · NEW file-manager write API (POST, JSON): /api/delete (permanent, with
    per-path results), /api/zip (server-side zipfile -> .zscripts/<name>.zip,
    a normal managed file), /api/move + /api/copy (dest = existing-or-new
    subfolder under .zscripts/; existing targets refused, never silently
    overwritten), and GET /api/folders (destination picker data). The UI
    owns confirmation dialogs (owner: permanent + miuix confirm); the API
    owns enforcement (protection + path safety + cache invalidation).
  · CSRF posture: the write API requires Content-Type: application/json
    (a non-simple content type — a cross-site form can never send it
    without a CORS preflight, which this server never answers) and, when
    the Origin header is present, it must match the request Host.
v1.12 (Task 81 / v5.7.6, owner orders "skill stellar-trail anti
  package.json/fullstack-dev" + "TFM harus survive dan persistent"): the
  package.json stand-down is RETIRED — the launcher (explorer.sh v1.6)
  decides by PORT REALITY (first-free 3000..3005, fallback mode, automatic
  reclaim of :3000). The guard block stops reporting file-presence
  (standdown stays in the API for compatibility but is always False) and
  reports the actual serving mode instead: port_mode = "primary" (:3000,
  the public preview via ingress :81) | "fallback" (another server holds
  :3000; the explorer is alive + monitored and reclaims it once free).
  A package.json at the project root never disables the explorer again.
v1.11 (Task 77 / v5.7.4, owner order "Set default location at zscripts/,
  bukan download/"): the guard block's canonical-version read moves to
  .zscripts/stellar-trail-canonical/ (the skill canonical relocated out of
  download/ — the platform "All files in task" auto-preview reacts to
  download/ writes, so the 25-file canonical + its release-day refresh
  bursts leave the panel); the v1.7 download-root scan exclusion stays as
  a stale-resurrection guard for the legacy path.
v1.10 (Task 67, owner order "popup preview platform mati permanent"): the
  /file/ serving default FLIPS inline -> ATTACHMENT. A direct hit on a
  /file/<label>/<rel> URL (typed, pasted, linked from anywhere, opened by
  any foreign file panel) now DOWNLOADS — the browser inline viewer and
  every platform preview popup built on our file URLs die at the source.
  The explorer's own preview modal is UNAFFECTED: its text branches read
  via fetch() (Content-Disposition never applies to subresource fetches),
  and its <img>/<iframe> sources carry ?inline=1 — the ONLY inline path
  (?inline=1; ?dl=1 keeps its explicit-download meaning; default =
  attachment). Security side-win: html/svg/pdf-as-document served as
  attachments can no longer execute as standalone documents via URL.
  UI v5.0.1 companions (same task): the modal's img/pdf hrefs carry
  ?inline=1, the binary-branch download carries ?dl=1, and the
  static-copy state AUTO-BREAKS OUT to the live root the moment the live
  feed answers on that origin (the platform file-preview chrome that
  wraps a static copy is replaced by the live app — once per page,
  guarded; supersedes the v4.2 manual-only recovery note per this owner
  order; the banner + manual button remain as the fallback when
  top-level navigation is blocked).
v1.9 (Task 63, owner order #2 — task-history source decision): the task
  list now parses worklog.md + worklog-archive.md MERGED (chronological:
  archive first, live worklog last — the later section wins on any Task-ID
  overlap). Decision rationale (analysis delivered with Task 63): the
  worklog family is the authoritative append-only ledger (D11) and the
  ONLY source carrying per-task section bodies, which the rail's
  related-files mapping tokenizes; memory/SESSION-STATE.md is a volatile
  checkpoint snapshot (atomic full rewrite, Active + last-5-sealed only,
  no file mapping) — wrong shape for history. Rotation keeps only the
  last 3 Task sections in worklog.md, which starved the 14-slot rail to
  3 cards; merging the archive restores full depth (~88 sections,
  ~390 KB — trivial next to the token-index parse) at zero UI change.
  The /api/tasks SESSION-STATE lens stays as-is (a different view, not
  the rail's source).
v1.8 (Task 53): the UI page is the v5.0 single-file build (Vue 3 + the real
  miuix-vue component layer, built by Vite at release time) — the serving
  contract is UNCHANGED: one self-contained explorer-ui/index.html with
  zero runtime dependencies, read per request; no new routes, no /assets.
Chain served:  preview-<bot-id>.space-z.ai  ->  platform ingress :81
                ->  127.0.0.1:3000  ->  THIS SERVER

Endpoints:
  GET /                      UI page (explorer-ui/index.html, read per
                             request so UI edits show up without a restart)
  GET /api/files             JSON: download/ + archive/ inventory, stats,
                             the task list parsed from worklog.md +
                             worklog-archive.md (v1.9 merged ledger), the
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
                               root=zscripts|all          (default all;
                               v1.13: the single root is .zscripts/)
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
                             v1.10: served as an ATTACHMENT by default
                             (direct URL hits download — foreign inline
                             previews die); ?inline=1 = the ONLY inline
                             path (the preview modal's img/iframe);
                             ?dl=1 = explicit attachment (unchanged)
  GET /healthz               health check for explorer.sh / watcher.sh
  GET /api/folders           v1.13: destination-picker data — owner-writable
                             subfolders of .zscripts/ (operational surface +
                             dotfiles excluded), depth 2, for the move/copy
                             dialogs
  POST /api/delete           v1.13 file-manager write API (JSON bodies;
                             Content-Type: application/json REQUIRED — a
                             non-simple type is preflight-protected, so a
                             cross-site form can never reach these; Origin,
                             when present, must match Host). {paths:[key..]}
                             permanently deletes (the UI confirmed); every
                             path is re-validated server-side: inside the
                             root, no traversal, no dotfile component, and
                             NOT operational surface (dev.sh, explorer.*,
                             watcher.*, canonical/, *.pid... are refused);
                             per-path results + cache invalidation on change
  POST /api/zip              {paths:[..], name?} -> server-side zip written
                             to .zscripts/<name|batch-ts>.zip (a normal
                             managed file: listed, downloadable, deletable;
                             never overwrites — -2, -3... on collision);
                             response carries the new key + href?dl=1
  POST /api/move             {paths:[..], dest:"zscripts/<subfolder"|""}
                             moves the selection into dest (created when
                             missing); an existing same-named target is
                             REFUSED per-path (never silently overwritten)
  POST /api/copy             same contract as move, duplicating instead

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
import shutil
import sys
import threading
import time
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote

PROJECT = os.environ.get("STELLAR_PROJECT", "/home/z/my-project")
ZDIR = os.path.join(PROJECT, ".zscripts")
UI = os.path.join(ZDIR, "explorer-ui", "index.html")
PIDFILE = os.path.join(ZDIR, "explorer.pid")
STAMP = os.path.join(ZDIR, "explorer.code-stamp")  # v1.4: md5 of the RUNNING server's source
WORKLOG = os.path.join(PROJECT, "worklog.md")
WORKLOG_ARCHIVE = os.path.join(PROJECT, "worklog-archive.md")  # v1.9: merged into parse_tasks — rotation moves older Task sections here, and the rail needs the depth
SESSION_STATE = os.path.join(PROJECT, "memory", "SESSION-STATE.md")

# label -> absolute path (the label is used in /file/<label>/ URLs)
# v1.13 (Task 84, owner order "Task File Explorer hanya mengolah direktori
# .zscripts/ saja"): the single root is .zscripts/ — owner deliveries are
# IMPORTED there by the watcher v2.5 duty-2d importer (MOVE semantics), so
# the explorer serves exactly what the file manager manages.
ROOTS = [
    ("zscripts", ZDIR),
]
ROOTMAP = dict(ROOTS)
# v1.13: operational surface of the .zscripts root — HIDDEN from the listing
# (the file manager shows owner files only, per the Task-84 view-scope
# answer) and WRITE-PROTECTED in the delete/zip/move/copy API (never
# deletable via the UI). KEEP IN SYNC with scripts/import-download.sh
# (PROTECTED_DIRS/FILES/SUFFIXES) — the two lists are a pair.
HIDE_DIRS = {
    "explorer-ui",                # the deployed UI (single-file build)
    "stellar-trail-canonical",    # the skill canonical copy (restore source)
}
HIDE_FILES = {
    "dev.sh", "dev.sh.foreign.bak",       # boot chain
    "explorer.py", "explorer.sh",         # the explorer itself
    "watcher.sh", "repo-snapshot.sh",     # persistence layer
    "import-download.sh",                 # the deployed importer (v1.13 copy)
    "explorer.log", "watcher.log", "boot.log",
    "explorer.pid", "watcher.pid", "explorer.port", "explorer.code-stamp",
    "bootstrap.state",
}
HIDE_SUFFIXES = (".pid", ".log", ".port", ".state", ".code-stamp", ".noticed", ".stop")
# v1.7 ROOT_EXCLUDES mechanism kept (root-level dir prune) — now carries the
# v1.13 hide set; the legacy "download": ("stellar-trail",) entry is retired
# with the download root itself.
ROOT_EXCLUDES = {
    "zscripts": tuple(HIDE_DIRS),
}
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

# v1.13 file-manager write API knobs
FM_MAX_PATHS = 200              # hard cap on paths[] per write request
FM_MAX_BODY = 2 * 1024 * 1024   # JSON body cap (2 MB)
FM_ZIP_MAX_TOTAL = 512 * 1024 * 1024  # server-side zip source cap (512 MB)


def _hidden_at_root(name: str) -> bool:
    """v1.13: True when a ROOT-LEVEL entry is operational surface — hidden
    from the listing (HIDE_FILES exact names + HIDE_SUFFIXES + dotfiles).
    Deeper levels are unaffected: a task artifact named boot.log inside an
    owner subfolder stays visible; only the .zscripts root itself is the
    persistence layer's operational surface."""
    if name.startswith(".") or name in HIDE_FILES or name in HIDE_DIRS:
        return True
    return name.endswith(HIDE_SUFFIXES)


def _write_denied(rel: str) -> str:
    """v1.13: None when rel is a legal WRITE target ('' = the root itself,
    legal as a move/copy destination), else the denial reason. The FIRST
    path component decides operational collisions; dotfiles are refused at
    ANY depth (the hidden state layer is never writable via the API)."""
    if rel.startswith("/") or "\\" in rel:
        return "absolute or backslash path refused"
    parts = [p for p in unquote(rel).split("/") if p not in ("", ".")]
    if not parts:
        return None  # the bare root: legal destination only
    if ".." in parts:
        return "path traversal refused"
    first = parts[0]
    if _hidden_at_root(first):
        return "operational path refused (protected: %s)" % first
    for p in parts:
        if p.startswith("."):
            return "hidden path component refused (%s)" % p
    return None


def _resolve_write(label: str, rel: str, need_exists=True):
    """v1.13: ('<abs>', None) when key label/rel is a legal write source,
    else (None, reason). need_exists=False allows a not-yet-existing
    destination (move/copy dest, new zip name)."""
    root = ROOTMAP.get(label)
    if not root:
        return None, "unknown root %r" % label
    if rel.startswith("/"):
        return None, "absolute path refused"
    reason = _write_denied(rel)
    if reason:
        return None, reason
    p = os.path.normpath(os.path.join(root, unquote(rel)))
    rp, rb = os.path.realpath(p), os.path.realpath(root)
    if not rp.startswith(rb + os.sep) and rp != rb:
        return None, "outside the root refused"
    if need_exists and not os.path.exists(p):
        return None, "not found"
    return p, None


def _invalidate_cache():
    """v1.13: force the next /api request to rebuild the inventory after a
    successful mutation (delete/zip/move/copy)."""
    with _cache_lock:
        _cache["built_at"] = 0.0


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
    skip_top = set(ROOT_EXCLUDES.get(label, ()))  # v1.7: root-level prune only
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = os.path.relpath(dirpath, root)
        depth = 0 if rel_dir == "." else rel_dir.count(os.sep) + 1
        if depth >= MAX_DEPTH:
            dirnames[:] = []
        if rel_dir == ".":  # v1.7 root dirs + v1.13 root operational FILES
            dirnames[:] = sorted(d for d in dirnames
                                 if not d.startswith(".") and d not in skip_top)
            filenames = [fn for fn in filenames
                         if not _hidden_at_root(fn)]
        else:
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
    """Parse 'Task ID: n / Task: ...' sections from worklog.md +
    worklog-archive.md (v1.9: the merged ledger — archive first, live
    worklog last, so the LATER section wins on Task-ID overlap), then map
    each file to the LAST task that mentions its file name.

    v1.5 token-index algorithm (was: per-(file, task) substring scans —
    O(tasks x files x section-bytes), ~44 ms per task per 22k files, so an
    un-rotated 30-section worklog paid ~1.3 s per /api/files request):
    tokenize each section once (O(worklog bytes)), then one O(1) set
    lookup per (file, task). A file maps when its name or label/rel path
    appears as a WHOLE TOKEN in the section — exactly how file names occur
    in the worklog's markdown (bullets, backticks, parens)."""
    text = ""
    for path in (WORKLOG_ARCHIVE, WORKLOG):  # chronological: archive older, worklog newer
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                text += f.read() + "\n\n---\n\n"
        except OSError:
            pass  # missing archive pre-rotation, missing worklog cold-start: parse what exists
    if not text.strip():
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
        with open(os.path.join(PROJECT, ".zscripts", "stellar-trail-canonical", "assets", "integrity.version"),
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
        # v1.12 (Task 81, owner order "anti package.json/fullstack-dev"):
        # the package.json stand-down is RETIRED — the launcher decides by
        # PORT REALITY (explorer.sh v1.6: first-free 3000..3005, fallback +
        # auto-reclaim). The legacy `standdown` key stays in the API for
        # compatibility but is always False; `port_mode` reports the actual
        # serving mode. A package.json NEVER disables the explorer again.
        "standdown": False,
        "port_mode": "fallback" if PORT != 3000 else "primary",
        "port": PORT,
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

    # ---- v1.13 file-manager write API ---------------------------------
    def _write_request_guard(self):
        """CSRF + shape guard shared by every write endpoint. Returns None
        when the request may proceed, else (code, message) to send."""
        origin = self.headers.get("Origin")
        if origin:
            host = self.headers.get("Host", "")
            # same-origin only: http(s)://<host> (the preview ingress and
            # 127.0.0.1 both satisfy this; a foreign origin is refused)
            if origin not in ("http://%s" % host, "https://%s" % host):
                return 403, "cross-origin write refused"
        ctype = (self.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        if ctype != "application/json":
            # a non-simple content type is preflight-protected by the browser
            # itself; requiring it also rejects every plain-form cross-site
            # attempt that somehow reaches us
            return 415, "Content-Type: application/json required"
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = 0
        if length <= 0 or length > FM_MAX_BODY:
            return 400, "missing or oversized JSON body"
        return None

    def _read_json(self):
        """Read + parse the guarded JSON body (caller ran _write_request_guard)."""
        try:
            raw = self.rfile.read(int(self.headers.get("Content-Length") or 0))
            data = json.loads(raw.decode("utf-8"))
        except (OSError, ValueError, UnicodeDecodeError):
            return None
        return data if isinstance(data, dict) else None

    @staticmethod
    def _key_split(key):
        """'zscripts/<rel>' -> (label, rel); malformed keys are refused."""
        if not isinstance(key, str):
            return None, None
        label, sep, rel = key.partition("/")
        if not sep or not label or not rel:
            return None, None
        return label, rel

    def do_POST(self):  # noqa: N802
        path, _, _query = self.path.partition("?")
        guard = self._write_request_guard()
        if guard:
            self._send(guard[0], guard[1])
            return
        data = self._read_json()
        if data is None:
            self._send(400, "invalid JSON body")
            return
        paths = data.get("paths")
        if not isinstance(paths, list) or not paths or len(paths) > FM_MAX_PATHS:
            self._send(400, "paths[] required (1..%d entries)" % FM_MAX_PATHS)
            return
        for k in paths:
            if not isinstance(k, str):
                self._send(400, "paths[] must be strings")
                return

        if path == "/api/delete":
            # permanent delete — the UI confirmed; the API enforces protection
            results, deleted = [], 0
            for k in paths:
                label, rel = self._key_split(k)
                if rel is None:
                    results.append({"key": k, "ok": False, "error": "malformed key"})
                    continue
                p, reason = _resolve_write(label, rel, need_exists=True)
                if reason:
                    results.append({"key": k, "ok": False, "error": reason})
                    continue
                try:
                    if os.path.isdir(p) and not os.path.islink(p):
                        shutil.rmtree(p)
                    else:
                        os.remove(p)
                    deleted += 1
                    results.append({"key": k, "ok": True})
                except OSError as e:
                    results.append({"key": k, "ok": False, "error": str(e)})
            if deleted:
                _invalidate_cache()
            self._send(200, json.dumps({"deleted": deleted, "results": results},
                                       ensure_ascii=False),
                       "application/json; charset=utf-8")
            return

        if path == "/api/zip":
            srcs, total = [], 0
            for k in paths:
                label, rel = self._key_split(k)
                if rel is None:
                    self._send(400, "malformed key: %r" % k)
                    return
                p, reason = _resolve_write(label, rel, need_exists=True)
                if reason:
                    self._send(403, "refused %s: %s" % (k, reason))
                    return
                try:
                    total += os.path.getsize(p) if os.path.isfile(p) else 0
                except OSError:
                    pass
                srcs.append(p)
            if total > FM_ZIP_MAX_TOTAL:
                self._send(413, "selection too large to zip (cap %d MB)"
                           % (FM_ZIP_MAX_TOTAL // (1024 * 1024)))
                return
            name = data.get("name")
            if not (isinstance(name, str) and name and
                    re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", name)
                    and not name.startswith(".")):
                name = "batch-" + time.strftime("%Y%m%d-%H%M%S")
            if not name.lower().endswith(".zip"):
                name += ".zip"
            zpath, reason = _resolve_write("zscripts", name, need_exists=False)
            if reason:
                self._send(400, "zip name refused: %s" % reason)
                return
            # never overwrite: batch-<ts>-2.zip, -3.zip, ... on collision
            base, n = zpath, 1
            while os.path.exists(zpath):
                n += 1
                zpath = "%s-%d.zip" % (base[:-4], n)
            try:
                with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as zf:
                    for p in srcs:
                        if os.path.isfile(p):
                            zf.write(p, os.path.basename(p))
                        else:
                            for dirpath, dirnames, filenames in os.walk(p):
                                dirnames[:] = sorted(d for d in dirnames
                                                     if not d.startswith("."))
                                for fn in sorted(filenames):
                                    if fn.startswith("."):
                                        continue
                                    fp = os.path.join(dirpath, fn)
                                    zf.write(fp, os.path.relpath(fp, os.path.dirname(p)))
            except OSError as e:
                try:
                    os.remove(zpath)
                except OSError:
                    pass
                self._send(500, "zip failed: %s" % e)
                return
            _invalidate_cache()
            self._send(200, json.dumps(
                {"ok": True, "name": os.path.basename(zpath),
                 "key": "zscripts/%s" % os.path.basename(zpath),
                 "href": "/file/zscripts/%s?dl=1" % os.path.basename(zpath),
                 "size": os.path.getsize(zpath)}, ensure_ascii=False),
                       "application/json; charset=utf-8")
            return

        if path in ("/api/move", "/api/copy"):
            dest = data.get("dest")
            if not isinstance(dest, str):
                self._send(400, "dest required (a subfolder key or \"\" for the root)")
                return
            dlabel, dsep, drel = dest.partition("/")
            if not dsep:
                # bare folder name = that folder under the root; "" = the root
                dlabel, drel = "zscripts", dest
            drel = drel.rstrip("/")
            dpath, reason = _resolve_write(dlabel, drel, need_exists=False)
            if reason:
                self._send(400, "dest refused: %s" % reason)
                return
            try:
                os.makedirs(dpath, exist_ok=True)
            except OSError as e:
                self._send(500, "dest not creatable: %s" % e)
                return
            results, done = [], 0
            for k in paths:
                label, rel = self._key_split(k)
                if rel is None:
                    results.append({"key": k, "ok": False, "error": "malformed key"})
                    continue
                p, r2 = _resolve_write(label, rel, need_exists=True)
                if r2:
                    results.append({"key": k, "ok": False, "error": r2})
                    continue
                target = os.path.join(dpath, os.path.basename(p))
                if os.path.exists(target):
                    results.append({"key": k, "ok": False,
                                    "error": "destination already has %s" % os.path.basename(p)})
                    continue
                try:
                    if path == "/api/move":
                        shutil.move(p, target)
                    elif os.path.isdir(p) and not os.path.islink(p):
                        shutil.copytree(p, target)
                    else:
                        shutil.copy2(p, target)
                    done += 1
                    results.append({"key": k, "ok": True,
                                    "dest": "%s/%s" % (drel, os.path.basename(p))})
                except OSError as e:
                    results.append({"key": k, "ok": False, "error": str(e)})
            if done:
                _invalidate_cache()
            self._send(200, json.dumps({"moved" if path == "/api/move" else "copied": done,
                                        "results": results}, ensure_ascii=False),
                       "application/json; charset=utf-8")
            return

        self._send(404, "Not Found")

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
        if path == "/api/folders":
            # v1.13: destination-picker data — owner-writable subfolders of
            # the root (operational surface + dotfiles excluded), depth 2.
            folders = []
            for dirpath, dirnames, _fns in os.walk(ZDIR):
                rel_dir = os.path.relpath(dirpath, ZDIR)
                depth = 0 if rel_dir == "." else rel_dir.count(os.sep) + 1
                if rel_dir == ".":
                    dirnames[:] = sorted(
                        d for d in dirnames
                        if not d.startswith(".") and not _hidden_at_root(d))
                else:
                    dirnames[:] = sorted(
                        d for d in dirnames if not d.startswith("."))
                    if depth <= 2:
                        folders.append(rel_dir)
                if depth >= 2:
                    dirnames[:] = []
            self._send(200, json.dumps({"root": "zscripts", "folders": folders},
                                       ensure_ascii=False),
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
            # v1.10 (Task 67): default ATTACHMENT — direct URL hits download,
            # never inline-preview (browser viewer + platform preview popups
            # die at the source). ?inline=1 = the ONLY inline path (the modal's
            # own <img>/<iframe>); ?dl=1 keeps its explicit-download meaning.
            dl = q.get("dl", ["0"])[0] in ("1", "true", "yes")
            inl = q.get("inline", ["0"])[0] in ("1", "true", "yes")
            disp = "inline" if (inl and not dl) else "attachment"
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
