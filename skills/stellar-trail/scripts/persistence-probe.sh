#!/usr/bin/env bash
# ============================================================================
# persistence-probe.sh — settle the packer-preservation question with ground truth
# stellar-trail · bundled asset (v5.7.9, audit-fix fix-5b)
#
# WHAT THIS SOLVES:
#   An unresolved contradiction sits at the base of every recovery path: the
#   platform spec says everything under the project root survives a container
#   recycle, while the v5.7.7 field evidence says the restore packer EXCLUDES
#   skills/. Both cannot be true — and until it is settled, the post-reset
#   checklist carries avoidable uncertainty (which layer do I verify first,
#   and with what expectation?). This probe records the on-disk layer state
#   into the packer-preserved area (.zscripts/ — preserved by contract) BEFORE
#   a reset and compares the disk against that marker AFTER. The delta IS the
#   ground truth, per layer, measured on YOUR sandbox — no documentation trust
#   required. The first --check after a real recycle closes the question.
#
# LAYERS PROBED (one verdict line each):
#   skills-tree  : skills/stellar-trail — existence, file count, SKILL.md hash
#   canonical    : .zscripts/stellar-trail-canonical — existence, file count,
#                  SKILL.md hash (the armed snapshot — packer-preserved)
#   memory       : memory/MEMORY.md + memory/SESSION-STATE.md + worklog.md —
#                  PRESENCE ONLY (content legitimately changes at checkpoints;
#                  a hash comparison would false-alarm on normal protocol work)
#
# VERDICTS:
#   SURVIVED  present and (for tree/canonical) hash-identical to the marker
#   WIPED     absent — a reset removed the layer
#   REGRESSED present but hash/file-count differs (mid-version marker, partial
#             restore, or a legitimate upgrade after marking — re-run --mark)
#
# Usage:
#   bash scripts/persistence-probe.sh --mark    # record the layer state now
#   bash scripts/persistence-probe.sh --check   # compare disk vs the marker
#   bash scripts/persistence-probe.sh --status  # print the raw marker
# Exit codes: 0 = all quiet · 1 = RESET DETECTED (>=1 layer WIPED/REGRESSED)
#             2 = usage · 3 = no marker on disk (run --mark first)
# Network: NONE — read-only vs disk plus one marker write; offline-safe.
# ============================================================================
set -u

PROBE_VERSION="1.0"

# --- project root: walk up from this script (same markers as relock-skill.sh)
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${STELLAR_PROJECT:-}"
if [ -z "$PROJECT" ]; then
    _d="$SELF_DIR"
    for _ in 1 2 3 4 5 6 7; do
        _d="$(dirname "$_d")"
        if [ -d "$_d/skills" ] || [ -d "$_d/download" ] || [ -d "$_d/.zscripts" ] \
           || [ -f "$_d/worklog.md" ]; then PROJECT="$_d"; break; fi
        [ "$_d" = "/" ] && break
    done
fi
PROJECT="${PROJECT:-$(dirname "$(dirname "$SELF_DIR")")}"

SKILL_DIR="$PROJECT/skills/stellar-trail"
CANON_DIR="$PROJECT/.zscripts/stellar-trail-canonical"
MEMORY_DIR="$PROJECT/memory"
WORKLOG="$PROJECT/worklog.md"
MARKER="$PROJECT/.zscripts/.persistence-probe"
REINSTALL_ONE_LINER='npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw -y && bash skills/stellar-trail/scripts/bootstrap-sandbox.sh --ensure'

usage() {
    cat <<USAGE
persistence-probe.sh v$PROBE_VERSION (stellar-trail) — reset-experiment instrument
  --mark    record the layer state (skills tree, canonical, memory) into $MARKER
  --check   compare the disk against the marker; per-layer verdicts + recovery
  --status  print the raw marker if present
Exit: 0 all quiet · 1 reset detected · 2 usage · 3 no marker
USAGE
}

# --- helpers -----------------------------------------------------------------
fcount() { [ -d "$1" ] && find "$1" -type f | wc -l || echo 0; }
fhash()  { [ -f "$1" ] && sha256sum "$1" | cut -d' ' -f1 || echo "-"; }
now()    { date '+%Y-%m-%d %H:%M:%S'; }

layer_state_skill()  { echo "files=$(fcount "$SKILL_DIR") hash=$(fhash "$SKILL_DIR/SKILL.md")"; }
layer_state_canon()  { echo "files=$(fcount "$CANON_DIR") hash=$(fhash "$CANON_DIR/SKILL.md")"; }

# memory layer: presence flags only (content churn is legitimate)
layer_state_memory() {
    _m="MEMORY.md:$([ -f "$MEMORY_DIR/MEMORY.md" ] && echo yes || echo no)"
    _s="SESSION-STATE.md:$([ -f "$MEMORY_DIR/SESSION-STATE.md" ] && echo yes || echo no)"
    _w="worklog.md:$([ -f "$WORKLOG" ] && echo yes || echo no)"
    echo "$_m $_s $_w"
}

