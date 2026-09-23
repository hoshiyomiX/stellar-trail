#!/usr/bin/env bash
# ============================================================================
# explorer.sh — LAUNCHER Task Files Explorer (pengganti fungsional popup
# "All files in task").
#
# Rantai: preview platform -> ingress :81 -> 127.0.0.1:3000 -> explorer.py
#
# PRIORITAS PORT 3000: bila ada package.json (proyek Next.js), Next.js yang
# berhak atas port 3000 dan explorer BERDIRI DOWN (guard di bawah) — explorer
# tidak boleh merusak proyek web platform.
#
# Dipanggil dari tiga jalur (sama seperti watcher):
#   1. Boot container -> dev.sh v1.2 (hook /start.sh)
#   2. watcher.sh v1.1 -> auto-heal tiap 30 detik bila healthz gagal
#   3. Manual
#
# v1.2 (Task 43, 2026-09-22): FRESHNESS SYNC — salinan deployment .zscripts/
#   bukan sumber kebenaran; kanonik skill-lah (download/stellar-trail/assets/
#   explorer/). --ensure kini menyegarkan explorer.py + explorer-ui/index.html
#   bila md5 drift (mis. restore repo.tar basi, atau rilis UI baru), lalu
#   restart server bila explorer.py berubah (UI dibaca per-request — cukup
#   copy). Hidup-tapi-basi kini ikut diperbaiki, bukan hanya mati-dihidupkan.
#
# PERINTAH:
#   bash explorer.sh --ensure   # idempoten: segarkan + hidupkan bila perlu
#   bash explorer.sh --status   # cek kesehatan + kesegaran + log tail
#   bash explorer.sh --stop     # matikan explorer
# ============================================================================
ZDIR="$PROJECT/.zscripts"
PROJECT="${STELLAR_PROJECT:-/home/z/my-project}"
PY="$ZDIR/explorer.py"
UI="$ZDIR/explorer-ui/index.html"
LOG="$ZDIR/explorer.log"
PIDFILE="$ZDIR/explorer.pid"
PORT=3000
HEALTH="http://127.0.0.1:${PORT}/healthz"
CANON_EXP="$PROJECT/download/stellar-trail/assets/explorer"

alive() { curl -fsS -m 2 "$HEALTH" >/dev/null 2>&1; }

sync_fresh() {  # v1.2: kesegaran deployment vs kanonik; return 1 bila .py berubah
    [ -d "$CANON_EXP" ] || return 0
    local rel changed_py=0
    for rel in explorer.py explorer-ui/index.html; do
        if [ -f "$CANON_EXP/$rel" ] && ! cmp -s "$ZDIR/$rel" "$CANON_EXP/$rel" 2>/dev/null; then
            mkdir -p "$ZDIR/$(dirname "$rel")"
            cp -p "$CANON_EXP/$rel" "$ZDIR/$rel"
            echo "[$(date '+%F %T')] sync-fresh: $rel disegarkan dari kanonik (drift)" >> "$LOG"
            case "$rel" in explorer.py) changed_py=1;; esac
        fi
    done
    if [ "$changed_py" = "1" ] && pgrep -f "$PY" >/dev/null 2>&1; then
        echo "[$(date '+%F %T')] sync-fresh: explorer.py berubah -> restart server" >> "$LOG"
        pkill -f "$PY" 2>/dev/null
        sleep 1
    fi
    return 0
}

case "$1" in
--status)
    echo "=== TASK FILES EXPLORER @ :$PORT ==="
    if alive; then
        echo "kesehatan: OK  ($HEALTH)"
        echo "api      : http://127.0.0.1:$PORT/api/files"
    else
        echo "kesehatan: MATI"
    fi
    if [ -d "$CANON_EXP" ]; then
        FR_PY=$(cmp -s "$ZDIR/explorer.py" "$CANON_EXP/explorer.py" && echo ok || echo DRIFT)
        FR_UI=$(cmp -s "$ZDIR/explorer-ui/index.html" "$CANON_EXP/explorer-ui/index.html" && echo ok || echo DRIFT)
        echo "fresh    : server=$FR_PY ui=$FR_UI (vs kanonik)"
    fi
    echo "pid file : $(cat "$PIDFILE" 2>/dev/null || echo '-')"
    echo "--- explorer.log (10 terakhir) ---"
    tail -10 "$LOG" 2>/dev/null || echo "(kosong)"
    exit 0
    ;;
--stop)
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null \
            && echo "[explorer] dihentikan (pid $(cat "$PIDFILE"))"
        rm -f "$PIDFILE"
    fi
    pkill -f "$PY" 2>/dev/null
    exit 0
    ;;
--ensure | *)
    sync_fresh   # v1.2: kesegaran dulu — hidup-tapi-basi ikut diperbaiki
    if alive; then exit 0; fi
    if [ -f "$PROJECT/package.json" ]; then
        echo "[explorer] package.json ada -> Next.js pemilik :$PORT, explorer stand-down" >&2
        exit 0
    fi
    if [ ! -f "$PY" ] || [ ! -f "$UI" ]; then
        echo "[explorer] file server/UI tidak lengkap ($PY / $UI)" >&2
        exit 1
    fi
    # port dipakai proses lain yang bukan explorer? jangan direbut
    if (exec 3<>/dev/tcp/127.0.0.1/$PORT) 2>/dev/null; then
        exec 3>&- 3<&-
        echo "[explorer] port $PORT dipakai proses lain (bukan explorer) — stand down" >&2
        exit 1
    fi
    echo "[$(date '+%F %T')] explorer.sh start (double-fork orphan)" >> "$LOG"
    ( setsid python3 "$PY" "$PORT" >> "$LOG" 2>&1 & )
    sleep 1
    if alive; then
        echo "[explorer] HIDUP di :$PORT (pid $(cat "$PIDFILE" 2>/dev/null))"
    else
        echo "[explorer] WARN: belum sehat setelah start — cek $LOG" >&2
    fi
    exit 0
    ;;
esac
