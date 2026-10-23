#!/usr/bin/env bash
# ============================================================================
# watcher.sh — runtime watchdog daemon for the stellar-trail persistence layer
# stellar-trail · watcher v2.3 (runtime watchdog, verify-only)
#
# WHAT THIS DAEMON DOES (one loop every 30 seconds, WATCHER_INTERVAL to tune):
#   1. download/ change trigger — when the top level of download/ changes,
#      run .zscripts/dev.sh (optional; skipped silently when absent).
#   2. Task Files Explorer health — probe http://127.0.0.1:3000/healthz and
#      restart the explorer via explorer.sh --ensure when it is down
#      (skipped when the project has a package.json: a Next.js dev server
#      owns the preview URL in that case).
#   2b. Explorer deployment-gap notice — when the skill tree ships the
#       explorer payload but .zscripts/explorer.sh is not deployed (fresh
#       install before bootstrap, or a deliberate opt-out), the health guard
#       above is correctly silent — nothing is deployed to revive. This duty
#       closes that observability gap (consumer report BUG #3):
#       ONE notice per gap episode in this log plus ONE worklog line naming
#       the activation command; state-gated (.explorer-gap.noticed), the
#       marker is removed when the gap closes. NOTICE, not alarm — the
#       watcher never installs anything.
#   3. Release-file guard — download/stellar-trail/skill-card.md and
#      assets/integrity.sha256 are release files that live outside the
#      checksum manifest (the manifest cannot hash itself, and the skill
#      card carries the version the manifest generator ran under). When one
#      goes missing or stale, restore it from the live installation when
#      that installation is healthy and on the same version. This is a
#      local cache-to-cache copy between two copies of the SAME release —
#      it never fetches anything. When no healthy local copy exists, raise
#      an alarm telling the user to re-run the install command.
#   4. Installation integrity check (every ~10 minutes) — verify each
#      installed copy against its checksum manifest. On failure: alarm and
#      the remediation message. There is NO automatic repair from alternate
#      sources — the single installation flow is the only fix, by design.
#   5. Platform archive refresh (every ~15 minutes) — repo-snapshot.sh
#      --apply-auto when the snapshot module is installed (own debounce).
#   6. Compliance sentinel (every ~2 minutes) — when the worklog is being
#      actively written but memory/SESSION-STATE.md has not been rewritten
#      for over 30 minutes, append a one-line alarm to the worklog (debounced
#      to one alarm per hour). BLIND SPOT (field-proven 2026-10-21): this
#      needs the worklog to GROW — sessions that work without writing a
#      single protocol line never trigger it. Duty 6b closes that hole.
#   6b. Silent-work sentinel + ALERT surface (every ~2 minutes) — work
#      artifacts (workspace/ scripts/ download/ upload/, minus the
#      watcher-guarded canonical copy) whose mtimes run ahead of the last
#      checkpoint: WORK-SILENCE (work without the protocol, >30 min) and
#      EVIDENCE-PENDING (user field evidence unprocessed by any logged
#      session, >2 h). Alarms append to the worklog (1 h debounce per class)
#      AND refresh download/ALERT-ACTIVE.md — a surface in the user-visible
#      file list, because worklog/watcher.log are only read when the
#      protocol already runs (the 2026-10-21 incident ran its full course
#      with zero machine alarms; the USER caught it). The ALERT file is
#      excluded from the duty-1 hash and removed automatically when every
#      class clears. Thresholds env-tunable: STELLAR_SILENCE_WORK_SECS,
#      STELLAR_SILENCE_EVIDENCE_SECS.
#   7. Origin release probe (every ~24 hours, epoch-state-gated so container
#      reboots do not reset the clock) — compare the origin's latest release
#      tag with the live installation. A NEWER origin tag appends a one-line
#      alarm to the worklog (once per unseen version, remediation = the
#      install command). ALARM-ONLY: the watcher never installs — the single
#      installation flow is the only installer, by design. Run it on demand
#      with --probe-origin.
#   8. Periodic compliance audit (every ~6 hours, epoch-state-gated like duty
#      7) — run scripts/audit-compliance.sh and log the verdict to
#      watcher.log as greppable history (a FAIL also appends a one-line
#      worklog alarm). The audit previously ran only at major checkpoints /
#      manual calls — between them, compliance drift had no scheduled
#      detector (field-verified 2026-10-21). Env-tunable:
#      STELLAR_AUDIT_INTERVAL. Verify-only — the audit never repairs.
#
# SURVIVAL MECHANICS (verified empirically on this platform):
#   every tool call spawns a fresh shell that the platform kills — including
#   its whole child process tree — when the call finishes. A double-forked
#   orphan (parent PID 1, own session via setsid) survives that cleanup, so
#   the daemon stays alive across tool calls and boots.
#
# Usage:
#   bash watcher.sh --ensure        start if not running (idempotent)
#   bash watcher.sh --status        show daemon status
#   bash watcher.sh --stop          stop and set the stop-flag
#   bash watcher.sh --force-start   start even when the stop-flag is present
#   bash watcher.sh --probe-origin  one-shot origin release probe (duty 7 on
#                                   demand — prints the verdict; alarms the
#                                   worklog when a newer release is found)
#
# The daemon is started from three redundant paths: container boot via
# dev.sh (step 4), the deploy/session path via
# bootstrap-sandbox.sh --ensure (step 11b — the daemon can die silently at
# container lifecycle events that no boot follows), and manual runs.
# ============================================================================

