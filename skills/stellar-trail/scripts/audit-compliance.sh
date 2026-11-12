#!/usr/bin/env bash
# ============================================================================
# audit-compliance.sh — external protocol compliance audit for stellar-trail
# stellar-trail · external compliance audit (on-disk artifacts only)
#
# WHY THIS EXISTS: protocol violations stay silent because a response without
#   phase markers raises no error anywhere. This script gives the user one
#   cheap command to check the compliance signature of the on-disk artifacts,
#   WITHOUT relying on the model's discipline. Read-only: it never repairs
#   anything (repair = the agent's checkpoint discipline, or re-running the
#   install command for installation issues).
#
# CHECKS (each prints PASS / WARN / FAIL with a one-line explanation):
#   memory-foundation        memory/SESSION-STATE.md exists (the memory
#                            protocol's foundation)
#   active-table-hygiene     the Active Tasks table contains only
#                            ACTIVE/WAITING/BLOCKED/STALE rows — a DONE or CANCELLED
#                            row there makes finished work look pending
#   checkpoint-staleness     the worklog is actively growing while
#                            SESSION-STATE.md has not been rewritten for over
#                            30 minutes — the signature of a missing checkpoint
#   silent-work               work artifacts (workspace/ scripts/ download/
#                            upload/, minus the watcher-guarded canonical copy)
#                            whose mtimes run ahead of the last checkpoint by
#                            over the threshold — the signature of sessions
#                            working WITHOUT the protocol at all (incident
#                            class 2026-10-21: a 66-minute silent-work window
#                            froze the worklog, so checkpoint-staleness never
#                            fired; this check watches the disk instead)
#   version-sanity           every installed copy reports the same version as
#                            the canonical snapshot — drift means a stale or
#                            damaged installation
#   tree-integrity (v5.4.4)  every skill tree (live + canonical + dev) passes
#                            its OWN checksum manifest — version equality
#                            alone passed over a tree whose promotion missed
#                            one file (incident 2026-10-23: the watcher's
#                            duty-4 caught what this audit missed)
#   release-recording (v5.4.4) the dev tree's NEWEST tag hash appears in the
#                            ledger (worklog + archive + memory) — a committed
#                            release nobody recorded is dead-session debt
#                            (incident 2026-10-23: v5.4.3 committed, session
#                            died pre-M1, the summary narrated it as done)
#   watcher-liveness (v5.4.4) the watchdog daemon is alive — a mid-session
#                            watcher death left duty 4/6b/8 blind for hours
#                            (2026-10-23: pid 920 died ~06:22–06:37 unseen)
#   worklog-activation-hook  the activation hook line is present at the tail
#                            of the worklog (keeps the activation chain alive
#                            across resets)
#   memory-activation-hooks  the activation hook line is present at the head
#                            of BOTH always-read memory files (SESSION-STATE
#                            + MEMORY — R1 scope extension)
#   sealed-shield (v5.5.0)   one-ID-one-table: no Sealed Task ID appears as an
#                            Active row — the duplicate-execution class (a
#                            sealed task picked back up and re-run by the LLM);
#                            ref mentions in descriptions stay legal (H4)
#   sealed-shield (v5.5.0)   one-ID-one-table: no Sealed Task ID appears as an
#                            Active row — the duplicate-execution class (a
#                            sealed task picked back up and re-run by the LLM);
#                            ref mentions in descriptions stay legal (H4)
#   sealed-shield (v5.5.0)   one-ID-one-table: no Sealed Task ID appears as an
#                            Active row — the duplicate-execution class (a
#                            sealed task picked back up and re-run by the LLM);
#                            ref mentions in descriptions stay legal (H4)
#
# FRESH-INSTALL NOTE: on a CLI-only installation without the persistence
#   layer, memory-foundation FAIL and worklog-activation-hook WARN are the
#   EXPECTED post-install state, not violations — run
#   scripts/bootstrap-sandbox.sh to arm the persistence layer (memory is
#   consent-gated by the first session).
#
# VERDICT: any FAIL → exit 1 · only PASS/WARN → exit 0
#   (WARN = a finding that can be legitimately momentary — reported, not fatal)
#
# Usage:
#   bash scripts/audit-compliance.sh [--root <project-root>] [--quiet]
#   --root  default: three levels above this script (standard skill layout);
#           adjust when the project root differs
# ============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd)"
QUIET=0

