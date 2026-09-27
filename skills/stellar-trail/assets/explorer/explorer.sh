#!/usr/bin/env bash
# ============================================================================
# explorer.sh — LAUNCHER of the Task Files Explorer (functional replacement
# for the "All files in task" popup).
#
# Chain: platform preview -> ingress :81 -> 127.0.0.1:3000 -> explorer.py
#
# PORT 3000 PRIORITY: when a package.json exists (Next.js project), Next.js
# owns port 3000 and the explorer STANDS DOWN (guard below) — the explorer
# must never break the platform's web project.
#
# Invoked from three paths (same as the watcher):
#   1. Container boot -> dev.sh v1.2 (/start.sh hook)
#   2. watcher.sh (v2.0, shipped in the package since v3.6.3) -> auto-heal every 30 seconds when healthz fails
#   3. Manual
#
# v1.2 (Task 43, 2026-09-22): FRESHNESS SYNC — the .zscripts/ deployment copy
#   is not the source of truth; the skill canonical is
#   (download/stellar-trail/assets/explorer/). --ensure now refreshes
#   explorer.py + explorer-ui/index.html on md5 drift (e.g. a stale repo.tar
#   restore, or a new UI release), then restarts the server when explorer.py
#   changed (the UI is read per-request — a copy suffices). Alive-but-stale
#   is now also repaired, not just dead-then-started.
#
# v1.3 (Task 60, 2026-09-25): AUTO-DEPLOY — a launcher invoked directly from
#   the INSTALL TREE (skills/stellar-trail/assets/explorer/) now detects its
#   layout, copies itself to <root>/.zscripts/, then re-execs from there.
#   Before: PROJECT fell to .../assets -> explorer.py open(PIDFILE) on
#   .../assets/.zscripts/explorer.pid (dir never created) ->
#   FileNotFoundError -> server died before bind (HTTP 000), plus
#   explorer.log written inside the install tree (extra drift).
#   (Consumer report from another sandbox, Installation & Explorer Report
#   v3.6.1.)
#
# COMMANDS:
#   bash explorer.sh --ensure   # idempotent: refresh + start when needed
#   bash explorer.sh --status   # health + freshness check + log tail
#   bash explorer.sh --stop     # stop the explorer
# ============================================================================
# Self-locating (v3.6.1): ZDIR = this script's directory, PROJECT = its
# parent — works in any sandbox without hardcoding; STELLAR_PROJECT is
# exported for explorer.py. (Task 56 fix: previously ZDIR was computed
# BEFORE PROJECT was defined → "/.zscripts" — ordering bug in the package
# copy.)
# v1.3 NOTE: when "ZDIR's parent" is not the project root (the install-tree
# case above), auto_deploy() below takes over BEFORE the variables are used.
ZDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(dirname "$ZDIR")"
export STELLAR_PROJECT="$PROJECT"
PY="$ZDIR/explorer.py"
UI="$ZDIR/explorer-ui/index.html"
LOG="$ZDIR/explorer.log"
PIDFILE="$ZDIR/explorer.pid"
PORT=3000
HEALTH="http://127.0.0.1:${PORT}/healthz"
CANON_EXP="$PROJECT/download/stellar-trail/assets/explorer"

# --- v1.3 (Task 60): AUTO-DEPLOY from the install tree -----------------------
# Runs BEFORE the variables above are used for any side effect.
# Layout */assets/explorer = launcher living in the install tree (not
# .zscripts): the real project root is searched upward (the ancestor
# containing skills/ — supports both flat skills/stellar-trail/... and
# owner-scoped skills/@owner/stellar-trail/...), all assets are copied to
# <root>/.zscripts/ (idempotent: only when different), then re-exec happens
# from there — so PID/log are always written in .zscripts/ and the INSTALL
# TREE STAYS PRISTINE (zero drift).
# Anti-loop: only the assets layout triggers it (re-exec target = .zscripts,
# a different layout) + env guard STELLAR_EXPLORER_AUTODEPLOYED.
auto_deploy() {
    case "$ZDIR" in */assets/explorer) ;; *) return 1 ;; esac
    if [ -n "${STELLAR_EXPLORER_AUTODEPLOYED:-}" ]; then
        echo "[explorer] AUTO-DEPLOY: loop detected (still assets layout after re-exec) — stopping; copy assets/explorer/ to <project>/.zscripts/ manually" >&2
        exit 1
    fi
    local p="$ZDIR" root=""
    while [ "$p" != "/" ]; do
        p="$(dirname "$p")"
        [ -d "$p/skills" ] && { root="$p"; break; }
    done
    if [ -z "$root" ]; then
        echo "[explorer] AUTO-DEPLOY: project root not found (no ancestor contains skills/) — copy assets/explorer/ to <project>/.zscripts/ manually, then run it from there" >&2
        exit 1
    fi
    local dep="$root/.zscripts" f changed=0
    mkdir -p "$dep/explorer-ui" || { echo "[explorer] AUTO-DEPLOY: mkdir failed for $dep" >&2; exit 1; }
    for f in explorer.sh explorer.py explorer-ui/index.html; do
        if ! cmp -s "$ZDIR/$f" "$dep/$f" 2>/dev/null; then
            cp -p "$ZDIR/$f" "$dep/$f" || { echo "[explorer] AUTO-DEPLOY: copy failed for $f" >&2; exit 1; }
            changed=1
        fi
    done
    # server alive from an old copy? kill it when explorer.py was just
    # refreshed so --ensure's re-exec restarts it; other args kill nothing
    # (--status/--stop stay read-only toward the process)
    if [ "$changed" = 1 ] && [ "${1:---ensure}" = "--ensure" ] \
        && pgrep -f "$dep/explorer.py" >/dev/null 2>&1; then
        pkill -f "$dep/explorer.py" 2>/dev/null
        sleep 1
    fi
    echo "[explorer] AUTO-DEPLOY: launched from the install tree -> deploy $dep ($([ "$changed" = 1 ] && echo refreshed || echo already-in-sync)), re-exec from there"
    export STELLAR_EXPLORER_AUTODEPLOYED=1
    exec bash "$dep/explorer.sh" "$@"
}
auto_deploy "$@"