# --- SELF-LOCATE --------------------------------------------------------------
# Priority: STELLAR_PROJECT environment variable > the .zscripts directory
# this file lives in > walk-up from this file's location (markers: skills/,
# download/, worklog.md, package.json) > default /home/z/my-project.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${STELLAR_PROJECT:-}"
if [ -z "$PROJECT" ]; then
    if [ "$(basename "$SELF_DIR")" = ".zscripts" ]; then
        PROJECT="$(dirname "$SELF_DIR")"
    else
        _d="$SELF_DIR"
        for _ in 1 2 3 4 5 6; do
            _d="$(dirname "$_d")"
            if [ -d "$_d/skills" ] || [ -d "$_d/download" ] \
               || [ -f "$_d/worklog.md" ] || [ -f "$_d/package.json" ]; then
                PROJECT="$_d"; break
            fi
            [ "$_d" = "/" ] && break
        done
    fi
fi
PROJECT="${PROJECT:-/home/z/my-project}"

ZDIR="$PROJECT/.zscripts"
DOWNLOAD="$PROJECT/download"
PIDFILE="$ZDIR/watcher.pid"
STOPFLAG="$ZDIR/watcher.stop"
LOG="$ZDIR/watcher.log"
DEVSH="$ZDIR/dev.sh"
INTERVAL="${WATCHER_INTERVAL:-30}"
# Remediation message printed in every integrity alarm — the single flow.
INSTALL_HINT="npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw -y"
# Origin release probe (duty 7) — alarm-only; tunables for tests and forks
ORIGIN_URL="${STELLAR_WATCHER_ORIGIN:-https://github.com/hoshiyomiX/stellar-trail.git}"
ORIGIN_INTERVAL="${STELLAR_WATCHER_ORIGIN_INTERVAL:-86400}"
ORIGIN_STATE="$ZDIR/.origin-probe.last"
# Duty 6b thresholds (incident 2026-10-21 classes) + duty 8 cadence — tunable
# for tests and forks; defaults: 30 min work-silence / 2 h evidence-pending /
# 6 h periodic audit
SILENCE_WORK_SECS="${STELLAR_SILENCE_WORK_SECS:-1800}"
SILENCE_EVIDENCE_SECS="${STELLAR_SILENCE_EVIDENCE_SECS:-7200}"
AUDIT_INTERVAL="${STELLAR_AUDIT_INTERVAL:-21600}"
mkdir -p "$ZDIR" 2>/dev/null || true

wlog() {
    echo "[$(date '+%F %T')] $*" >> "$LOG"
    # keep the log under 50 KB — retain the last 100 lines
    if [ -s "$LOG" ] && [ "$(stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt 51200 ]; then
        tail -100 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
    fi
}

alive() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
}

# version_lt <a> <b> — true when a < b on loose x.y.z version patterns.
# Controlled copy (change both together; siblings: scripts/update-skill.sh and
# the dev.sh boot hook) — the standalone-helper doctrine forbids a shared
# library here.
version_lt() {
    local a1=0 a2=0 a3=0 b1=0 b2=0 b3=0
    IFS=. read -r a1 a2 a3 <<< "${1:-0}"
    IFS=. read -r b1 b2 b3 <<< "${2:-0}"
    [ "${a1:-0}" -lt "${b1:-0}" ] && return 0
    [ "${a1:-0}" -gt "${b1:-0}" ] && return 1
    [ "${a2:-0}" -lt "${b2:-0}" ] && return 0
    [ "${a2:-0}" -gt "${b2:-0}" ] && return 1
    [ "${a3:-0}" -lt "${b3:-0}" ]
}

