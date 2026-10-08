#!/usr/bin/env bash
# ============================================================================
# explorer.sh — LAUNCHER v1.5 of the Task Files Explorer (functional
# replacement for the "All files in task" popup).
#
# Chain: platform preview -> ingress :81 -> 127.0.0.1:3000 -> explorer.py
#
# PORT 3000 PRIORITY: when a package.json exists (Next.js project), Next.js
# owns port 3000 and the explorer STANDS DOWN (guard below) — the explorer
# must never break the platform's web project.
#
# Invoked from three paths (same as the watcher):
#   1. Container boot -> dev.sh (/start.sh hook)
#   2. watcher.sh -> auto-heal every 30 seconds when healthz fails
#   3. Manual
#
# WHAT THE LAUNCHER DOES:
#   - AUTO-DEPLOY from the install tree: a launcher invoked directly at
#     skills/stellar-trail/assets/explorer/ detects the layout, copies
#     itself + explorer.py + the UI to <root>/.zscripts/, then re-execs from
#     there (PID/log always in .zscripts/, the install tree stays drift-free;
#     anti-loop via env guard + layout detection).
#   - sync_fresh: the .zscripts/ deployment copy is not the source of truth —
#     the skill canonical is (download/stellar-trail/assets/explorer/).
#     --ensure refreshes explorer.py + explorer-ui/index.html on md5 drift
#     and restarts the server when explorer.py changed (the UI is read
#     per-request — a copy suffices). Alive-but-stale is repaired, not just
#     dead-then-started.
#   - PROCESS-FRESHNESS RESTART (content-exact): explorer.py writes
#     .zscripts/explorer.code-stamp (md5 of its own source) at startup;
#     --ensure compares md5(deployed explorer.py) vs the stamp and restarts
#     a live server predating the deployed code — no mtime ambiguity, a
#     missing stamp = a pre-stamp server = stale by definition.
#   - Hardened stop (kill_wait: TERM, poll <=5s, then KILL — a server that
#     ignores TERM cannot pass the alive check on its dying socket) with a
#     pid-identity guard (a RECYCLED pid in the pidfile is never killed
#     blindly: /proc/<pid>/cmdline must match).
#   - Heal: alive but pidfile missing (externally deleted — the server writes
#     pidfile+stamp BEFORE serving) -> restart restores the anchor.
#   - Start health verdict gets one +2s retry for slow cold starts.
#   - Deploy-time activation: bootstrap-sandbox.sh calls --ensure after
#     deploying the assets — dev.sh covers BOOT, the watcher covers DEATH,
#     bootstrap covers DEPLOY-TIME. One path per moment.
#
# COMMANDS:
#   bash explorer.sh --ensure   # idempotent: refresh + start when needed
#   bash explorer.sh --status   # health + freshness check + log tail
#   bash explorer.sh --stop     # stop the explorer
# ============================================================================
# Self-locating: ZDIR = this script's directory, PROJECT = its parent —
# works in any sandbox without hardcoding; STELLAR_PROJECT is exported for
# explorer.py.
# NOTE: when "ZDIR's parent" is not the project root (the install-tree case
# above), auto_deploy below takes over BEFORE the variables are used.
ZDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(dirname "$ZDIR")"
export STELLAR_PROJECT="$PROJECT"
PY="$ZDIR/explorer.py"
UI="$ZDIR/explorer-ui/index.html"
LOG="$ZDIR/explorer.log"
PIDFILE="$ZDIR/explorer.pid"
STAMP="$ZDIR/explorer.code-stamp"   # v1.5: md5 of the RUNNING server's source
PORT=3000
HEALTH="http://127.0.0.1:${PORT}/healthz"
CANON_EXP="$PROJECT/download/stellar-trail/assets/explorer"