while [ $# -gt 0 ]; do
    case "$1" in
        --root)  ROOT="$(cd "$2" 2>/dev/null && pwd)" || { echo "ERROR: invalid --root $2"; exit 2; }; shift 2 ;;
        --quiet) QUIET=1; shift ;;
        *) echo "usage: bash scripts/audit-compliance.sh [--root <dir>] [--quiet]"; exit 2 ;;
    esac
done

PASS=0; WARN=0; FAIL=0
say() { [ "$QUIET" -eq 0 ] && echo "$*"; return 0; }
res() { # res <PASS|WARN|FAIL> <check-name> <detail>
    case "$1" in
        PASS) PASS=$((PASS+1)); say "  [PASS] $2 — $3" ;;
        WARN) WARN=$((WARN+1)); say "  [WARN] $2 — $3" ;;
        *)    FAIL=$((FAIL+1)); say "  [FAIL] $2 — $3" ;;
    esac
}

say "[audit-compliance] root: $ROOT"

# --- memory-foundation -------------------------------------------------------
SS="$ROOT/memory/SESSION-STATE.md"
WL="$ROOT/worklog.md"
if [ -f "$SS" ]; then res PASS "memory-foundation" "SESSION-STATE.md present ($(wc -l < "$SS") lines)"
else res FAIL "memory-foundation" "memory/SESSION-STATE.md MISSING — the memory protocol has no foundation — fresh install? run: bash scripts/bootstrap-sandbox.sh (memory is consent-gated by the first session)"; fi

# --- active-table-hygiene ----------------------------------------------------
if [ -f "$SS" ]; then
    # extract the Active Tasks section, then look for terminal statuses in the status column
    ACTIVE_ROWS="$(awk '/^## Active Tasks/{f=1;next} /^## /{f=0} f && /^\|/' "$SS" | grep -vE '^\|[[:space:]]*-|^\|[[:space:]]*Task ID' || true)"
    if [ -z "$ACTIVE_ROWS" ]; then
        res PASS "active-table-hygiene" "active table empty (no active tasks) — clean"
    elif echo "$ACTIVE_ROWS" | grep -qiE '\| *(DONE|CANCELLED|TERTUTUP|SEALED) *\|'; then
        res FAIL "active-table-hygiene" "terminal row (DONE/CANCELLED/...) inside the Active table — finished work displayed as pending, stale-pickup risk"
    else
        res PASS "active-table-hygiene" "active table holds only ACTIVE/WAITING/BLOCKED/STALE rows ($(echo "$ACTIVE_ROWS" | wc -l) rows)"
    fi
fi

# --- sealed-shield (v5.5.0; Max shield) --------------------------------------
# One-ID-one-table law: a Task ID exists in exactly ONE of Active/Sealed —
# never both. A sealed ID sitting in the Active table as a row ID is the
# duplicate-execution class the owner ordered killed: the LLM picking sealed
# work back up and re-running it. Ref mentions in descriptions ("ref: #oldID")
# are LEGAL revisits (H4); only an ID-column collision is the violation.
if [ -f "$SS" ]; then
    SEALED_IDS="$(awk '/^## Sealed Tasks/{f=1;next} /^## /{f=0} f && /^\|/ {print $2}' "$SS" 2>/dev/null | grep -oE '^[0-9]+' | sort -u || true)"
    SSH_BAD=""
    if [ -n "$SEALED_IDS" ] && [ -n "${ACTIVE_ROWS:-}" ]; then
        for SSH_ID in $SEALED_IDS; do
            printf '%s\n' "$ACTIVE_ROWS" | grep -qE "^\| *${SSH_ID} *\|" && SSH_BAD="$SSH_BAD $SSH_ID"
        done
    fi
    if [ -n "$SSH_BAD" ]; then
        res FAIL "sealed-shield" "sealed Task ID(s) present as Active row(s):$SSH_BAD — one-ID-one-table violation (duplicate-execution class); quarantine per H7, re-run"
    else
        res PASS "sealed-shield" "Active∩Sealed = ∅ — no sealed ID picked up as work (ref mentions legal)"
    fi