# ---------------------------------------------------------------------------
# MODES --stop / --status
# ---------------------------------------------------------------------------
case "$1" in
    --probe-origin)
        # One-shot origin release probe (duty 7 on demand — the daemon loop
        # invokes this same mode: single source of truth). Prints the verdict;
        # appends a one-line worklog alarm when the origin carries a NEWER
        # release tag (once per unseen version). NEVER installs anything.
        LIVE_VER=""
        for LV in "$PROJECT/skills/stellar-trail" "$PROJECT"/skills/@*/stellar-trail; do
            if [ -f "$LV/assets/integrity.version" ]; then
                LIVE_VER="$(tr -d '[:space:]' < "$LV/assets/integrity.version")"
                break
            fi
        done
        if [ -z "$LIVE_VER" ]; then
            echo "[watcher] probe-origin: no live installation found — nothing to compare"
            exit 0
        fi
        if ! command -v git >/dev/null 2>&1; then
            echo "[watcher] probe-origin: git unavailable — skipped (alarm-only probe, never blocks)"
            exit 0
        fi
        ORIGIN_VER="$(timeout 25 git ls-remote --tags --refs --sort=-v:refname "$ORIGIN_URL" 'v[0-9]*' 2>/dev/null \
            | head -1 | awk -F/ '{print $NF}' | sed 's/^v//' | tr -d '[:space:]')"
        O_NOW="$(date +%s)"
        O_ALARMED="-"
        [ -f "$ORIGIN_STATE" ] && O_ALARMED="$(awk '{print $2}' "$ORIGIN_STATE" 2>/dev/null)"
        [ -z "$O_ALARMED" ] && O_ALARMED="-"
        if [ -z "$ORIGIN_VER" ]; then
            # offline-tolerant: retry in ~1h instead of the full interval so a
            # network blip cannot blind the probe for 24h
            echo "$((O_NOW - ORIGIN_INTERVAL + 3600)) $O_ALARMED" > "$ORIGIN_STATE" 2>/dev/null
            echo "[watcher] probe-origin: origin unreachable — will retry in ~1h (alarm-only probe, never blocks)"
            exit 0
        fi
        if [ "$ORIGIN_VER" = "$LIVE_VER" ]; then
            echo "$O_NOW $O_ALARMED" > "$ORIGIN_STATE" 2>/dev/null
            echo "[watcher] probe-origin: origin v$ORIGIN_VER == live v$LIVE_VER — up to date"
        elif version_lt "$ORIGIN_VER" "$LIVE_VER"; then
            echo "$O_NOW $O_ALARMED" > "$ORIGIN_STATE" 2>/dev/null
            echo "[watcher] probe-origin: origin v$ORIGIN_VER < live v$LIVE_VER (dev install ahead) — no action"
        elif [ "$O_ALARMED" = "$ORIGIN_VER" ]; then
            echo "$O_NOW $O_ALARMED" > "$ORIGIN_STATE" 2>/dev/null
            echo "[watcher] probe-origin: origin v$ORIGIN_VER > live v$LIVE_VER — alarm already sent for this version, not repeating"
        else
            echo "$O_NOW $ORIGIN_VER" > "$ORIGIN_STATE" 2>/dev/null
            printf "\n> ORIGIN-RELEASE-ALARM %s: the origin carries a NEWER release v%s (live installation: v%s). At the next session start run: bash skills/stellar-trail/scripts/update-skill.sh --ensure — or manually: %s. The watcher NEVER installs (alarm-only; the single install flow is the only installer).\n" \
                "$(date '+%F %T')" "$ORIGIN_VER" "$LIVE_VER" "$INSTALL_HINT" >> "$PROJECT/worklog.md" 2>/dev/null
            echo "[watcher] probe-origin: ALARM — newer release v$ORIGIN_VER at the origin (live v$LIVE_VER); one-line alarm appended to the worklog"
        fi
        exit 0
        ;;
    --stop)
        if alive; then
            kill "$(cat "$PIDFILE")" 2>/dev/null
            wlog "watcher stopped manually (--stop)"
            echo "[watcher] stopped (pid $(cat "$PIDFILE"))"
        fi
        rm -f "$PIDFILE"
        touch "$STOPFLAG"
        echo "[watcher] stop-flag set: $STOPFLAG (delete that file to allow starting again)"
        exit 0
        ;;
    --status)
        echo "=== WATCHER STATUS (v2.3) ==="
        echo "project : $PROJECT"
        if alive; then
            echo "daemon  : RUNNING (pid $(cat "$PIDFILE"))"
            ps -o pid,ppid,etime,cmd -p "$(cat "$PIDFILE")" 2>/dev/null | tail -1
        else
            echo "daemon  : NOT RUNNING"
        fi
        [ -f "$STOPFLAG" ] && echo "stopflag: SET (auto-start blocked)" || echo "stopflag: clear"
        echo "interval: ${INTERVAL}s   log: $LOG"
        echo "origin   : $ORIGIN_URL (probe every ${ORIGIN_INTERVAL}s, alarm-only)"
        echo "sentinel : duty 6b silent-work — work ${SILENCE_WORK_SECS}s / evidence ${SILENCE_EVIDENCE_SECS}s vs checkpoint · ALERT at download/ALERT-ACTIVE.md"
        echo "audit    : duty 8 periodic compliance audit every ${AUDIT_INTERVAL}s (verdict in watcher.log)"
        if [ -f "$ORIGIN_STATE" ]; then
            O_EP="$(awk '{print $1}' "$ORIGIN_STATE" 2>/dev/null)"
            O_AL="$(awk '{print $2}' "$ORIGIN_STATE" 2>/dev/null)"
            echo "probe    : last $(date -d "@$O_EP" '+%F %T' 2>/dev/null || echo "@$O_EP") · last alarmed: ${O_AL:--}"
        else
            echo "probe    : never run (the first cycle after daemon start probes)"
        fi
        echo "--- watcher.log (last 10 lines) ---"
        tail -10 "$LOG" 2>/dev/null || echo "(empty)"
        exit 0
        ;;
esac

# ---------------------------------------------------------------------------
# --ensure / --force-start / no argument: start when needed
# ---------------------------------------------------------------------------
if alive; then
    echo "[watcher] already running (pid $(cat "$PIDFILE")) — nothing to do"
    exit 0
fi
if [ -f "$STOPFLAG" ] && [ "$1" != "--force-start" ]; then
    echo "[watcher] stop-flag is set — not starting. (delete $STOPFLAG or use --force-start)"
    exit 0
fi
# --force-start clears a leftover stop-flag, honoring its contract literally
if [ "$1" = "--force-start" ]; then
    rm -f "$STOPFLAG"