# --- v1.3 : AUTO-DEPLOY from the install tree -----------------------
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
kill_wait() {  # v1.5: $1 = pgrep pattern — TERM, wait <=5s for death, then KILL
    pkill -f "$1" 2>/dev/null
    local i
    for i in 1 2 3 4 5; do
        pgrep -f "$1" >/dev/null 2>&1 || return 0
        sleep 1
    done
    echo "[$(date '+%F %T')] kill_wait: SIGTERM not enough -> SIGKILL ($1)" >> "$LOG"
    pkill -9 -f "$1" 2>/dev/null
    sleep 1
    return 0
}

process_fresh() {  # v1.5: 0 = fresh · 1 = stale · 2 = no process. Content-exact:
    # the running server runs the deployed code IFF stamp md5 == md5 of the
    # deployed explorer.py. No stamp = pre-v1.5 server (never wrote one) =
    # stale -> one-time migration restart.
    pgrep -f "$PY" >/dev/null 2>&1 || return 2
    [ -f "$STAMP" ] || return 1
    [ "$(md5sum "$PY" 2>/dev/null | cut -d' ' -f1)" = "$(cut -d' ' -f1 "$STAMP" 2>/dev/null)" ]
}

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
        kill_wait "$dep/explorer.py"   # v1.5: TERM + wait + KILL fallback
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
        kill_wait "$PY"   # v1.5: TERM + wait + KILL fallback
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
    # v1.5: process/code freshness — content-exact via the code stamp
    # (restart happens on the next --ensure)
    if [ -f "$PY" ]; then
        case "$(process_fresh; echo $?)" in
            0) echo "process : pid $(cat "$PIDFILE" 2>/dev/null || echo '?') code current (stamp ok)" ;;
            1) echo "process : pid $(cat "$PIDFILE" 2>/dev/null || echo '?') runs PRE-UPDATE code — restart pending (bash explorer.sh --ensure)" ;;
            2) echo "process : (not running)" ;;
        esac
    fi
    echo "--- explorer.log (last 10) ---"
    tail -10 "$LOG" 2>/dev/null || echo "(empty)"
    exit 0
    ;;
--stop)
    if [ -f "$PIDFILE" ]; then
        pid="$(cat "$PIDFILE" 2>/dev/null)"
        # v1.5 pid-identity guard: a RECYCLED pid is never killed blindly —
        # only when /proc/<pid>/cmdline really is the explorer; the pattern
        # pkill below catches the true server either way
        if [ -n "$pid" ] && grep -aq "explorer.py" "/proc/$pid/cmdline" 2>/dev/null; then
            kill "$pid" 2>/dev/null \
                && echo "[explorer] stopped (pid $pid)"
        elif [ -n "$pid" ]; then
            echo "[explorer] pidfile pid $pid is not the explorer (recycled?) — not killed"
        fi
        rm -f "$PIDFILE"
    fi
    pkill -f "$PY" 2>/dev/null
    exit 0
    ;;
--ensure | *)
    sync_fresh   # v1.2: freshness first — alive-but-stale also gets repaired
    # v1.5: process freshness — content-exact (see process_fresh). A live
    # server predating the deployed code restarts so new endpoints go live
    # on EVERY deploy path (bootstrap activation, boot, watcher, manual).
    case "$(process_fresh; echo $?)" in
        0) ;;
        1)  echo "[$(date '+%F %T')] process-fresh: running server predates the deployed code (stamp mismatch/missing) -> restart" >> "$LOG"
            kill_wait "$PY" ;;
    esac
    # v1.5 heal: alive but pidfile missing = the freshness anchor was deleted
    # externally (the server writes pidfile+stamp BEFORE serving) -> restart
    # restores the invariant
    if alive && [ ! -f "$PIDFILE" ]; then
        echo "[$(date '+%F %T')] heal: server alive but pidfile missing -> restart" >> "$LOG"
        kill_wait "$PY"
    fi
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
        sleep 2   # v1.5: one retry — a cold FS can be slow to bind
        if alive; then
            echo "[explorer] ALIVE on :$PORT (pid $(cat "$PIDFILE" 2>/dev/null), slow start)"
        else
            echo "[explorer] WARN: not healthy after start — check $LOG" >&2
        fi
    fi
    exit 0
    ;;
esac
