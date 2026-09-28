#!/usr/bin/env bash
# ============================================================================
# audit-compliance.sh — external protocol compliance audit for stellar-trail
# stellar-trail v3.6.8 · 2026-09-28
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
#                            ACTIVE/BLOCKED/STALE rows — a DONE or CANCELLED
#                            row there makes finished work look pending
#   checkpoint-staleness     the worklog is actively growing while
#                            SESSION-STATE.md has not been rewritten for over
#                            30 minutes — the signature of a missing checkpoint
#   version-sanity           every installed copy reports the same version as
#                            the canonical snapshot — drift means a stale or
#                            damaged installation
#   worklog-activation-hook  the activation hook line is present at the tail
#                            of the worklog (keeps the activation chain alive
#                            across resets)
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
        res PASS "active-table-hygiene" "active table holds only ACTIVE/BLOCKED/STALE rows ($(echo "$ACTIVE_ROWS" | wc -l) rows)"
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

# --- version-sanity ----------------------------------------------------------
# v3.6.8: the registry lock anchor is fully retired — every installed copy is now compared against the canonical snapshot
#   (download/stellar-trail), the one out-of-band reference the GitHub
#   install path has always had. (The pre-v3.6.8 code read the lock file but
#   never actually used CANON_VER — the canonical comparison the header
#   always claimed became real in this version.)
CANON_VER="$(cat "$ROOT/download/stellar-trail/assets/integrity.version" 2>/dev/null || true)"
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

# --- worklog-activation-hook -------------------------------------------------
if [ -f "$WL" ]; then
    if tail -50 "$WL" | grep -q '⚡ACTIVATE'; then
        res PASS "worklog-activation-hook" "activation trigger present at the worklog tail"
    else
        res WARN "worklog-activation-hook" "no ⚡ACTIVATE line within the last 50 worklog lines — the activation hook has not been appended yet — fresh install? run: bash scripts/bootstrap-sandbox.sh"
    fi
fi

# --- verdict -------------------------------------------------------------------
say "[audit-compliance] VERDICT: PASS=$PASS WARN=$WARN FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
    say "[audit-compliance] FAILED — the FAIL findings above must be handled (seal the task with a checkpoint / re-run the install command / re-audit)"
    exit 1
fi
say "[audit-compliance] PASSED — ${WARN:+$WARN WARN finding(s) reported above}"
exit 0