fi
if [ ! -f "$DEVSH" ]; then
    echo "[watcher] NOTE: $DEVSH not found — download/ tidy trigger disabled (explorer health, integrity checks, archive refresh and the compliance sentinel keep running)"
fi

# --- DOUBLE-FORK ORPHAN SPAWN (survives the platform's per-tool-call cleanup) --
(
    setsid bash -c '
        ZDIR="'"$ZDIR"'"
        PROJECT="'"$PROJECT"'"
        DOWNLOAD="'"$DOWNLOAD"'"
        DEVSH="'"$DEVSH"'"
        INTERVAL="'"$INTERVAL"'"
        ORIGIN_INTERVAL="'"$ORIGIN_INTERVAL"'"
        PIDFILE="$ZDIR/watcher.pid"
        STOPFLAG="$ZDIR/watcher.stop"
        LOG="$ZDIR/watcher.log"
        INSTALL_HINT="'"$INSTALL_HINT"'"
        SILENCE_WORK_SECS="'"$SILENCE_WORK_SECS"'"
        SILENCE_EVIDENCE_SECS="'"$SILENCE_EVIDENCE_SECS"'"
        AUDIT_INTERVAL="'"$AUDIT_INTERVAL"'"
        wlog() {
            echo "[$(date "+%F %T")] $*" >> "$LOG"
            if [ -s "$LOG" ] && [ "$(stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt 51200 ]; then
                tail -100 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
            fi
        }
        echo $$ > "$PIDFILE"
        wlog "watcher START (pid $$, interval ${INTERVAL}s, origin probe ${ORIGIN_INTERVAL}s, project $PROJECT)"
        CYCLES=0
        CANON_DIR="$DOWNLOAD/stellar-trail"
        GUARD_STATE="$ZDIR/.guard-release.state"
        # duty 1 hashes the top level of download/ EXCEPT the ALERT surface —
        # an alarm file appearing/clearing must never trigger dev.sh (the
        # sentinel does not get to kick the boot hook)
        LAST="$(ls -1 "$DOWNLOAD" 2>/dev/null | grep -v ^ALERT | sort | md5sum)"
        while true; do
            if [ -f "$STOPFLAG" ]; then
                wlog "watcher stopping: stop-flag detected"
                rm -f "$PIDFILE"
                exit 0
            fi
            sleep "$INTERVAL"

            # 1. download/ change trigger (dev.sh is optional; ALERT files
            #    are excluded from the hash — see the LAST= note above)
            CUR="$(ls -1 "$DOWNLOAD" 2>/dev/null | grep -v ^ALERT | sort | md5sum)"
            if [ "$CUR" != "$LAST" ]; then
                LAST="$CUR"
                if [ -f "$DEVSH" ]; then
                    wlog "download/ change detected -> running dev.sh"
                    bash "$DEVSH" >> "$LOG" 2>&1
                    wlog "dev.sh finished (return $?)"
                fi
            fi

            # 2. Task Files Explorer health (skip when a Next.js project owns the URL)
            if [ -f "$ZDIR/explorer.sh" ] && [ ! -f "$PROJECT/package.json" ]; then
                curl -fsS -m 2 http://127.0.0.1:3000/healthz >/dev/null 2>&1 || {
                    wlog "explorer unhealthy -> auto-restart (explorer.sh --ensure)"
                    bash "$ZDIR/explorer.sh" --ensure >> "$LOG" 2>&1
                }
            fi

            # 2b. Explorer deployment-gap notice (consumer report BUG #3):
            #     payload installed but never deployed leaves the
            #     UI a static copy with ZERO diagnostics — the one silent state
            #     in an otherwise loud watchdog. NOTICE only, once per gap
            #     episode; verify-only doctrine — the watcher never installs.
            #     CONSTRAINT (same as duty 7): this block lives inside a
            #     single-quoted bash -c string — NO single quotes here.
            GAP_ON=0
            if [ ! -f "$PROJECT/package.json" ]; then
                for GAP_SK in "$PROJECT/skills/stellar-trail" "$PROJECT"/skills/@*/stellar-trail; do
                    [ -f "$GAP_SK/assets/explorer/explorer.sh" ] && GAP_ON=1
                done
                [ -f "$ZDIR/explorer.sh" ] && GAP_ON=0
            fi
            if [ "$GAP_ON" = 1 ]; then
                if [ ! -f "$ZDIR/.explorer-gap.noticed" ]; then
                    touch "$ZDIR/.explorer-gap.noticed"
                    wlog "NOTICE: explorer payload ships in the skill tree but .zscripts/explorer.sh is not deployed — index.html stays a static copy until activated. Activate: bash skills/stellar-trail/scripts/bootstrap-sandbox.sh --ensure (auto-enables) or bash skills/stellar-trail/assets/explorer/explorer.sh --ensure; opt out on purpose with --without-explorer. The watcher never installs (verify-only)."
                    printf "\n> EXPLORER-GAP NOTICE %s: the installed skill ships assets/explorer but .zscripts/explorer.sh is absent — index.html stays a static copy until the module is activated. Run bash skills/stellar-trail/scripts/bootstrap-sandbox.sh --ensure (auto-enables explorer) or bash skills/stellar-trail/assets/explorer/explorer.sh --ensure; to keep it off on purpose use --without-explorer. The watcher never installs (verify-only notice, once per gap).\n" "$(date "+%F %T")" >> "$PROJECT/worklog.md" 2>/dev/null
                fi
            else
                rm -f "$ZDIR/.explorer-gap.noticed"
            fi

            # 3. Release-file guard (files outside the checksum manifest).
            #    Restore source = a healthy LIVE installation on the same
            #    release version (local cache-to-cache copy, verified after
            #    copy). No network, no alternate sources, no version changes.
            if [ -d "$CANON_DIR" ] && [ -f "$CANON_DIR/assets/integrity.version" ]; then
                REL_VER="$(cat "$CANON_DIR/assets/integrity.version" 2>/dev/null)"
                GUARD_ISSUE=""
                if [ -n "$REL_VER" ]; then
                    if [ ! -f "$CANON_DIR/skill-card.md" ]; then
                        GUARD_ISSUE="skill-card.md missing"
                    else
                        GUARD_CARD_V="$(grep -A3 -i "^## *Skill Version" "$CANON_DIR/skill-card.md" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)"
                        [ "$GUARD_CARD_V" = "$REL_VER" ] || GUARD_ISSUE="skill-card.md stale (card ${GUARD_CARD_V:-?} != release $REL_VER)"
                    fi
                    [ -f "$CANON_DIR/assets/integrity.sha256" ] || GUARD_ISSUE="${GUARD_ISSUE:+$GUARD_ISSUE; }assets/integrity.sha256 missing"
                fi
                if [ -z "$GUARD_ISSUE" ]; then
                    if [ -f "$GUARD_STATE" ]; then
                        rm -f "$GUARD_STATE"
                        wlog "release-file guard: healthy again (card == $REL_VER)"
                    fi
                else
                    # debounce restore attempts to one per 10 minutes
                    G_NOW=$(date +%s); G_LAST=0
                    [ -f "$GUARD_STATE" ] && G_LAST=$(stat -c%Y "$GUARD_STATE" 2>/dev/null || echo 0)
                    if [ $((G_NOW - G_LAST)) -ge 600 ]; then
                        touch "$GUARD_STATE"
                        wlog "release-file guard: $GUARD_ISSUE -> looking for a healthy live installation"
                        G_DONE=""
                        for G_LIVE in "$PROJECT/skills/stellar-trail" "$PROJECT"/skills/@*/stellar-trail; do
                            [ -f "$G_LIVE/skill-card.md" ] || continue
                            G_LV="$(cat "$G_LIVE/assets/integrity.version" 2>/dev/null)"
                            [ "$G_LV" = "$REL_VER" ] || continue
                            if ! (cd "$G_LIVE" && sha256sum -c assets/integrity.sha256 --quiet >/dev/null 2>&1); then
                                continue
                            fi
                            cp "$G_LIVE/skill-card.md" "$CANON_DIR/skill-card.md" 2>/dev/null && chmod 644 "$CANON_DIR/skill-card.md"
                            if [ ! -f "$CANON_DIR/assets/integrity.sha256" ] && [ -f "$G_LIVE/assets/integrity.sha256" ]; then
                                cp "$G_LIVE/assets/integrity.sha256" "$CANON_DIR/assets/integrity.sha256" 2>/dev/null && chmod 644 "$CANON_DIR/assets/integrity.sha256"
                            fi
                            G_CHK="$(grep -A3 -i "^## *Skill Version" "$CANON_DIR/skill-card.md" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)"
                            if [ "$G_CHK" = "$REL_VER" ]; then
                                rm -f "$GUARD_STATE"
                                wlog "release-file guard: RESTORED from $G_LIVE (card $G_CHK == release $REL_VER)"
                                G_DONE=1
                                break
                            else
                                wlog "release-file guard: restore from $G_LIVE failed verification after copy"
                            fi
                        done
                        [ -n "$G_DONE" ] || wlog "release-file guard: no healthy local copy for v$REL_VER — re-run the install command: $INSTALL_HINT"
                    fi
                fi
            fi

            CYCLES=$((CYCLES + 1))

            # 4. Installation integrity check (~every 10 minutes) — verify
            #    only. No automatic repair from alternate sources exists.
            #    v5.4.4: a failure also sets the INTEGRITY marker consumed by
            #    the 6b ALERT surface — watcher.log alone is invisible in the
            #    user file list (2026-10-23: the alarm sat unread for 25+ min
            #    after the platform-upgrade boot while the tree was broken).
            #    CONSTRAINT (same as duties 2b/6b/7): NO single quotes here.
            if [ $((CYCLES % 20)) -eq 0 ]; then
                INT_BAD=0
                for CAND in "$PROJECT/skills/stellar-trail" "$PROJECT"/skills/@*/stellar-trail; do
                    [ -d "$CAND" ] || continue
                    [ -f "$CAND/assets/integrity.sha256" ] || continue
                    if (cd "$CAND" && sha256sum -c assets/integrity.sha256 --quiet >/dev/null 2>&1); then
                        :   # healthy — nothing to log, keeps noise down
                    else
                        INT_BAD=1
                        touch "$ZDIR/.alert-integrity.on" 2>/dev/null
                        wlog "INTEGRITY ALARM: $CAND failed its checksum manifest — re-run the install command: $INSTALL_HINT"
                    fi
                done
                if [ "$INT_BAD" = 0 ]; then
                    rm -f "$ZDIR/.alert-integrity.on" 2>/dev/null
                fi
            fi

            # 5. Platform archive refresh (~every 15 minutes, own debounce)
            if [ $((CYCLES % 30)) -eq 0 ] && [ -f "$ZDIR/repo-snapshot.sh" ]; then
                bash "$ZDIR/repo-snapshot.sh" --apply-auto >> "$LOG" 2>&1
            fi

            # 6. Compliance sentinel (~every 2 minutes): the worklog is being
            #    written but memory/SESSION-STATE.md has not been rewritten for
            #    over 30 minutes — the protocol is not running as specified.
            if [ $((CYCLES % 4)) -eq 0 ]; then
                WL="$PROJECT/worklog.md"
                SS="$PROJECT/memory/SESSION-STATE.md"
                if [ -f "$WL" ] && [ -f "$SS" ]; then
                    WL_M=$(stat -c%Y "$WL" 2>/dev/null || echo 0)
                    SS_M=$(stat -c%Y "$SS" 2>/dev/null || echo 0)
                    NOW=$(date +%s)
                    if [ "$WL_M" -gt "$SS_M" ] && [ $((NOW - WL_M)) -lt 900 ] && [ $((WL_M - SS_M)) -gt 1800 ]; then
                        LAST_ALARM=0
                        [ -f "$ZDIR/.compliance-alarm.last" ] && LAST_ALARM=$(cat "$ZDIR/.compliance-alarm.last" 2>/dev/null)
                        if [ $((NOW - LAST_ALARM)) -gt 3600 ]; then
                            echo "$NOW" > "$ZDIR/.compliance-alarm.last"
                            printf "\n> COMPLIANCE-ALARM %s: the worklog is actively growing but memory/SESSION-STATE.md has not been checkpointed for over 30 minutes — the stellar-trail protocol is NOT running. Agent: invoke Skill(stellar-trail) NOW and run the cold-boot restore + checkpoint. User: audit the agent responses (look for the stellar-trail banner on every response).\n" "$(date "+%F %T")" >> "$WL"
                            wlog "COMPLIANCE-ALARM: SESSION-STATE stale >30m while the worklog is active"
                        fi
                    fi
                fi
            fi

            # 6b. Silent-work sentinel + ALERT surface (v2.3; incident class
            #     2026-10-21: sessions worked for real without writing a
            #     single protocol line — the worklog never grew, so the duty-6
            #     growth condition could never fire and ZERO alarms shot
            #     while the disk advanced two stages and user evidence sat
            #     unprocessed). This duty watches the OTHER side of the same
            #     failure: work artifacts whose mtimes run ahead of the last
            #     memory checkpoint. Two classes, separate labels and
            #     thresholds (env-tunable, see the header):
            #       WORK-SILENCE — workspace/ scripts/ download/ artifacts
            #         newer than the checkpoint by over the work threshold:
            #         work is happening without the protocol.
            #       EVIDENCE-PENDING — upload/ artifacts newer than the
            #         checkpoint by over the evidence threshold: user field
            #         evidence no logged session has processed.
            #     Alarms append one line to the worklog (1 h debounce per
            #     class) and refresh download/ALERT-ACTIVE.md — a surface in
            #     the user-visible file list; the worklog is only read when
            #     the protocol already runs (the guard that cannot wake the
            #     guard). The ALERT file also carries the duty-6 staleness
            #     class, is excluded from the duty-1 hash, and is removed
            #     automatically when every class clears. Verify-only: detect
            #     + alarm, never repair.
            #     CONSTRAINT (same as duties 2b/7): this block lives inside a
            #     single-quoted bash -c string — NO single quotes here.
            if [ $((CYCLES % 4)) -eq 0 ]; then
                SW_SS="$PROJECT/memory/SESSION-STATE.md"
                SW_WL="$PROJECT/worklog.md"
                if [ -f "$SW_SS" ]; then
                    SW_SS_M=$(stat -c%Y "$SW_SS" 2>/dev/null || echo 0)
                    SW_NOW=$(date +%s)
                    SW_CLASSES=""
                    SW_ANY=0
                    # class A — WORK-SILENCE: work artifacts outrunning the
                    # checkpoint by over the work threshold (canonical copy,
                    # node_modules and the ALERT surface itself excluded)
                    SW_MARK="$ZDIR/.silence-mark.work"
                    touch -d @$((SW_SS_M + SILENCE_WORK_SECS)) "$SW_MARK" 2>/dev/null
                    SW_A_N=$(find "$PROJECT/workspace" "$PROJECT/scripts" "$PROJECT/download" -type f -newer "$SW_MARK" -not -path "$PROJECT/download/stellar-trail/*" -not -path "*/node_modules/*" -not -name "ALERT-*" 2>/dev/null | wc -l)
                    if [ "$SW_A_N" -gt 0 ]; then
                        SW_ANY=1
                        SW_CLASSES="$SW_CLASSES WORK-SILENCE"
                        SW_LA=0
                        [ -f "$ZDIR/.silence-alarm.work.last" ] && SW_LA=$(cat "$ZDIR/.silence-alarm.work.last" 2>/dev/null)
                        case "$SW_LA" in ""|*[!0-9]*) SW_LA=0;; esac
                        if [ $((SW_NOW - SW_LA)) -gt 3600 ]; then
                            echo "$SW_NOW" > "$ZDIR/.silence-alarm.work.last"
                            printf "\n> SILENT-WORK-ALARM %s: %s work artifact(s) under workspace/ scripts/ download/ are newer than the last checkpoint by over %s minutes — work is happening WITHOUT the stellar-trail protocol (incident class 2026-10-21). Agent: invoke Skill(stellar-trail) + run M0 + treat the unlogged work as unverified input (rule 6). User: audit the responses — every marked response opens with the stellar-trail banner.\n" "$(date "+%F %T")" "$SW_A_N" "$((SILENCE_WORK_SECS / 60))" >> "$SW_WL" 2>/dev/null
                            wlog "SILENT-WORK-ALARM: $SW_A_N artifact(s) ahead of the checkpoint by over $((SILENCE_WORK_SECS / 60)) min (WORK-SILENCE)"
                        fi
                    fi
                    # class B — EVIDENCE-PENDING: user field evidence no
                    # logged session has processed (the upload-05:25 case)
                    SW_MARK_B="$ZDIR/.silence-mark.evidence"
                    touch -d @$((SW_SS_M + SILENCE_EVIDENCE_SECS)) "$SW_MARK_B" 2>/dev/null
                    SW_B_N=$(find "$PROJECT/upload" -type f -newer "$SW_MARK_B" -not -path "*/node_modules/*" 2>/dev/null | wc -l)
                    if [ "$SW_B_N" -gt 0 ]; then
                        SW_ANY=1
                        SW_CLASSES="$SW_CLASSES EVIDENCE-PENDING"
                        SW_LB=0
                        [ -f "$ZDIR/.silence-alarm.evidence.last" ] && SW_LB=$(cat "$ZDIR/.silence-alarm.evidence.last" 2>/dev/null)
                        case "$SW_LB" in ""|*[!0-9]*) SW_LB=0;; esac
                        if [ $((SW_NOW - SW_LB)) -gt 3600 ]; then
                            echo "$SW_NOW" > "$ZDIR/.silence-alarm.evidence.last"
                            printf "\n> EVIDENCE-PENDING-ALARM %s: %s file(s) in upload/ are newer than the last checkpoint by over %s minutes — user-provided field evidence has not been processed by any logged session (incident class 2026-10-21). Agent: at the next session run M0 and process it under the rule-6 unverified-input posture. User: this evidence is still waiting.\n" "$(date "+%F %T")" "$SW_B_N" "$((SILENCE_EVIDENCE_SECS / 60))" >> "$SW_WL" 2>/dev/null
                            wlog "EVIDENCE-PENDING-ALARM: $SW_B_N upload file(s) ahead of the checkpoint by over $((SILENCE_EVIDENCE_SECS / 60)) min"
                        fi
                    fi
                    # class C — the duty-6 staleness condition, mirrored here
                    # only so the ALERT file carries the full picture (the
                    # worklog alarm for this class stays with duty 6 alone)
                    if [ -f "$SW_WL" ]; then
                        SW_WL_M=$(stat -c%Y "$SW_WL" 2>/dev/null || echo 0)
                        if [ "$SW_WL_M" -gt "$SW_SS_M" ] && [ $((SW_NOW - SW_WL_M)) -lt 900 ] && [ $((SW_WL_M - SW_SS_M)) -gt 1800 ]; then
                            SW_ANY=1
                            SW_CLASSES="$SW_CLASSES COMPLIANCE-STALE"
                        fi
                    fi
                    # class D — INTEGRITY (v5.4.4): the duty-4 checksum marker.
                    # An installation can fail its manifest while every version
                    # string aligns (the 2026-10-23 dead-session promotion miss:
                    # duty-4 caught it at 12:41:49, yet nothing surfaced it to
                    # the user until a compliant session read watcher.log). Set
                    # by duty 4 on failure; cleared by its next passing cycle.
                    if [ -f "$ZDIR/.alert-integrity.on" ]; then
                        SW_ANY=1
                        SW_CLASSES="$SW_CLASSES INTEGRITY"
                    fi
                    # ALERT surface — one file in the user-visible list. The
                    # worklog paradox (alarms written only where the protocol
                    # already reads) is what let the 2026-10-21 incident run
                    # its full course unseen; this file is what the user sees
                    # WITHOUT loading anything. Refreshed when the active
                    # class set changes; removed on all-clear (self-heals a
                    # manual deletion while classes remain active).
                    SW_ALERT="$DOWNLOAD/ALERT-ACTIVE.md"
                    if [ "$SW_ANY" = 1 ]; then
                        SW_PREV="-"
                        [ -f "$ZDIR/.alert-classes.last" ] && SW_PREV=$(cat "$ZDIR/.alert-classes.last" 2>/dev/null)
                        if [ "$SW_PREV" != "$SW_CLASSES" ] || [ ! -f "$SW_ALERT" ]; then
                            printf "%s\n" "$SW_CLASSES" > "$ZDIR/.alert-classes.last" 2>/dev/null
                            printf "> stellar-trail WATCHDOG ALERT — active since %s\n> Active classes:%s\n> Meaning: work artifacts or user evidence are running ahead of the last memory checkpoint, the worklog is growing without one, or an installation failed its checksum manifest (INTEGRITY class) — the protocol is not running as specified.\n> Agent remediation: invoke Skill(stellar-trail), run M0, apply the rule-6 unverified-input posture over any unlogged work found on disk.\n> User remediation: audit the agent responses — every marked response opens with the stellar-trail banner; this file is removed automatically once every class clears (watcher = verify-only, it never repairs).\n" "$(date "+%F %T")" "$SW_CLASSES" > "$SW_ALERT" 2>/dev/null
                            wlog "ALERT surface refreshed:$SW_CLASSES"
                        fi
                    elif [ -f "$SW_ALERT" ]; then
                        rm -f "$SW_ALERT"
                        printf "%s\n" "-" > "$ZDIR/.alert-classes.last" 2>/dev/null
                        wlog "silent-work sentinel: all clear — download/ALERT-ACTIVE.md removed"
                    fi
                fi
            fi

            # 7. Origin release probe (~every 24 hours; epoch-state-gated so
            #    container reboots do not reset the clock — cycle counting
            #    would). The probe runs as a one-shot child invocation of
            #    this same script (--probe-origin): single source of truth.
            #    ALARM-ONLY — the watcher never installs (single-flow
            #    doctrine); a newer origin tag alarms the worklog once per
            #    unseen version.
            #    CONSTRAINT: this block lives inside a single-quoted bash -c
            #    string — NO single quotes allowed here (no awk programs, no
            #    empty-string case patterns written with quotes); use cat +
            #    parameter expansion instead.
            ORIGIN_STATE="$ZDIR/.origin-probe.last"
            O_NOW=$(date +%s)
            O_LINE=""
            [ -f "$ORIGIN_STATE" ] && O_LINE="$(cat "$ORIGIN_STATE" 2>/dev/null)"
            O_LAST="${O_LINE%% *}"
            case "$O_LAST" in ""|*[!0-9]*) O_LAST=0;; esac
            if [ $((O_NOW - O_LAST)) -ge "$ORIGIN_INTERVAL" ] && [ -f "$ZDIR/watcher.sh" ]; then
                wlog "origin release probe due -> watcher.sh --probe-origin"
                bash "$ZDIR/watcher.sh" --probe-origin >> "$LOG" 2>&1
            fi

            # 8. Periodic compliance audit (~every 6 h, epoch-state-gated like
            #    duty 7 so container reboots do not reset the clock): the
            #    external audit-compliance.sh ran only at major checkpoints
            #    and manual calls (field-verified 2026-10-21) — between them,
            #    compliance drift had no scheduled detector. The verdict goes
            #    to watcher.log as greppable history; a FAIL also appends a
            #    one-line worklog alarm. The audit gained a silent-work check
            #    in v5.4.0, so the periodic record covers the incident class
            #    as well. Verify-only — the audit never repairs anything.
            #    CONSTRAINT (same as duties 2b/6b/7): NO single quotes here.
            AUDIT_STATE="$ZDIR/.audit-periodic.last"
            A8_NOW=$(date +%s)
            A8_LINE=""
            [ -f "$AUDIT_STATE" ] && A8_LINE="$(cat "$AUDIT_STATE" 2>/dev/null)"
            A8_LAST="${A8_LINE%% *}"
            case "$A8_LAST" in ""|*[!0-9]*) A8_LAST=0;; esac
            if [ $((A8_NOW - A8_LAST)) -ge "$AUDIT_INTERVAL" ]; then
                AUDIT_SH=""
                for AUD_CAND in "$PROJECT/skills/stellar-trail" "$PROJECT"/skills/@*/stellar-trail; do
                    if [ -f "$AUD_CAND/scripts/audit-compliance.sh" ]; then
                        AUDIT_SH="$AUD_CAND/scripts/audit-compliance.sh"
                        break
                    fi
                done
                if [ -n "$AUDIT_SH" ]; then
                    echo "$A8_NOW" > "$AUDIT_STATE" 2>/dev/null
                    wlog "periodic compliance audit due -> audit-compliance.sh"
                    AUD_OUT="$(bash "$AUDIT_SH" --root "$PROJECT" 2>&1)"; AUD_RC=$?
                    wlog "periodic audit verdict:$(echo "$AUD_OUT" | tail -1) (rc $AUD_RC)"
                    if [ "$AUD_RC" -ne 0 ]; then
                        printf "\n> PERIODIC-AUDIT-ALARM %s: the scheduled compliance audit FAILED — run bash skills/stellar-trail/scripts/audit-compliance.sh for the findings and settle them at the next M0/M1.\n" "$(date "+%F %T")" >> "$PROJECT/worklog.md" 2>/dev/null
                        wlog "PERIODIC-AUDIT-ALARM: audit-compliance FAILED (rc $AUD_RC)"
                    fi
                fi
            fi
        done
    ' >/dev/null 2>&1 &
)
sleep 1
if alive; then
    echo "[watcher] STARTED (pid $(cat "$PIDFILE"), PPID=$(awk '{print $4}' /proc/$(cat "$PIDFILE")/stat 2>/dev/null) — orphaned, survives per-tool-call cleanup)"
else
    echo "[watcher] FAILED to start — check $LOG"
    exit 1
fi
