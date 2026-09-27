#!/usr/bin/env bash
# ============================================================================
# update-skill.sh — auto-update check + install wrapper for stellar-trail
# stellar-trail v3.6.7 · 2026-09-27
#
# THE SINGLE INSTALLATION FLOW (locked decision 2026-09-27):
#     npx skills add hoshiyomiX/stellar-trail
# Fresh install and upgrade are the SAME command — the skills CLI installs
# over an existing installation in place. This script never installs by any
# other means. It only:
#   1. checks the GitHub origin for a newer release tag (public read, no
#      credential needed; debounced to one network check per 24 hours), and
#   2. when the origin is newer, runs that one install command, then
#      verifies the result and re-arms the persistence modules.
# There is NO fallback source and NO alternate repair path. If the install
# fails, it fails loudly (exit 1) and this script has touched nothing —
# the user retries the same command.
#
# Usage:
#   bash scripts/update-skill.sh [--ensure|--force|--check|--status|--help]
#   (no argument = --ensure — the protocol's cold-boot path)
#     --ensure   debounced check; auto-update when the origin is newer
#     --force    bypass the debounce; check now and update if newer
#     --check    network check without installing (dry-run report)
#     --status   local state report, no network access
#
# Environment overrides:
#   STELLAR_PROJECT               project root (auto-detected when unset)
#   STELLAR_UPDATE_ORIGIN         git URL used for the version check
#                                 (default: https://github.com/hoshiyomiX/stellar-trail.git)
#   STELLAR_INSTALL_SOURCE        package argument for the install command
#                                 (default: hoshiyomiX/stellar-trail)
#   STELLAR_INSTALL_ARGS          extra arguments for the install command
#                                 (default: "--skill stellar-trail -a openclaw -y")
#   STELLAR_UPDATE_STATE          debounce state file
#                                 (default: <project>/.zscripts/.update-check.last)
#   STELLAR_UPDATE_DEBOUNCE       debounce window in seconds (default: 86400)
#   STELLAR_UPDATE_BOOTSTRAP_ARGS post-install bootstrap arguments
#                                 (default: "--ensure --with-explorer --with-snapshot")
#
# Exit codes:
#   0  ok / already latest / downgrade refused / offline (never blocks cold boot)
#   1  install attempted and FAILED (command failure or verification failure)
# ============================================================================
set -u

# --- SELF-COPY RE-EXEC -------------------------------------------------------
# The install command overwrites the directory this script runs from, and
# executing a script file while it is being replaced is undefined behavior.
# Copy this script to a temp file and re-exec from there; the temp copy is
# deleted on exit and the original file is safe to overwrite.
if [ "${STELLAR_UPDATE_SELFEXE:-}" != "1" ]; then
    _tmp_self="$(mktemp /tmp/stellar-trail-update.XXXXXX.sh)" || exit 1
    if ! cat "${BASH_SOURCE[0]}" > "$_tmp_self" 2>/dev/null; then
        echo "[update] FATAL: cannot copy this script to $_tmp_self" >&2; exit 1
    fi
    STELLAR_UPDATE_SELFEXE=1 STELLAR_UPDATE_ORIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" \
        exec bash "$_tmp_self" "$@"
fi
trap 'rm -f "$0" 2>/dev/null' EXIT
SELF_DIR="${STELLAR_UPDATE_ORIG_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

say() { echo "[update] $*"; }

# --- LOCATIONS ---------------------------------------------------------------
SKILL_ROOT="$(cd "$SELF_DIR/.." && pwd)"
PROJECT="${STELLAR_PROJECT:-}"
if [ -z "$PROJECT" ]; then
    _d="$SELF_DIR"
    for _ in 1 2 3 4 5 6 7; do
        _d="$(dirname "$_d")"
        if [ -d "$_d/skills" ] || [ -d "$_d/download" ] || [ -d "$_d/.zscripts" ] \
           || [ -f "$_d/worklog.md" ]; then
            PROJECT="$_d"; break
        fi
        [ "$_d" = "/" ] && break
    done