cmd_mark() {
    mkdir -p "$PROJECT/.zscripts" 2>/dev/null || { echo "[persistence-probe] FAIL: cannot write $PROJECT/.zscripts"; exit 1; }
    cat > "$MARKER" <<MARK
probe_version=$PROBE_VERSION
marked=$(now)
skill_tree=$(layer_state_skill)
canonical=$(layer_state_canon)
memory=$(layer_state_memory)
MARK
    if [ $? -ne 0 ]; then echo "[persistence-probe] FAIL: marker write error"; exit 1; fi
    echo "[persistence-probe] marked $(now) — skill-tree: $(fcount "$SKILL_DIR") files · canonical: $(fcount "$CANON_DIR") files · memory: $(layer_state_memory)"
    echo "[persistence-probe] marker: $MARKER (packer-preserved area — survives the recycle under test)"
    echo "[persistence-probe] next reset: run --check BEFORE touching anything else"
    exit 0
}

marker_get() { # key -> value from the marker (first match)
    [ -f "$MARKER" ] && sed -n "s/^$1=//p" "$MARKER" | head -1
}

cmd_check() {
    if [ ! -f "$MARKER" ]; then
        echo "[persistence-probe] no marker at $MARKER — run --mark first (rc 3)"
        exit 3
    fi
    MARKED_AT="$(marker_get marked)"
    echo "[persistence-probe] marker: $MARKED_AT — comparing disk vs marker"
    RC=0

    # --- skills-tree layer
    M_TREE="$(marker_get skill_tree)"
    C_TREE="$(layer_state_skill)"
    if [ ! -d "$SKILL_DIR" ]; then
        echo "[persistence-probe] skills-tree : WIPED (skills/stellar-trail absent since the marker — MEASURED on this sandbox: the packer does NOT preserve skills/ here)"
        echo "[persistence-probe]   recover: bash .zscripts/dev.sh  (canonical intact) OR the GitHub one-liner (total loss)"
        RC=1
    elif [ "$M_TREE" = "$C_TREE" ]; then
        echo "[persistence-probe] skills-tree : SURVIVED ($C_TREE)"
    else
        echo "[persistence-probe] skills-tree : REGRESSED (marker '$M_TREE' vs now '$C_TREE' — version drift or partial restore; re-run --mark if expected)"
        RC=1
    fi

    # --- canonical layer
    M_CANON="$(marker_get canonical)"
    C_CANON="$(layer_state_canon)"
    if [ ! -d "$CANON_DIR" ]; then
        echo "[persistence-probe] canonical   : WIPED (.zscripts/stellar-trail-canonical absent — the packer contract itself is broken on this platform)"
        echo "[persistence-probe]   recover: $REINSTALL_ONE_LINER"
        RC=1
    elif [ "$M_CANON" = "$C_CANON" ]; then
        echo "[persistence-probe] canonical   : SURVIVED ($C_CANON)"
    else
        echo "[persistence-probe] canonical   : REGRESSED (marker '$M_CANON' vs now '$C_CANON'; re-run --mark if expected)"
        RC=1
    fi

    # --- memory layer (presence only)
    M_MEM="$(marker_get memory)"
    C_MEM="$(layer_state_memory)"
    if echo "$C_MEM" | grep -q 'no'; then
        echo "[persistence-probe] memory      : WIPED (one or more of MEMORY.md / SESSION-STATE.md / worklog.md absent — now: $C_MEM)"
        echo "[persistence-probe]   recover: bash skills/stellar-trail/scripts/bootstrap-sandbox.sh --ensure (re-scaffolds cold start; sealed context is lost)"
        RC=1
    else
        echo "[persistence-probe] memory      : SURVIVED (all present: $C_MEM)"
    fi

    if [ "$RC" -eq 0 ]; then
        echo "[persistence-probe] verdict     : ALL QUIET — no reset detected since $MARKED_AT (or the recycle preserved every layer)"
    else
        echo "[persistence-probe] verdict     : RESET DETECTED — resolve the WIPED/REGRESSED layers above, then re-run --mark"
    fi
    exit "$RC"
}

cmd_status() {
    if [ ! -f "$MARKER" ]; then
        echo "[persistence-probe] no marker at $MARKER — run --mark first (rc 3)"
        exit 3
    fi
    echo "[persistence-probe] marker: $MARKER"
    cat "$MARKER"
    exit 0
}

case "${1:-}" in
    --mark)   cmd_mark ;;
    --check)  cmd_check ;;
    --status) cmd_status ;;
    *)        usage; exit 2 ;;
esac
