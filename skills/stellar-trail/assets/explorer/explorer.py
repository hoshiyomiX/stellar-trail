#!/usr/bin/env python3
"""
explorer.py — Task Files Explorer v1.1 (server final, pengganti popup preview)
=========================================================================
Rantai yang dilayani:  preview-<bot-id>.space-z.ai  ->  ingress platform :81
                        ->  127.0.0.1:3000  ->  SERVER INI

Endpoint:
  GET /                      halaman UI (explorer-ui/index.html, dibaca per
                             request agar edit UI langsung terlihat tanpa restart)
  GET /api/files             JSON: inventaris download/ + archive/, statistik,
                             daftar task yang diparse dari worklog.md, dan blok
                             skill (versi stellar-trail, heal terakhir, watcher)
  GET /file/<label>/<rel>    file mentah (guard path: hanya di dalam ROOTS);
                             tambah ?dl=1 untuk kirim sebagai ATTACHMENT
                             (unduhan paksa via Content-Disposition: attachment)
  GET /healthz               health-check untuk explorer.sh / watcher.sh

Dijalankan sebagai double-fork orphan oleh explorer.sh (PPID=1, setsid) agar
selamat dari pembersihan proses antar tool call. Bind 127.0.0.1 saja.
"""
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
WORKLOG = os.path.join(PROJECT, "worklog.md")

# label -> path absolut (label dipakai di URL /file/<label>/... )
ROOTS = [
    ("download", os.path.join(PROJECT, "download")),
    ("archive", os.path.join(PROJECT, "archive")),
]
ROOTMAP = dict(ROOTS)
SKILL_DIR = os.path.join(PROJECT, "skills", "stellar-trail")
HEAL_MARKER = os.path.join(ZDIR, ".skill-heal.last")
WATCHER_PID = os.path.join(ZDIR, "watcher.pid")

BIND = "127.0.0.1"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 3000
STARTED = time.time()

MAX_DEPTH = 4  # batas kedalaman walk per root


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
    """Parse section 'Task ID: n / Task: ...' dari worklog.md, lalu petakan
    tiap file ke task TERAKHIR yang menyebut nama filenya."""
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
    for t in tasks:  # urut kronologis; task belakangan menimpa -> menang
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
    for t in tasks:  # section ganda dgn Task ID sama -> ambil yang terakhir
        dedup[t["id"]] = {"id": t["id"], "title": t["title"], "count": t["count"]}
    out = list(dedup.values())
    return out


def skill_info():
    """Blok guardian: versi stellar-trail terinstal, heal terakhir, watcher.
    Semua pembacaan best-effort — absennya skill bukan error explorer."""
    info = {"installed": os.path.isdir(SKILL_DIR)}
    if not info["installed"]:
        return info
    try:
        with open(os.path.join(SKILL_DIR, "_meta.json"), encoding="utf-8") as f:
            info["version"] = json.load(f).get("version")
    except (OSError, ValueError):
        info["version"] = None
    if info.get("version") is None:
        # v1.2 (v3.6.3, Task 62): instalasi non-registry (npx/git) tidak
        # membawa _meta.json — guardian dulu melaporkan version:null padahal
        # assets/integrity.version ada di tree (laporan konsumer T46 F6).
        try:
            with open(os.path.join(SKILL_DIR, "assets", "integrity.version"), encoding="utf-8") as f:
                info["version"] = f.read().strip() or None
        except OSError:
            pass
    try:
        info["heal_last"] = int(os.stat(HEAL_MARKER).st_mtime)
    except OSError:
        info["heal_last"] = None
    alive = False
    try:
        with open(WATCHER_PID, encoding="utf-8") as f:
            os.kill(int(f.read().strip()), 0)
        alive = True
    except (OSError, ValueError):
        pass
    info["watcher_alive"] = alive
    return info


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
        "skill": skill_info(),
    }


def safe_path(label: str, rel: str):
    """Kembalikan path absolut hanya bila rel berada di dalam root label."""
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
                self._send(500, "UI index.html tidak ditemukan")
            return
        if path == "/api/files":
            self._send(200, json.dumps(build_api(), ensure_ascii=False),
                       "application/json; charset=utf-8")
            return
        if path.startswith("/file/"):
            rest = path[len("/file/"):]
            label, _, rel = rest.partition("/")
            fp = safe_path(label, rel)
            if not fp:
                self._send(403, "Akses file ditolak (di luar root yang diizinkan)")
                return
            size = os.path.getsize(fp)
            name = os.path.basename(fp)
            # ?dl=1 -> attachment (unduhan paksa); default inline (pratinjau)
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
    print("[explorer] START pid %s bind %s:%d ui %s"
          % (os.getpid(), BIND, PORT, UI), flush=True)
    try:
        ThreadingHTTPServer((BIND, PORT), Handler).serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        try:
            os.remove(PIDFILE)
        except OSError:
            pass