fi
PROJECT="${PROJECT:-$(dirname "$(dirname "$SKILL_ROOT")")}"
ZDIR="$PROJECT/.zscripts"
ORIGIN="${STELLAR_UPDATE_ORIGIN:-https://github.com/hoshiyomiX/stellar-trail.git}"
INSTALL_SOURCE="${STELLAR_INSTALL_SOURCE:-hoshiyomiX/stellar-trail}"
STATE="${STELLAR_UPDATE_STATE:-$ZDIR/.update-check.last}"
DEBOUNCE="${STELLAR_UPDATE_DEBOUNCE:-86400}"

# version_lt <a> <b> — true when a < b on loose x.y.z version patterns
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

local_version() {
    cat "$SKILL_ROOT/assets/integrity.version" 2>/dev/null | tr -d '[:space:]'
}
read_state() {  # echoes "<epoch> <version>"
    [ -f "$STATE" ] && cat "$STATE" 2>/dev/null || echo "0 -"
}
write_state() {  # $1 = version observed at the origin
    mkdir -p "$(dirname "$STATE")" 2>/dev/null || return 0
    echo "$(date +%s) $1" > "$STATE" 2>/dev/null || true
}

MODE="${1:---ensure}"
case "$MODE" in
    --ensure|--force|--check|--status|-h|--help) ;;
    *) echo "[update] unknown argument: $MODE (use --help)" >&2; exit 1;;
esac

if [ "$MODE" = "-h" ] || [ "$MODE" = "--help" ]; then
    sed -n '2,53p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

LOCAL_VER="$(local_version)"
if [ -z "$LOCAL_VER" ]; then
    say "FATAL: cannot read the local version ($SKILL_ROOT/assets/integrity.version) — installation not recognized"
    exit 1
fi

# --- MODE --status (no network) ----------------------------------------------
if [ "$MODE" = "--status" ]; then
    ST="$(read_state)"; ST_EPOCH="${ST%% *}"; ST_VER="${ST#* }"
    ST_HUMAN="never checked"
    [ "$ST_EPOCH" -gt 0 ] 2>/dev/null && ST_HUMAN="$(date -d "@$ST_EPOCH" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "@$ST_EPOCH") v$ST_VER"
    echo "=== UPDATE-SKILL STATUS ==="
    echo "installation : $SKILL_ROOT (v$LOCAL_VER)"
    echo "origin       : $ORIGIN"
    echo "install cmd  : npx skills add $INSTALL_SOURCE \${STELLAR_INSTALL_ARGS:---skill stellar-trail -a openclaw -y}"
    echo "last check   : $ST_HUMAN (debounce ${DEBOUNCE}s)"
    exit 0
fi

# --- DEBOUNCE (--ensure only; --force and --check bypass it) ------------------
if [ "$MODE" = "--ensure" ]; then
    ST="$(read_state)"; ST_EPOCH="${ST%% *}"; ST_VER="${ST#* }"
    NOW="$(date +%s)"
    if [ "$ST_EPOCH" -gt 0 ] 2>/dev/null && [ $((NOW - ST_EPOCH)) -lt "$DEBOUNCE" ]; then
        say "check skipped (debounce ${DEBOUNCE}s): last check $(date -d "@$ST_EPOCH" '+%H:%M' 2>/dev/null) saw v$ST_VER — local v$LOCAL_VER · use --force to check now"
        exit 0
    fi
fi

# --- REMOTE CHECK ------------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
    say "git is not available — update check skipped (offline-tolerant)"
    exit 0
fi
say "checking origin: $ORIGIN"
REMOTE_VER="$(timeout 25 git ls-remote --tags --refs --sort=-v:refname "$ORIGIN" 'v[0-9]*' 2>/dev/null \
    | head -1 | awk -F/ '{print $NF}' | sed 's/^v//' | tr -d '[:space:]')"
if [ -z "$REMOTE_VER" ]; then
    say "origin unreachable or has no release tags — skipped (offline-tolerant; cold boot is never blocked)"
    exit 0
fi
say "origin reports: v$REMOTE_VER · local: v$LOCAL_VER"

if [ "$REMOTE_VER" = "$LOCAL_VER" ]; then
    write_state "$REMOTE_VER"
    say "already latest (v$LOCAL_VER) — nothing to do"
    exit 0