alive() { curl -fsS -m 2 "$HEALTH" >/dev/null 2>&1; }

sync_fresh() {  # v1.2: deployment freshness vs canonical; restarts the server when the .py changed
    [ -d "$CANON_EXP" ] || return 0
    local rel changed_py=0
    for rel in explorer.py explorer-ui/index.html; do
        if [ -f "$CANON_EXP/$rel" ] && ! cmp -s "$ZDIR/$rel" "$CANON_EXP/$rel" 2>/dev/null; then
            mkdir -p "$ZDIR/$(dirname "$rel")"
            cp -p "$CANON_EXP/$rel" "$ZDIR/$rel"
            echo "[$(date '+%F %T')] sync-fresh: $rel refreshed from canonical (drift)" >> "$LOG"
            case "$rel" in explorer.py) changed_py=1;; esac
        fi
    done
    if [ "$changed_py" = "1" ] && pgrep -f "$PY" >/dev/null 2>&1; then
        echo "[$(date '+%F %T')] sync-fresh: explorer.py changed -> server restart" >> "$LOG"
        pkill -f "$PY" 2>/dev/null
        sleep 1
    fi
    return 0
}

case "$1" in
--status)
    echo "=== TASK FILES EXPLORER @ :$PORT ==="
    if alive; then
        echo "health   : OK  ($HEALTH)"
        echo "api      : http://127.0.0.1:$PORT/api/files"
    else
        echo "health   : DOWN"
    fi
    if [ -d "$CANON_EXP" ]; then
        FR_PY=$(cmp -s "$ZDIR/explorer.py" "$CANON_EXP/explorer.py" && echo ok || echo DRIFT)
        FR_UI=$(cmp -s "$ZDIR/explorer-ui/index.html" "$CANON_EXP/explorer-ui/index.html" && echo ok || echo DRIFT)
        echo "fresh    : server=$FR_PY ui=$FR_UI (vs canonical)"
    fi
    echo "pid file : $(cat "$PIDFILE" 2>/dev/null || echo '-')"
    echo "--- explorer.log (last 10) ---"
    tail -10 "$LOG" 2>/dev/null || echo "(empty)"
    exit 0
    ;;
--stop)
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null \
            && echo "[explorer] stopped (pid $(cat "$PIDFILE"))"
        rm -f "$PIDFILE"
    fi
    pkill -f "$PY" 2>/dev/null
    exit 0
    ;;
--ensure | *)
    sync_fresh   # v1.2: freshness first — alive-but-stale also gets repaired
    if alive; then exit 0; fi
    if [ -f "$PROJECT/package.json" ]; then
        echo "[explorer] package.json present -> Next.js owns :$PORT, explorer stand-down" >&2
        exit 0
    fi
    if [ ! -f "$PY" ] || [ ! -f "$UI" ]; then
        echo "[explorer] server/UI files incomplete ($PY / $UI)" >&2
        exit 1
    fi
    # port held by another process that is not the explorer? do not fight for it
    if (exec 3<>/dev/tcp/127.0.0.1/$PORT) 2>/dev/null; then
        exec 3>&- 3<&-
        echo "[explorer] port $PORT held by another process (not the explorer) — stand down" >&2
        exit 1
    fi
    echo "[$(date '+%F %T')] explorer.sh start (double-fork orphan)" >> "$LOG"
    ( setsid python3 "$PY" "$PORT" >> "$LOG" 2>&1 & )
    sleep 1
    if alive; then
        echo "[explorer] ALIVE on :$PORT (pid $(cat "$PIDFILE" 2>/dev/null))"
    else
        echo "[explorer] WARN: not healthy after start — check $LOG" >&2
    fi
    exit 0
    ;;
esac