fi

# --- checkpoint-staleness ----------------------------------------------------
if [ -f "$SS" ] && [ -f "$WL" ]; then
    SS_M=$(stat -c%Y "$SS" 2>/dev/null || echo 0)
    WL_M=$(stat -c%Y "$WL" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    if [ "$WL_M" -gt "$SS_M" ] && [ $((NOW - WL_M)) -lt 900 ] && [ $((WL_M - SS_M)) -gt 1800 ]; then
        res WARN "checkpoint-staleness" "worklog active ($(date -d "@$WL_M" '+%H:%M' 2>/dev/null)) but SESSION-STATE last written $(date -d "@$SS_M" '+%H:%M' 2>/dev/null) — gap $(( (WL_M - SS_M) / 60 )) min: the signature of a missing checkpoint"
    else
        res PASS "checkpoint-staleness" "checkpoint fresh (safe gap / no active work orphaned from its checkpoint)"
    fi
fi

# --- silent-work (v5.4.0; incident 2026-10-21) -------------------------------
# The checkpoint-staleness check above needs the worklog to GROW; sessions
# that work without writing a single protocol line freeze the worklog and
# slip past it (field-proven: a 66-minute silent-work window, zero alarms).
# This check watches the other side: work artifacts whose mtimes run ahead
# of the last checkpoint by the threshold (env-tunable, same knobs as the
# watcher duty 6b: STELLAR_SILENCE_WORK_SECS / STELLAR_SILENCE_EVIDENCE_SECS).
# WARN, not FAIL: during compliant work an artifact can legitimately sit
# between completion and its M1 — the real-time alarm is watcher duty 6b;
# this check makes the signal greppable in scheduled/manual audits.
if [ -f "$SS" ]; then
    SW_SS_M=$(stat -c%Y "$SS" 2>/dev/null || echo 0)
    SW_TH="${STELLAR_SILENCE_WORK_SECS:-1800}"
    SW_EV="${STELLAR_SILENCE_EVIDENCE_SECS:-7200}"
    SW_MARK="$(mktemp)"
    touch -d @$((SW_SS_M + SW_TH)) "$SW_MARK" 2>/dev/null
    SW_N=$(find "$ROOT/workspace" "$ROOT/scripts" "$ROOT/download" -type f -newer "$SW_MARK" \
        -not -path "*/node_modules/*" -not -name "ALERT-*" 2>/dev/null | wc -l)
    rm -f "$SW_MARK"
    SW_MARK2="$(mktemp)"
    touch -d @$((SW_SS_M + SW_EV)) "$SW_MARK2" 2>/dev/null
    SW_E=$(find "$ROOT/upload" -type f -newer "$SW_MARK2" -not -path "*/node_modules/*" 2>/dev/null | wc -l)
    rm -f "$SW_MARK2"
    if [ "$SW_N" -gt 0 ]; then
        res WARN "silent-work" "$SW_N work artifact(s) under workspace/ scripts/ download/ newer than the last checkpoint by over $((SW_TH / 60)) min — work may be running without the protocol (incident class 2026-10-21); verify from disk before building on it"
    elif [ "$SW_E" -gt 0 ]; then
        res WARN "silent-work" "$SW_E upload file(s) newer than the last checkpoint by over $((SW_EV / 60)) min — user-provided evidence not yet processed by a logged session"
    else
        res PASS "silent-work" "no work artifact outruns the last checkpoint (everything logged / safe gap)"
    fi
fi

# --- version-sanity ----------------------------------------------------------
# : the registry lock anchor is fully retired — every installed copy is now compared against the canonical snapshot
#   (.zscripts/stellar-trail-canonical), the one out-of-band reference the GitHub
#   install path has always had. (The pre-code read the lock file but
#   never actually used CANON_VER — the canonical comparison the header
#   always claimed became real in this version.)
CANON_VER="$(cat "$ROOT/.zscripts/stellar-trail-canonical/assets/integrity.version" 2>/dev/null || true)"
for CAND in "$ROOT/skills/stellar-trail" "$ROOT"/skills/@*/stellar-trail; do
    [ -d "$CAND" ] || continue
    IV="$(cat "$CAND/assets/integrity.version" 2>/dev/null || echo '?')"
    KEY="$(basename "$(dirname "$CAND")")/$(basename "$CAND")"; [ "$KEY" = "skills/stellar-trail" ] && KEY="stellar-trail"
    if [ "$IV" = "?" ]; then res WARN "version-sanity ($KEY)" "integrity.version unreadable in $CAND"
    elif [ -z "$CANON_VER" ]; then res WARN "version-sanity ($KEY)" "no canonical snapshot to compare against — run: bash scripts/bootstrap-sandbox.sh"
    elif [ "$IV" != "$CANON_VER" ]; then res WARN "version-sanity ($KEY)" "installed $IV != canonical $CANON_VER — re-run the install command: npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw -y"
    else res PASS "version-sanity ($KEY)" "installed $IV = canonical $CANON_VER"
    fi
done

# --- tree-integrity (v5.4.4; incident 2026-10-23) ----------------------------
# Version equality passed over a broken tree: the v5.4.3 promotion missed one
# file (references/task-files-explorer.md) in live+canonical while every
# version string said 5.4.3 — the watcher duty-4 INTEGRITY ALARM caught it;
# this audit PASSED 8/8 over the same tree. Per-tree checksum verification
# closes the gap at every audit run (manual + duty-8 periodic).
INT_PASS=0; INT_BAD_TREES=""
for TI_T in "$ROOT/skills/stellar-trail" "$ROOT/.zscripts/stellar-trail-canonical" "$ROOT/stellar-trail-dev/skills/stellar-trail"; do
    [ -f "$TI_T/assets/integrity.sha256" ] || continue
    TI_OUT="$(cd "$TI_T" && sha256sum -c assets/integrity.sha256 2>&1)"
    if [ $? -eq 0 ]; then
        INT_PASS=$((INT_PASS+1))
    else
        TI_N=$(printf '%s\n' "$TI_OUT" | grep -c ': FAILED')
        INT_BAD_TREES="$INT_BAD_TREES ${TI_T##*project/}:$TI_N"
    fi
done
if [ -z "$INT_BAD_TREES" ]; then
    res PASS "tree-integrity" "all $INT_PASS skill tree(s) pass their checksum manifest"
else
    res WARN "tree-integrity" "checksum-manifest failures (path:count) —$INT_BAD_TREES — repair from a healthy tree / re-run the install command; verify the promotion instrument"
fi

# --- release-recording (v5.4.4; dead-session class 2026-10-23) ---------------
# The dying session committed + tagged v5.4.3 but never wrote the delivery
# worklog section or the M1 — the ledger believed the release was still
# "fix locked" while live served 5.4.3, and the continuation summary narrated
# the missing steps as done. The NEWEST tag's commit hash must appear in the
# ledger (worklog, archive, or either memory file); an unmentioned newest tag
# is unrecorded-release debt: settle from disk at the next M0/M1.
RR_DEV="$ROOT/stellar-trail-dev"
if [ -d "$RR_DEV/.git" ]; then
    RR_TAG="$(git -C "$RR_DEV" describe --tags --abbrev=0 2>/dev/null || true)"
    RR_HASH="$(git -C "$RR_DEV" rev-parse --short=7 "$RR_TAG" 2>/dev/null || true)"
    RR_FOUND=0
    for RR_F in "$WL" "$ROOT/worklog-archive.md" "$SS" "$ROOT/memory/MEMORY.md"; do
        [ -f "$RR_F" ] || continue
        if grep -q "$RR_HASH" "$RR_F" 2>/dev/null; then RR_FOUND=1; break; fi
    done
    if [ -z "$RR_TAG" ] || [ -z "$RR_HASH" ]; then
        res WARN "release-recording" "newest tag unreadable in $RR_DEV — check the git tree"
    elif [ "$RR_FOUND" = 1 ]; then
        res PASS "release-recording" "newest release $RR_TAG ($RR_HASH) is recorded in the ledger"
    else
        res WARN "release-recording" "newest tag $RR_TAG ($RR_HASH) appears NOWHERE in worklog/worklog-archive/SESSION-STATE/MEMORY — an unrecorded release (dead-session debt, incident class 2026-10-23): settle from disk at the next M0/M1 before new work"
    fi
fi

# --- watcher-liveness (v5.4.4; dead-watcher window 2026-10-23) ---------------
# The pre-upgrade watcher died silently mid-session while the session kept
# working — arms run at M0 only, so duty 4/6b/8 went blind for hours until the
# next container boot re-armed them. The audit now reports daemon liveness
# itself; a dead watcher is a WARN, not a FAIL (CLI-only installs have no
# .zscripts layer at all — that case passes by design).
if [ -d "$ROOT/.zscripts" ]; then
    WLV_PID="$(cat "$ROOT/.zscripts/watcher.pid" 2>/dev/null || true)"
    if [ -n "$WLV_PID" ] && kill -0 "$WLV_PID" 2>/dev/null; then
        res PASS "watcher-liveness" "watcher daemon alive (pid $WLV_PID)"
    else
        res WARN "watcher-liveness" "watcher daemon NOT running — duty 4/6b/8 are blind until the next boot; run: bash scripts/bootstrap-sandbox.sh --ensure"
    fi
else
    res PASS "watcher-liveness" "no .zscripts layer (CLI-only install) — check skipped by design"
fi

# --- worklog-activation-hook -------------------------------------------------
if [ -f "$WL" ]; then
    if tail -50 "$WL" | grep -q '⚡ACTIVATE'; then
        res PASS "worklog-activation-hook" "activation trigger present at the worklog tail"
    else
        res WARN "worklog-activation-hook" "no ⚡ACTIVATE line within the last 50 worklog lines — the activation hook has not been appended yet — fresh install? run: bash scripts/bootstrap-sandbox.sh"
    fi
fi

# --- memory-activation-hooks (R1 scope extension) -----------------
for MF in "$ROOT/memory/SESSION-STATE.md" "$ROOT/memory/MEMORY.md"; do
    MFB="$(basename "$MF")"
    if [ ! -f "$MF" ]; then
        res WARN "memory-activation-hook ($MFB)" "memory file missing — fresh install? run: bash scripts/bootstrap-sandbox.sh (memory is consent-gated by the first session)"
    elif head -3 "$MF" | grep -q '⚡ACTIVATE'; then
        res PASS "memory-activation-hook ($MFB)" "activation trigger present in the header (first 3 lines)"
    else
        res WARN "memory-activation-hook ($MFB)" "no ⚡ACTIVATE line in the first 3 lines — restore the hook at the next M1 (SKILL.md R1: the trigger rides BOTH always-read memory headers)"
    fi
done

# --- verdict -------------------------------------------------------------------
say "[audit-compliance] VERDICT: PASS=$PASS WARN=$WARN FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
    say "[audit-compliance] FAILED — the FAIL findings above must be handled (seal the task with a checkpoint / re-run the install command / re-audit)"
    exit 1
fi
say "[audit-compliance] PASSED — ${WARN:+$WARN WARN finding(s) reported above}"
exit 0