fi
if version_lt "$REMOTE_VER" "$LOCAL_VER"; then
    write_state "$REMOTE_VER"
    say "REFUSED: origin v$REMOTE_VER is OLDER than local v$LOCAL_VER (downgrade protection — is this a dev install? push the release first)"
    exit 0
fi
if [ "$MODE" = "--check" ]; then
    say "UPDATE AVAILABLE: v$LOCAL_VER -> v$REMOTE_VER (--check mode: nothing installed — run --ensure or --force to install)"
    exit 0
fi

# ============================================================================
# INSTALL — the single flow: npx skills add <source>
# ============================================================================
INSTALL_ARGS="${STELLAR_INSTALL_ARGS:---skill stellar-trail -a openclaw -y}"
if ! command -v npx >/dev/null 2>&1; then
    say "npx is not available — cannot run the install command; run it manually when node tooling is present:"
    say "    npx skills add $INSTALL_SOURCE $INSTALL_ARGS"
    exit 0
fi

say "=== UPDATE v$LOCAL_VER -> v$REMOTE_VER START ==="
say "[1/4] single install flow: npx skills add $INSTALL_SOURCE $INSTALL_ARGS"
if ! timeout 600 npx --yes skills add "$INSTALL_SOURCE" $INSTALL_ARGS; then
    say "FAILED: the install command exited non-zero — update aborted. No fallback exists by design."
    say "Retry the same command manually: npx skills add $INSTALL_SOURCE $INSTALL_ARGS"
    exit 1
fi

say "[2/4] verify the installed version"
shopt -s nullglob
UPDATED_DIR=""
UPDATED=0
for INST in "$PROJECT/skills/stellar-trail" "$PROJECT"/skills/@*/stellar-trail; do
    [ -d "$INST" ] || continue
    INST_VER="$(cat "$INST/assets/integrity.version" 2>/dev/null | tr -d '[:space:]')"
    if [ "$INST_VER" = "$REMOTE_VER" ]; then
        UPDATED=1; UPDATED_DIR="$INST"
        say "       $INST: v$INST_VER — matches the origin tag"
    else
        say "       $INST: v${INST_VER:-unknown} (expected v$REMOTE_VER)"
    fi
done
shopt -u nullglob
if [ "$UPDATED" -ne 1 ]; then
    say "FAILED: no installation reports version v$REMOTE_VER after the install command finished."
    say "Retry manually: npx skills add $INSTALL_SOURCE $INSTALL_ARGS"
    exit 1
fi

say "[3/4] verify the package manifest of the updated installation"
if ( cd "$UPDATED_DIR" && LC_ALL=C sha256sum -c assets/integrity.sha256 --quiet >/dev/null 2>&1 ); then
    MANIFEST_N="$(wc -l < "$UPDATED_DIR/assets/integrity.sha256")"
    say "       manifest $MANIFEST_N/$MANIFEST_N entries OK"
else
    say "FAILED: manifest verification failed for $UPDATED_DIR — the installed package is inconsistent."
    say "Retry manually: npx skills add $INSTALL_SOURCE $INSTALL_ARGS"
    exit 1
fi

BOOTSTRAP_ARGS="${STELLAR_UPDATE_BOOTSTRAP_ARGS:---ensure --with-explorer --with-snapshot}"
say "[4/4] arm the persistence layer: bootstrap-sandbox.sh $BOOTSTRAP_ARGS"
if [ -f "$UPDATED_DIR/scripts/bootstrap-sandbox.sh" ]; then
    _bs_out="$(bash "$UPDATED_DIR/scripts/bootstrap-sandbox.sh" $BOOTSTRAP_ARGS 2>&1)"; _bs_rc=$?
    printf '%s\n' "$_bs_out" | tail -4 | sed 's/^/       /'
    [ "$_bs_rc" -eq 0 ] || say "       WARN: bootstrap returned $_bs_rc — the persistence layer keeps its previous state"
else
    say "       bootstrap-sandbox.sh not found in the updated installation — skipped"
fi

write_state "$REMOTE_VER"
say "=== UPDATE COMPLETE: v$LOCAL_VER -> v$REMOTE_VER ==="
say "The protocol now runs on v$REMOTE_VER; response banners carry the new version."
say "If a session is currently open, reload the skill body at the next session start."
exit 0
