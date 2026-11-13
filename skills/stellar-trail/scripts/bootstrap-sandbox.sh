#!/usr/bin/env bash
# ============================================================================
# bootstrap-sandbox.sh — arm the persistence layer for reset-prone sandboxes
# stellar-trail · persistence-layer arming (one command)
#
# WHAT THIS SOLVES (four confirmed failure modes of container sandboxes
# whose platform restores the project from an archive on every boot):
#   1. skill files vanish after a reset — the platform packer excludes
#      skills/ from the restore archive, wiping the installation each boot
#   2. explorer/services stay dead — no boot hook restarts processes that
#      the reset killed
#   3. the activation chain breaks — worklog.md is never created, so the
#      activation hook is missing and the skill is never loaded next session
#   4. the watchdog daemon dies silently at container lifecycle events
#      (freeze/thaw, session-start process reaping — observed with a CLEAR
#      stop-flag and NO boot in between) and nothing between boots revives
#      it: the explorer has three revival paths (boot, watcher, deploy-time
#      below), the watcher itself had only one (boot). The same wild
#      behavior leaves worklog sections appended WITHOUT their activation
#      hook line — the tail, the one part the next session reads, loses the
#      directive. Fixed by step 10b (worklog tail guard) + step 11b (watcher
#      daemon ensure) — both run on EVERY bootstrap invocation
#
# THE SOLUTION (one proven path per module — no redundant fallbacks):
#   core     : copy the live installation to the canonical snapshot at
#              .zscripts/stellar-trail-canonical/ (the platform packer PRESERVES
#              download/ + .zscripts/ + memory/ + worklog.md — verified
#              against the packer's own archive), then install
#              .zscripts/dev.sh (boot hook on the /start.sh contract) which
#              restores skills/stellar-trail from the canonical snapshot on
#              EVERY boot, plus .zscripts/watcher.sh (runtime watchdog
#              daemon v2.3: explorer health, release-file guard,
#              installation integrity checks, archive refresh, compliance
#              alarm, silent-work sentinel + ALERT surface, periodic
#              compliance audit; started by dev.sh at boot AND by this
#              script at every run — step 11b — so a silent daemon death
#              heals at the next cold boot, not only at the next container
#              boot).
#   explorer : installs .zscripts/{explorer.sh,explorer.py,explorer-ui/} and
#              an --ensure step in dev.sh — AUTO-ENABLED when
#              the payload ships in the install tree (--with-explorer forces
#              on; --without-explorer opts out) — plus, a
#              DEPLOY-TIME activation call at the end of every
#              bootstrap run (the running server is checked against the
#              just-deployed code; explorer.sh v1.6 does the content-stamp
#              freshness restart — closes the upgrade-path gap where a
#              first-hop left the old process serving).
#   snapshot : installs .zscripts/repo-snapshot.sh and an --apply-auto step in
#              dev.sh (platforms with /home/sync) — AUTO-ENABLED
#              when the payload ships (--with-snapshot forces on;
#              --without-snapshot opts out).
#   hooks    : seeds CLAUDE.md + AGENTS.md at the PROJECT ROOT from
#              assets/harness-hooks/ — create-if-absent + refresh-if-byte-
#              identical (v5.5.1): a root file whose sha256 is listed in
#              assets/harness-hooks/seed-hashes.txt is an UNMODIFIED managed
#              seed — it tracks the template across releases (an old-version
#              seed is refreshed to current); a registry miss = a user file
#              that is NEVER overwritten — AUTO-ENABLED when the payload
#              ships (--with-harness-hooks forces on;
#              --without-harness-hooks opts out AND removes seeds still
#              byte-identical to ANY shipped template version — an edited
#              file is the user's and is never touched). Guaranteed-context
#              activation for harnesses that auto-read project-root files at
#              session start (Claude Code reads CLAUDE.md; AGENTS.md is the
#              cross-CLI standard); dev.sh step 7 re-seeds at boot
#              (project-root files are NOT in the packer preserve list).
#
# IMPORTANT — this is persistence, not installation:
#   the canonical snapshot is a copy of what is ALREADY installed. It never
#   fetches anything and never resolves versions. Installing or upgrading
#   the skill happens through exactly one flow (see SKILL.md):
#       npx skills add hoshiyomiX/stellar-trail
#
# DESIGN PRINCIPLES:
#   - One path per module: the seed source is the installation directory
#     this script runs from (self-locating, offline, no version negotiation).
#   - Idempotent: safe to run repeatedly (--ensure); writes only when
#     content differs; NEVER overwrites memory/, worklog.md, or a dev.sh
#     that bootstrap does not own.
#
# Usage:
#   bash scripts/bootstrap-sandbox.sh                     # install core + auto-enable present modules
#   bash scripts/bootstrap-sandbox.sh --ensure            # idempotent (cold-boot path; state + auto-detect)
#   bash scripts/bootstrap-sandbox.sh --with-explorer     # force the explorer module on
#   bash scripts/bootstrap-sandbox.sh --with-snapshot     # force the snapshot module on
#   bash scripts/bootstrap-sandbox.sh --without-explorer  # opt OUT of the auto-enabled explorer module
#   bash scripts/bootstrap-sandbox.sh --without-snapshot  # opt OUT of the auto-enabled snapshot module
#   bash scripts/bootstrap-sandbox.sh --with-harness-hooks    # force the harness-hooks module on
#   bash scripts/bootstrap-sandbox.sh --without-harness-hooks # opt OUT of harness hooks (unmodified seeds removed)
#   bash scripts/bootstrap-sandbox.sh --status            # read-only report
#   bash scripts/bootstrap-sandbox.sh --project-dir PATH  # override project-root detection
#   bash scripts/bootstrap-sandbox.sh --force-devsh       # ALIAS since v5.7.6: foreign-dev.sh takeover is the DEFAULT on every run
#
# EXIT: 0 = armed/healthy · 1 = failed (see the last [bootstrap] line)
# ============================================================================
set -u

# ---------------------------------------------------------------------------
# 0. SELF-LOCATE — this script lives in <skill-root>/scripts/; project = walk-up
# ---------------------------------------------------------------------------
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(dirname "$SELF_DIR")"

BOOT_VERSION="$(cat "$SKILL_ROOT/assets/integrity.version" 2>/dev/null || echo "unknown")"
STATE_MARKER="# BOOTSTRAP-GENERATED: stellar-trail bootstrap-sandbox.sh"
JUNK_DIRS=(-name '__pycache__' -o -name '.DS_Store')
JUNK_FILES=(-name '*.pyc' -o -name '*.pyo')

log() { echo "[bootstrap] $*"; }
die() { echo "[bootstrap] FAILED: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. ARGUMENTS
# ---------------------------------------------------------------------------
MODE="install"          # install | status
ENSURE=0
FORCE_DEVSH=0
OPT_PROJECT=""
MODULE_ARGS=()
MODULE_OFF=()    # --without-* opt-outs — also disarm previously armed modules

for arg in "$@"; do
    case "$arg" in
        --ensure)        ENSURE=1 ;;
        --status)        MODE="status" ;;
        --with-explorer)   MODULE_ARGS+=("explorer") ;;
        --with-snapshot)   MODULE_ARGS+=("snapshot") ;;
        --without-explorer) MODULE_OFF+=("explorer") ;;
        --without-snapshot) MODULE_OFF+=("snapshot") ;;
        --with-harness-hooks)   MODULE_ARGS+=("hooks") ;;
        --without-harness-hooks) MODULE_OFF+=("hooks") ;;
        --force-devsh)   FORCE_DEVSH=1 ;;
        --project-dir)   : ;;   # value consumed from the next argument below
        --project-dir=*) OPT_PROJECT="${arg#*=}" ;;
        -h|--help)       sed -n '2,49p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) ;;
    esac
done
# capture the two-token form --project-dir PATH
prev=""
for arg in "$@"; do
    if [ "$prev" = "--project-dir" ]; then OPT_PROJECT="$arg"; fi
    prev="$arg"
done

# ---------------------------------------------------------------------------
# 2. PROJECT-ROOT DETECTION — walk up at most 6 levels, or --project-dir
#    markers: skills/ · download/ · .zscripts/ · worklog.md · package.json
# ---------------------------------------------------------------------------
find_project_root() {
    local d="$SKILL_ROOT"
    for _ in 1 2 3 4 5 6; do
        d="$(dirname "$d")"
        if [ -d "$d/skills" ] || [ -d "$d/download" ] || [ -d "$d/.zscripts" ] \
           || [ -f "$d/worklog.md" ] || [ -f "$d/package.json" ]; then
            echo "$d"; return 0
        fi
        [ "$d" = "/" ] && break
    done
    return 1
}

if [ -n "$OPT_PROJECT" ]; then
    PROJECT="$(cd "$OPT_PROJECT" 2>/dev/null && pwd)" || die "invalid --project-dir: $OPT_PROJECT"
else
    PROJECT="$(find_project_root)" || die "project root not detected from $SKILL_ROOT (no skills/ · download/ · .zscripts/ · worklog.md · package.json within 6 levels up). Use --project-dir <path>."
fi
[ "$PROJECT" = "/" ] && die "project root detected as '/' — refusing."
[ -w "$PROJECT" ] || die "project root is not writable: $PROJECT"

CANON="$PROJECT/.zscripts/stellar-trail-canonical"
ZDIR="$PROJECT/.zscripts"
STATE_FILE="$ZDIR/bootstrap.state"

# boot.log ledger writer — bootstrap events that must outlive the session
# (stdout log() vanishes with the terminal; the boot ledger persists).
# Used for the foreign-dev.sh AUTO-TAKEOVER events (Task 78 audit R2; takeover
# is the DEFAULT since v5.7.6 / Task 81 — owner order "Basmi rantai dev.sh
# ASING": the foreign copy is backed up, never destroyed).
blog() {
    printf '[%s] [bootstrap] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$ZDIR/boot.log" 2>/dev/null || true
}
MEMORY_DIR="$PROJECT/memory"
WORKLOG="$PROJECT/worklog.md"
MODULES_FILE="/tmp/bootstrap-modules.$$"

# ---------------------------------------------------------------------------
# 3. MODULE STATE — previous state + new modules; persisted after success
#    state format: one line per key: v=<version> m=<module,...> d=<date>
# ---------------------------------------------------------------------------
load_state_modules() {
    [ -f "$STATE_FILE" ] || return 0
    local m; m="$(sed -n 's/^m=//p' "$STATE_FILE" 2>/dev/null)"
    [ -n "$m" ] || return 0
    [ "$m" = "-" ] && return 0   # "no modules" sentinel — not a module name
    local mod
    for mod in ${m//,/ }; do echo "$mod" >> "$MODULES_FILE"; done
}
add_module() { echo "$1" >> "$MODULES_FILE"; }
has_module() { grep -qx -- "$1" "$MODULES_FILE" 2>/dev/null; }
sort_modules() { sort -u "$MODULES_FILE" 2>/dev/null > "${MODULES_FILE}.s" && mv "${MODULES_FILE}.s" "$MODULES_FILE" 2>/dev/null; }

: > "$MODULES_FILE" 2>/dev/null || die "tmp not writable"
load_state_modules
for m in "${MODULE_ARGS[@]:-}"; do [ -n "$m" ] && add_module "$m"; done
sort_modules

# --- module auto-enable : a module whose payload ships
#     in the install tree is armed by DEFAULT. The consumer report
#      showed the fresh-install trap: plain --ensure armed no
#     modules, so the explorer stayed unmaintained after any reset. Explicit
#     opt-out: --without-explorer / --without-snapshot — these also disable
#     a module armed by a previous run.
drop_module() {  # $1=module — remove it from MODULES_FILE
    grep -vx -- "$1" "$MODULES_FILE" > "${MODULES_FILE}.d" 2>/dev/null || true
    mv "${MODULES_FILE}.d" "$MODULES_FILE" 2>/dev/null
}
module_off() { printf '%s\n' ${MODULE_OFF[@]+"${MODULE_OFF[@]}"} | grep -qx -- "$1"; }

# seed_known <file> <name> — TRUE when <file>'s sha256 is a REGISTERED template
# version for <name> in assets/harness-hooks/seed-hashes.txt (an unmodified
# managed seed, possibly of an older release — any user edit breaks the hash;
# v5.5.1). Registry absent (pre-v5.5.1 install) = FALSE = safe old behavior.
seed_known() {
    [ -f "$1" ] || return 1
    _sk_reg="$SKILL_ROOT/assets/harness-hooks/seed-hashes.txt"
    [ -f "$_sk_reg" ] || return 1
    _sk_h="$(sha256sum "$1" 2>/dev/null | awk '{print $1}')"
    [ -n "$_sk_h" ] || return 1
    awk -v h="$_sk_h" -v f="$2" \
        '$0 !~ /^#/ && NF >= 2 && $1 == h && $2 == f {found=1} END {exit found ? 0 : 1}' "$_sk_reg"
}
AUTO_ENABLED=""
if ! module_off explorer && [ -f "$SKILL_ROOT/assets/explorer/explorer.sh" ] && ! has_module explorer; then
    add_module explorer; AUTO_ENABLED="explorer"
fi
if ! module_off snapshot && [ -f "$SKILL_ROOT/scripts/snapshot-repo.sh" ] && ! has_module snapshot; then
    add_module snapshot; AUTO_ENABLED="${AUTO_ENABLED:+$AUTO_ENABLED }snapshot"
fi
if ! module_off hooks && [ -f "$SKILL_ROOT/assets/harness-hooks/CLAUDE.md" ] && ! has_module hooks; then
    add_module hooks; AUTO_ENABLED="${AUTO_ENABLED:+$AUTO_ENABLED }hooks"
fi
for m in ${MODULE_OFF[@]+"${MODULE_OFF[@]}"}; do drop_module "$m"; done
sort_modules
[ -n "$AUTO_ENABLED" ] && echo "[bootstrap] auto-enable: $AUTO_ENABLED — payload present in the install tree (modules arm by default; opt out with --without-explorer / --without-snapshot / --without-harness-hooks)"

MODULE_LIST="$(tr '\n' ',' < "$MODULES_FILE" | sed 's/,$//')"
[ -z "$MODULE_LIST" ] && MODULE_LIST="-"

# ---------------------------------------------------------------------------
# 4. UTILITY — write-only-when-different (idempotent)
# ---------------------------------------------------------------------------
write_if_changed() {  # $1=source file  $2=target  → echoes "wrote"|"kept"
    local src="$1" dst="$2"
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then echo "kept"; return 0; fi
    mkdir -p "$(dirname "$dst")"
    cp -p "$src" "$dst" && echo "wrote"
}

prune_junk() {  # $1=root tree — drop __pycache__/*.pyc/.DS_Store
    find "$1" \( -type d \( -name '__pycache__' -o -name '.DS_Store' \) -exec rm -rf {} + \) 2>/dev/null
    find "$1" \( -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete \) 2>/dev/null
    return 0
}

# ---------------------------------------------------------------------------
# 5. MODE --status — read-only, never changes anything
# ---------------------------------------------------------------------------
if [ "$MODE" = "status" ]; then
    echo "=== BOOTSTRAP STATUS (v$BOOT_VERSION) ==="
    echo "verdict    : $([ -f "$ZDIR/dev.sh" ] && echo "ARMED" || echo 'NOT ARMED — run: bash skills/stellar-trail/scripts/bootstrap-sandbox.sh --ensure')"
    echo "marker     : $([ -f "$SKILL_ROOT/NOT-ARMED.md" ] && echo 'NOT-ARMED.md present (install landed; arming pending)' || echo 'absent (armed, or a pre-v5.7.7 install)')"
    echo "skill root : $SKILL_ROOT"
    echo "project    : $PROJECT"
    echo "modules    : ${MODULE_LIST}"
    if [ -d "$CANON" ]; then
        echo -n "canonical  : $(find "$CANON" -type f | wc -l) files"
        if (cd "$CANON" && sha256sum -c assets/integrity.sha256 --quiet >/dev/null 2>&1); then
            echo " · manifest OK"
        else
            echo " · manifest FAILED/missing"
        fi
    else
        echo "canonical  : NOT CREATED YET (not seeded)"
    fi
    if [ -f "$ZDIR/dev.sh" ]; then
        if head -n 2 "$ZDIR/dev.sh" | grep -qF "$STATE_MARKER"; then
            echo "dev.sh     : bootstrap-generated ($(sed -n 's/^# .*modules: //p' "$ZDIR/dev.sh" | head -n 1))"
        else
            echo "dev.sh     : present but NOT owned by bootstrap (foreign — AUTO-TAKEOVER at the next --ensure; backup dev.sh.foreign.bak)"
        fi
    else
        echo "dev.sh     : NOT INSTALLED"
    fi
    has_module explorer && {
        for f in explorer.sh explorer.py explorer-ui/index.html; do
            echo "explorer   : .zscripts/$f $([ -f "$ZDIR/$f" ] && echo OK || echo MISSING)"
        done
    }
    has_module snapshot && echo "snapshot   : .zscripts/repo-snapshot.sh $([ -f "$ZDIR/repo-snapshot.sh" ] && echo OK || echo MISSING)"
    if has_module hooks; then
        for f in CLAUDE.md AGENTS.md; do
            if [ -f "$PROJECT/$f" ]; then
                if cmp -s "$SKILL_ROOT/assets/harness-hooks/$f" "$PROJECT/$f"; then
                    st="SEEDED (managed)"
                elif seed_known "$PROJECT/$f" "$f"; then
                    st="STALE SEED (managed — next --ensure refreshes it)"
                else
                    st="PRESENT (user-owned — never touched)"
                fi
            else
                st="MISSING"
            fi
            echo "hooks      : $PROJECT/$f $st"
        done
    fi
    echo "watcher    : .zscripts/watcher.sh $([ -f "$ZDIR/watcher.sh" ] && echo OK || echo 'NOT PRESENT (core)')"
    echo "memory     : $([ -f "$MEMORY_DIR/SESSION-STATE.md" ] && echo "scaffolded/active ($MEMORY_DIR)" || echo "NOT CREATED")"
    echo "worklog    : $([ -f "$WORKLOG" ] && { grep -q '⚡ACTIVATE' "$WORKLOG" && echo "present + activation hook OK" || echo "present WITHOUT activation hook"; } || echo "NOT CREATED")"
    echo "state file : $([ -f "$STATE_FILE" ] && cat "$STATE_FILE" | tr '\n' ' ' || echo "not created yet")"
    rm -f "$MODULES_FILE"
    exit 0
fi

# ---------------------------------------------------------------------------
# 6. CORE MODULE A — SEED THE CANONICAL SNAPSHOT: live install → .zscripts/stellar-trail-canonical/
#    staging + compare + swap (idempotent; junk pruned from the snapshot)
# ---------------------------------------------------------------------------
STAGE="$(mktemp -d "$PROJECT/.bootstrap-stage.XXXXXX")" || die "mktemp failed"
trap 'rm -rf "$STAGE" "$MODULES_FILE"' EXIT

log "seed canonical snapshot: $SKILL_ROOT → $CANON"
mkdir -p "$STAGE/stellar-trail"
cp -a "$SKILL_ROOT/." "$STAGE/stellar-trail/" || { die "failed to copy the skill tree from $SKILL_ROOT"; }
prune_junk "$STAGE/stellar-trail"

if [ -d "$CANON" ]; then
    prune_junk "$CANON"
    if diff -rq "$CANON" "$STAGE/stellar-trail" >/dev/null 2>&1; then
        log "canonical snapshot already fresh (0 changes)"
    else
        rm -rf "${CANON}.old"
        mv "$CANON" "${CANON}.old" && mv "$STAGE/stellar-trail" "$CANON" \
            || die "canonical swap failed (backup kept at: ${CANON}.old)"
        rm -rf "${CANON}.old"
        log "canonical snapshot refreshed ($(find "$CANON" -type f | wc -l) files)"
    fi
else
    mkdir -p "$(dirname "$CANON")"
    mv "$STAGE/stellar-trail" "$CANON" || die "failed to write the canonical snapshot"
    log "canonical snapshot CREATED ($(find "$CANON" -type f | wc -l) files)"
fi

# verify the canonical snapshot against the release manifest (shipped with the package)
if (cd "$CANON" && sha256sum -c assets/integrity.sha256 --quiet >/dev/null 2>&1); then
    log "manifest verification: OK"
    VERIFY="manifest OK"
else
    BAD_N=$(cd "$CANON" && sha256sum -c assets/integrity.sha256 2>/dev/null | grep -c 'FAILED' || true)
    log "WARN: manifest mismatch ($BAD_N entries) — the snapshot is used as-is (single path: this copy of the installation IS the source)"
    VERIFY="manifest MISMATCH ($BAD_N)"
fi

# ---------------------------------------------------------------------------
# 7. CORE MODULE B — GENERATE .zscripts/dev.sh (boot hook on the /start.sh contract)
#    One restore path: canonical snapshot → skills/stellar-trail (manifest check
#    + version gate: a live installation NEWER than the snapshot is never
#    downgraded by the cache replay — validated by lifecycle test T3).
#    A bootstrap-owned dev.sh is marked. A FOREIGN dev.sh is AUTO-NEUTRALIZED
#    (v5.7.6, Task 81, owner order "Basmi rantai dev.sh ASING, TFM harus
#    survive dan persistent"): the foreign copy is backed up to
#    dev.sh.foreign.bak (latest only) and the bootstrap hook takes the boot
#    chain — plain --ensure, no flag. --force-devsh stays as an accepted
#    alias (no behavioral difference; the pre-v5.7.6 SKIP branch is dead).
#    Install is ATOMIC (tmp + mv in the same directory): a boot mid-run keeps
#    executing the old inode — no torn-script risk.
# ---------------------------------------------------------------------------
build_devsh() {
    cat <<'DEVSH_HEAD'
#!/usr/bin/env bash
DEVSH_HEAD
    echo "$STATE_MARKER v$BOOT_VERSION (modules: $MODULE_LIST)"
    cat <<'DEVSH_BODY'
# dev.sh — PERSISTENT BOOT HOOK (run automatically by /start.sh on every boot)
# GENERATED BY bootstrap-sandbox.sh — do not edit by hand; regenerate with
#   bash .zscripts/stellar-trail-canonical/scripts/bootstrap-sandbox.sh [--with-*]
#
# ONE PATH PER MODULE (no redundant fallbacks):
#   1. SKILL RESTORE : skills/stellar-trail is verified against the canonical
#      snapshot .zscripts/stellar-trail-canonical (SHA-256 manifest); broken/missing →
#      restored from the snapshot. A live installation NEWER than the
#      snapshot is never downgraded (version gate — it stays; the snapshot
#      catches up at the next bootstrap --ensure). The snapshot is a copy of
#      the installation at bootstrap time — what you installed is what gets
#      preserved. Local cache replay: nothing is fetched, no versions resolved.
#   2. FULLSTACK GUARD: the presence of this dev.sh REPLACES the default boot
#      flow of /start.sh — that flow is replicated here so a web project
#      keeps running.
#   3. TIDY download/ : eval/audit artifacts are moved to archive/ (undoable).
#   4. WATCHER --ensure : start the runtime watchdog daemon when it is down
#      (explorer health + release-file guard + installation integrity
#      checks + archive refresh + compliance alarm).
DEVSH_BODY
    has_module explorer && cat <<'DEVSH_EXPL'
#   5. EXPLORER --ensure : start the explorer when it is down + refresh drift.
DEVSH_EXPL
    has_module snapshot && cat <<'DEVSH_SNAP'
#   6. SNAPSHOT --apply-auto : refresh the platform restore archive (own debounce).
DEVSH_SNAP
    has_module hooks && cat <<'DEVSH_HOOKSHDR'
#   7. HARNESS HOOKS re-seed : project-root CLAUDE.md/AGENTS.md (create-if-absent + refresh-if-byte-identical).
DEVSH_HOOKSHDR
    cat <<'DEVSH_TAILGUARDHDR'
#   8. WORKLOG TAIL GUARD : append-only — keep the activation directive as
#      the last line of worklog.md (recovery net for hook-less sections).
DEVSH_TAILGUARDHDR
    cat <<'DEVSH_VARS'

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOAD="$PROJECT/download"
ARCHIVE="$PROJECT/archive"
BOOTLOG="$PROJECT/.zscripts/boot.log"
LOCKDIR="/tmp/dev-sh.lock"
CANON="$PROJECT/.zscripts/stellar-trail-canonical"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $*" >> "$BOOTLOG"; echo "[dev.sh] $*"; }

if [ "$1" = "--status" ]; then
    echo "=== project: $PROJECT ==="
    echo "=== download/ (top level) ==="; ls -1 "$DOWNLOAD" 2>/dev/null
    echo "=== boot.log (last 15 lines) ==="; tail -15 "$BOOTLOG" 2>/dev/null || echo "(none yet)"
    exit 0
fi

# double-run protection (10-minute lock, stale locks are taken over)
if [ -d "$LOCKDIR" ]; then
    if [ -z "$(find "$LOCKDIR" -maxdepth 0 -mmin -10 2>/dev/null)" ]; then
        rm -rf "$LOCKDIR"
    else
        log "lock active, skipping duplicate run"; exit 0
    fi
fi
mkdir "$LOCKDIR" 2>/dev/null || exit 0
trap 'rm -rf "$LOCKDIR"' EXIT
log "dev.sh (bootstrap) start"
DEVSH_VARS

    cat <<'DEVSH_RESTORE'

# --- 1. SKILL RESTORE (one path: canonical snapshot → live installation) ----
# version_lt <a> <b> — true when a < b on loose x.y.z patterns.
# Controlled copy (change both together; sibling: scripts/update-skill.sh) —
# the standalone-helper doctrine forbids a shared library here.
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
if [ -f "$CANON/SKILL.md" ] && [ -f "$CANON/assets/integrity.sha256" ]; then
    CANON_VER="$(tr -d '[:space:]' < "$CANON/assets/integrity.version" 2>/dev/null)"
    shopt -s nullglob
    for LIVE in "$PROJECT/skills/stellar-trail" "$PROJECT"/skills/@*/stellar-trail; do
        # version gate (no downgrades): a live installation that is NEWER than
        # the snapshot is left alone — a failed upgrade mid-write is caught by
        # the watcher integrity alarm instead (remediation: the install command)
        LIVE_VER="$(tr -d '[:space:]' < "$LIVE/assets/integrity.version" 2>/dev/null)"
        if [ -n "$LIVE_VER" ] && [ -n "$CANON_VER" ] && version_lt "$CANON_VER" "$LIVE_VER"; then
            log "SKILL RESTORE: skip ${LIVE#"$PROJECT"/} — live v$LIVE_VER is newer than the snapshot v$CANON_VER (no downgrades; the snapshot catches up at the next bootstrap --ensure)"
            continue
        fi
        if [ ! -f "$LIVE/SKILL.md" ] \
           || ! (cd "$LIVE" && sha256sum -c "$CANON/assets/integrity.sha256" --quiet >/dev/null 2>&1); then
            rm -rf "$LIVE"
            mkdir -p "$(dirname "$LIVE")"
            if cp -a "$CANON" "$LIVE"; then
                log "SKILL RESTORE: ${LIVE#"$PROJECT"/} restored from the canonical snapshot"
            else
                log "WARN: failed to restore ${LIVE#"$PROJECT"/} from the canonical snapshot"
            fi
        fi
    done
    shopt -u nullglob
    # canonical hygiene (owner order #2, Task 68, v5.7.0): when the live tree
    # is HEALTHY (manifest OK), the snapshot must mirror it exactly —
    # snapshot-ONLY files are stale-resurrection junk (incident 2026-11-04:
    # the platform packer restored a pre-prune download/, leaving 14 v3.6.5-era
    # extras one restore away from the live tree). Delete them at every boot.
    for LIVE in "$PROJECT/skills/stellar-trail" "$PROJECT"/skills/@*/stellar-trail; do
        [ -f "$LIVE/SKILL.md" ] || continue
        if (cd "$LIVE" && sha256sum -c "$CANON/assets/integrity.sha256" --quiet >/dev/null 2>&1); then
            _hyg=0
            while IFS= read -r _extra; do
                [ -n "$_extra" ] && rm -f "$CANON/$_extra" && _hyg=$((_hyg+1))
            done < <(comm -13 \
                <(cd "$LIVE"  2>/dev/null && find . -type f | sort) \
                <(cd "$CANON" 2>/dev/null && find . -type f | sort))
            [ "$_hyg" -eq 0 ] || log "CANONICAL HYGIENE: pruned $_hyg stale snapshot-only file(s)"
        fi
        break   # the first PRESENT live tree is the reference (healthy = prune;
                # unhealthy = leave for bootstrap --ensure's seed swap)
    done
fi

# v5.7.4 canonical relocation (owner order 2026-11-12 — default location
# .zscripts/, download/ reserved for owner-requested file deliveries): the
# canonical snapshot lives at .zscripts/stellar-trail-canonical/; a stale
# packer archive can resurrect the legacy download/stellar-trail/ copy (the
# 2026-11-02 partial-stale class) — prune it at every boot.
if [ -d "$DOWNLOAD/stellar-trail" ]; then
    rm -rf "$DOWNLOAD/stellar-trail"
    log "LEGACY CANONICAL PRUNE: removed download/stellar-trail (canonical lives at .zscripts/stellar-trail-canonical since v5.7.4)"
fi

# v5.7.7 NOT-ARMED MARKER HYGIENE (Task 82 — field-test R1): this dev.sh
# existing IS the armed state; a NOT-ARMED.md resurrected into the live tree
# or the snapshot (packer partial-stale class, 2026-11-02/2026-11-13) would
# signal the opposite. Retire it at every boot (state file, never in the
# manifest — removing it cannot break any integrity check).
if [ -f "$PROJECT/skills/stellar-trail/NOT-ARMED.md" ] || [ -f "$CANON/NOT-ARMED.md" ]; then
    rm -f "$PROJECT/skills/stellar-trail/NOT-ARMED.md" "$CANON/NOT-ARMED.md"
    for L in "$PROJECT"/skills/@*/stellar-trail/NOT-ARMED.md; do rm -f "$L"; done
    log "NOT-ARMED MARKER: retired (boot hygiene — this boot hook IS the armed state)"
fi
DEVSH_RESTORE

    cat <<'DEVSH_FULLSTACK'

# --- 2. FULLSTACK GUARD ------------------------------------------------------
# (v5.7.6, Task 81 owner order "anti package.json/fullstack-dev"): this
# guard KEEPS replicating the platform bun flow (the existence of this
# dev.sh REPLACES /start.sh's default flow, so the web project must be
# started from here), but the explorer NO LONGER STANDS DOWN for a
# package.json — it binds by PORT REALITY (explorer.sh v1.6). To keep an
# ACTIVE web project on :3000 (the public preview via ingress :81), the
# web flow gets a short head start before the explorer claims a free
# :3000; a dead/stale scaffold leaves :3000 free and the explorer takes
# the preview after the settle window.
if [ -f "$PROJECT/package.json" ]; then
    log "package.json detected -> replicating the standard fullstack boot flow"
    cd "$PROJECT" || true
    bun install        >> "$BOOTLOG" 2>&1 || log "WARN: bun install failed"
    bun run db:push    >> "$BOOTLOG" 2>&1 || log "WARN: db:push failed"
    nohup bun run dev  >> "$BOOTLOG" 2>&1 &
    log "Next.js dev server started in the background"
    for d in "$PROJECT"/mini-services/*/; do
        [ -f "${d}package.json" ] || continue
        (
            cd "$d" || exit 0
            bun install >> "$BOOTLOG" 2>&1
            nohup bun run dev >> "$BOOTLOG" 2>&1 &
        )
        log "mini-service started: $d"
    done
    # v5.7.6 settle wait: only when :3000 is still free (a fresh-boot race);
    # when a web server already holds :3000 there is nothing to wait for.
    # An active project claims it within seconds (early exit); a dead
    # scaffold leaves it free and the explorer takes the preview after 15s.
    if ! (exec 3<>/dev/tcp/127.0.0.1/3000) 2>/dev/null; then
        _sw=0
        _claimed=0
        while [ "$_sw" -lt 15 ]; do
            sleep 1
            _sw=$((_sw+1))
            if (exec 3<>/dev/tcp/127.0.0.1/3000) 2>/dev/null; then
                log "fullstack settle: :3000 claimed by the web project after ${_sw}s — the explorer will take a fallback port"
                _claimed=1
                break
            fi
        done
        if [ "$_claimed" = 0 ]; then
            log "fullstack settle: :3000 still free after 15s — the explorer claims the preview (dead/stale scaffold)"
        fi
    fi
fi
DEVSH_FULLSTACK

    cat <<'DEVSH_TIDY'

# --- 3. TIDY download/ (idempotent; undo with: mv archive/<file> download/) --
tidy_download() {
    [ -d "$DOWNLOAD" ] || return 0
    mkdir -p "$ARCHIVE"
    cd "$DOWNLOAD" || return 0
    local moved=0 item dest
    for item in *; do
        [ -e "$item" ] || continue
        case "$item" in
            README.md|*.md|*.skill|*.pdf|*.docx|*.xlsx|*.pptx|*.csv|*.png|*.jpg|*.jpeg|*.gif|*.zip|stellar-trail)
                continue ;;
        esac
        case "$item" in
            *-eval|*-results.json|*-audit-results.json|audit-results.json|*-cover.html|workflow-guardian|memory-guardian)
                dest="$ARCHIVE/$item"
                [ -e "$dest" ] && dest="$ARCHIVE/${item}.$(date +%Y%m%d%H%M%S)"
                mv -- "$item" "$dest" 2>>"$BOOTLOG" && moved=$((moved+1)) ;;
        esac
    done
    log "tidy done: $moved item(s) moved to archive/"
    return 0
}
tidy_download
DEVSH_TIDY

    cat <<'DEVSH_WATCH'

# --- 4. WATCHDOG DAEMON --ensure (v2.0, part of core) ------------------------
#     no-op when already running; double-fork orphan otherwise. Loop of 30s:
#     explorer health + auto-restart, release-file guard (restore only from a
#     healthy local installation), installation integrity checks (~10 min,
#     verify-only), archive refresh (~15 min), compliance sentinel (~2 min).
if [ -f "$PROJECT/.zscripts/watcher.sh" ]; then
    bash "$PROJECT/.zscripts/watcher.sh" --ensure >> "$BOOTLOG" 2>&1 \
        || log "WARN: watcher --ensure failed"
fi
DEVSH_WATCH

    if has_module explorer; then
        cat <<'DEVSH_EXPL2'

# --- 5. TASK FILES EXPLORER --ensure ------------------------------------------
if [ -f "$PROJECT/.zscripts/explorer.sh" ]; then
    _ex_out="$(bash "$PROJECT/.zscripts/explorer.sh" --ensure 2>&1)"; _ex_rc=$?
    if [ -n "$_ex_out" ]; then printf '%s\n' "$_ex_out" >> "$BOOTLOG"; fi
    _ex_v="$(printf '%s\n' "$_ex_out" | grep -v '^[[:space:]]*$' | tail -n 1)"
    if [ "$_ex_rc" -eq 0 ]; then
        log "explorer --ensure: OK — ${_ex_v:-alive (no diagnostics)}"
    else
        log "WARN: explorer --ensure failed (rc=$_ex_rc) — ${_ex_v:-no diagnostics}"
    fi
fi
DEVSH_EXPL2
    fi

    if has_module snapshot; then
        cat <<'DEVSH_SNAP2'

# --- 6. PLATFORM SNAPSHOT --apply-auto (own debounce + cooldown) --------------
if [ -f "$PROJECT/.zscripts/repo-snapshot.sh" ]; then
    WMG_PROJECT="$PROJECT" bash "$PROJECT/.zscripts/repo-snapshot.sh" --apply-auto \
        >> "$BOOTLOG" 2>&1 || log "WARN: archive refresh failed"
fi
DEVSH_SNAP2
    fi

    if has_module hooks; then
        cat <<'DEVSH_HOOKS'

# --- 7. HARNESS HOOKS re-seed (create-if-absent + refresh-if-byte-identical; --
#     project-root files are NOT in the packer preserve list, so boot-time
#     re-seeding keeps them alive) ---
for _hh in CLAUDE.md AGENTS.md; do
    _hsrc="$PROJECT/.zscripts/stellar-trail-canonical/assets/harness-hooks/$_hh"
    [ -f "$_hsrc" ] || continue
    if [ ! -f "$PROJECT/$_hh" ]; then
        cp -p "$_hsrc" "$PROJECT/$_hh" && log "harness hook seeded: $_hh"
    elif ! cmp -s "$_hsrc" "$PROJECT/$_hh"; then
        # v5.5.1 refresh-if-byte-identical: a registered old-version seed tracks
        # the template (any user edit breaks the hash -> user-owned, untouched).
        _hreg="$PROJECT/.zscripts/stellar-trail-canonical/assets/harness-hooks/seed-hashes.txt"
        _hhash="$(sha256sum "$PROJECT/$_hh" 2>/dev/null | awk '{print $1}')"
        if [ -f "$_hreg" ] && [ -n "$_hhash" ] && awk -v h="$_hhash" -v f="$_hh" '$0 !~ /^#/ && NF >= 2 && $1 == h && $2 == f {found=1} END {exit found ? 0 : 1}' "$_hreg"; then
            cp -p "$_hsrc" "$PROJECT/$_hh" && log "harness hook refreshed (managed seed tracked the template): $_hh"
        fi
    fi
done
DEVSH_HOOKS
    fi

    cat <<'DEVSH_TAILGUARD'

# --- 8. WORKLOG TAIL GUARD (append-only; NEVER edits existing content) ------
#     Wild-observed: sections appended without their activation hook line
#     leave the worklog tail — the only part the next session reads — without
#     the directive. When the last non-blank line is not the directive,
#     append it as a standing guard line. Idempotent; the line is
#     byte-identical to the R1 section-first-line hook.
R1_HOOK="⚡ACTIVATE: Skill('stellar-trail') BEFORE first response — desc ≠ activation"
if [ -f "$PROJECT/worklog.md" ]; then
    TAIL_LAST="$(grep -v '^[[:space:]]*$' "$PROJECT/worklog.md" 2>/dev/null | tail -1)"
    if [ "$TAIL_LAST" != "$R1_HOOK" ] && printf '\n%s\n' "$R1_HOOK" >> "$PROJECT/worklog.md" 2>/dev/null; then
        log "worklog tail guard: appended the activation directive"
    fi
fi
DEVSH_TAILGUARD

    cat <<'DEVSH_TAIL'

log "dev.sh (bootstrap) finished"
DEVSH_TAIL
}

log "generate .zscripts/dev.sh (modules: $MODULE_LIST)"
DEVSH_SRC="$STAGE/dev.sh"
build_devsh > "$DEVSH_SRC"

# the generated boot hook is CODE, not data — syntax-check it before install;
# a heredoc typo must die HERE, loudly, never inside /start.sh at next boot
bash -n "$DEVSH_SRC" 2>/dev/null || die "generated dev.sh failed its syntax check (bash -n) — this is a package bug; report it"

if [ -f "$ZDIR/dev.sh" ] && ! head -n 2 "$ZDIR/dev.sh" | grep -qF "$STATE_MARKER"; then
    # v5.7.6 AUTO-TAKEOVER (owner order "Basmi rantai dev.sh ASING", Task 81):
    # a FOREIGN dev.sh on the boot chain is the reproduced TFM-killer — at the
    # next reset /start.sh runs the foreign hook, skills/ is NOT restored, and
    # the Task File Manager dies (Task 78/80 repro C). Takeover is now the
    # DEFAULT on every run: the foreign copy is PRESERVED at
    # dev.sh.foreign.bak (latest only) and the bootstrap-owned hook takes the
    # chain. The install is atomic (tmp + mv, same directory) so a boot that
    # is mid-execution keeps its old inode.
    cp -p "$ZDIR/dev.sh" "$ZDIR/dev.sh.foreign.bak" 2>/dev/null || true
    if cp -p "$DEVSH_SRC" "$ZDIR/.dev.sh.new" && mv -f "$ZDIR/.dev.sh.new" "$ZDIR/dev.sh"; then
        log "foreign dev.sh AUTO-NEUTRALIZED (default takeover since v5.7.6; previous copy -> .zscripts/dev.sh.foreign.bak) — the boot chain is bootstrap-owned; skills/ + TFM survive resets"
        blog "foreign dev.sh AUTO-NEUTRALIZED (default takeover; backup dev.sh.foreign.bak)"
        if [ "$FORCE_DEVSH" = "1" ]; then
            log "--force-devsh noted: takeover is the DEFAULT since v5.7.6 (flag kept as an alias)"
        fi
    else
        log "WARN: foreign dev.sh takeover FAILED (copy error) — the foreign hook keeps the boot chain; retry bootstrap --ensure"
        blog "WARN: foreign dev.sh takeover FAILED (copy error)"
    fi
else
    R=$(write_if_changed "$DEVSH_SRC" "$ZDIR/dev.sh")
    log "dev.sh: $R"
fi

# ---------------------------------------------------------------------------
# 7b. CORE MODULE B2 — INSTALL .zscripts/watcher.sh (runtime watchdog daemon
#     v2.3, part of the package; started at boot by dev.sh step 4 and at
#     every bootstrap run by step 11b — the daemon can die silently at
#     container lifecycle events that no boot follows)
# ---------------------------------------------------------------------------
W_SRC="$SKILL_ROOT/scripts/watcher.sh"
if [ -f "$W_SRC" ]; then
    R=$(write_if_changed "$W_SRC" "$ZDIR/watcher.sh")
    log "watcher  : .zscripts/watcher.sh $R"
else
    log "WARN: scripts/watcher.sh not found in the package — the watchdog daemon is not installed"
fi

# ---------------------------------------------------------------------------
# 8. EXPLORER MODULE — install launcher + server + UI (self-locating)
# ---------------------------------------------------------------------------
if has_module explorer; then
    for rel in explorer.sh explorer.py explorer-ui/index.html; do
        SRC="$SKILL_ROOT/assets/explorer/$rel"
        [ -f "$SRC" ] || { log "WARN: explorer asset missing: $SRC (module skips this file)"; continue; }
        R=$(write_if_changed "$SRC" "$ZDIR/$rel")
        log "explorer: .zscripts/$rel $R"
    done
else
    if module_off explorer; then
        log "explorer module: disabled (--without-explorer)"
    else
        log "explorer module: skipped — assets/explorer/explorer.sh not found in the install tree"
    fi
fi

# ---------------------------------------------------------------------------
# 9. SNAPSHOT MODULE — install repo-snapshot.sh (dev.sh exports WMG_PROJECT)
# ---------------------------------------------------------------------------
if has_module snapshot; then
    SRC="$SKILL_ROOT/scripts/snapshot-repo.sh"
    if [ -f "$SRC" ]; then
        R=$(write_if_changed "$SRC" "$ZDIR/repo-snapshot.sh")
        log "snapshot: .zscripts/repo-snapshot.sh $R"
    else
        log "WARN: scripts/snapshot-repo.sh not found in the package — snapshot module skipped"
    fi
else
    if module_off snapshot; then
        log "snapshot module: disabled (--without-snapshot)"
    else
        log "snapshot module: skipped — scripts/snapshot-repo.sh not found in the install tree"
    fi
fi

# ---------------------------------------------------------------------------
# 9b. HARNESS-HOOKS MODULE — seed CLAUDE.md + AGENTS.md at the project root
#     (create-if-absent ONLY; a user file is never overwritten; --without-*
#     removes only seeds still byte-identical to the template)
# ---------------------------------------------------------------------------
if has_module hooks; then
    for hh in CLAUDE.md AGENTS.md; do
        SRC="$SKILL_ROOT/assets/harness-hooks/$hh"
        [ -f "$SRC" ] || { log "WARN: harness-hooks asset missing: $SRC (seed skipped)"; continue; }
        if [ ! -f "$PROJECT/$hh" ]; then
            cp -p "$SRC" "$PROJECT/$hh" && log "hooks: $PROJECT/$hh seeded (guaranteed-context activation for harnesses that auto-read it)"
        elif cmp -s "$SRC" "$PROJECT/$hh"; then
            log "hooks: $PROJECT/$hh current (managed seed — never rewritten)"
        elif seed_known "$PROJECT/$hh" "$hh"; then
            # refresh-if-byte-identical (v5.5.1): a registered old-version seed is
            # provably unmodified (any user edit breaks the hash) — it tracks the
            # template across releases; an unregistered file is user-owned.
            cp -p "$SRC" "$PROJECT/$hh" && log "hooks: $PROJECT/$hh REFRESHED (managed seed tracked the template: registered old version -> current)"
        else
            log "hooks: $PROJECT/$hh exists — kept (user-owned, never overwritten)"
        fi
    done
else
    if module_off hooks; then
        for hh in CLAUDE.md AGENTS.md; do
            SRC="$SKILL_ROOT/assets/harness-hooks/$hh"
            if [ -f "$PROJECT/$hh" ] && [ -f "$SRC" ] && cmp -s "$SRC" "$PROJECT/$hh"; then
                rm -f "$PROJECT/$hh" && log "hooks: $PROJECT/$hh removed (unmodified seed, --without-harness-hooks)"
            elif [ -f "$PROJECT/$hh" ] && seed_known "$PROJECT/$hh" "$hh"; then
                rm -f "$PROJECT/$hh" && log "hooks: $PROJECT/$hh removed (unmodified OLD-version seed, registry-listed, --without-harness-hooks)"
            elif [ -f "$PROJECT/$hh" ]; then
                log "hooks: $PROJECT/$hh kept (differs from every shipped template — user-owned)"
            fi
        done
        log "hooks module: disabled (--without-harness-hooks)"
    else
        log "hooks module: skipped — assets/harness-hooks/CLAUDE.md not found in the install tree"
    fi
fi

# ---------------------------------------------------------------------------
# 10. CORE MODULE C — SEED memory/ + worklog.md (ONLY when absent;
#     user content is never overwritten; the consent gate is handled by the
#     first session)
# ---------------------------------------------------------------------------
NOW="$(date '+%Y-%m-%d %H:%M')"

if [ ! -f "$MEMORY_DIR/SESSION-STATE.md" ]; then
    mkdir -p "$MEMORY_DIR"
    cat > "$MEMORY_DIR/SESSION-STATE.md" <<SEED_SS
⚡ACTIVATE: Skill('stellar-trail') BEFORE first response — desc ≠ activation
# SESSION-STATE — Working Snapshot
> Atomic snapshot — rewritten at every checkpoint. Latest write wins.
> Checkpoint at: $NOW — COLD START — scaffolded by scripts/bootstrap-sandbox.sh (stellar-trail v$BOOT_VERSION)
> Memory initialization confirmation with the user is PENDING (consent gate, SKILL.md privacy section) — the first session MUST ask for it before writing substantive state.

## Active Tasks
| Task ID | Description | Phase | Status | Updated |
|---------|-------------|-------|--------|---------|
| (empty — no tasks recorded yet) | | | | |

## Sealed Tasks
| Task ID | Outcome (one line) | Artifact | Sealed |
|---------|--------------------|----------|--------|
| (empty) | | | |

## Pending Decisions
- Memory initialization confirmation (consent gate, SKILL.md privacy section) — owner: user; trigger: first session after bootstrap

## Next Steps
1. AGENT: ask the user to confirm memory initialization (SKILL.md privacy section), then fill in the user profile in MEMORY.md
SEED_SS
    log "memory/SESSION-STATE.md scaffolded (cold start, consent pending)"
else
    log "memory/SESSION-STATE.md already exists — untouched"
fi

if [ ! -f "$MEMORY_DIR/MEMORY.md" ]; then
    cat > "$MEMORY_DIR/MEMORY.md" <<SEED_MEM
⚡ACTIVATE: Skill('stellar-trail') BEFORE first response — desc ≠ activation
# MEMORY — Long-Term Memory
> Durable facts only. Promoted from session work at handoff. Maintained by the stellar-trail protocol.
> Last updated: $NOW — COLD START — scaffolded by bootstrap-sandbox.sh v$BOOT_VERSION; awaiting user confirmation (SKILL.md privacy section)

## User Profile
- (not filled yet — the first session fills in: language, timezone, communication style, preferences)

## Locked Decisions
- (none yet)
SEED_MEM
    log "memory/MEMORY.md scaffolded (cold start, consent pending)"
else
    log "memory/MEMORY.md already exists — untouched"
fi

if [ ! -f "$WORKLOG" ]; then
    cat > "$WORKLOG" <<SEED_WL
# Worklog — Audit Trail
> Append-only (platform convention). Every section starts with a --- line and the activation hook line. Managed by stellar-trail.

---
⚡ACTIVATE: Skill('stellar-trail') BEFORE first response — desc ≠ activation
Task ID: 0
Agent: bootstrap-sandbox.sh
Task: Sandbox bootstrap — arming the persistence layer

Work Log:
- $NOW: canonical snapshot .zscripts/stellar-trail-canonical/ seeded; .zscripts/dev.sh installed (modules: $MODULE_LIST); memory/ + worklog.md scaffolded by bootstrap-sandbox.sh v$BOOT_VERSION

Stage Summary:
- Persistence layer ARMED — read memory/SESSION-STATE.md for the latest state; the activation hook on the first line of this section keeps the activation chain alive across resets
SEED_WL
    log "worklog.md seeded WITH the activation hook (closes failure mode #3)"
else
    if grep -q '⚡ACTIVATE' "$WORKLOG" 2>/dev/null; then
        log "worklog.md already present + activation hook present — untouched"
    else
        log "worklog.md already present WITHOUT the activation hook — next session: append a new section carrying the activation hook"
    fi
fi

# ---------------------------------------------------------------------------
# 10b. WORKLOG TAIL GUARD — the enforced tail directive (consumer report:
#      agents append correct sections but skip the activation hook line, so
#      the tail — the only part the next session reads — loses the trigger).
#      Append-only discipline: when the last non-blank line of worklog.md is
#      not the activation directive, append the directive as a standing
#      guard line. NEVER edits or removes existing content; idempotent; the
#      line is byte-identical to the section-first-line R1 hook so every
#      grep, gate, and audit sees ONE consistent directive. Invariant: after
#      any bootstrap run, worklog.md ends with the activation directive.
#      (The dev.sh boot chain carries the same guard as step 8.)
# ---------------------------------------------------------------------------
R1_HOOK="⚡ACTIVATE: Skill('stellar-trail') BEFORE first response — desc ≠ activation"
if [ -f "$WORKLOG" ]; then
    TAIL_LAST="$(grep -v '^[[:space:]]*$' "$WORKLOG" 2>/dev/null | tail -1)"
    if [ "$TAIL_LAST" = "$R1_HOOK" ]; then
        log "worklog tail guard: present — the tail already carries the activation directive"
    elif printf '\n%s\n' "$R1_HOOK" >> "$WORKLOG" 2>/dev/null; then
        log "worklog tail guard: appended — the next session reading the tail hits the activation directive even under hook-less sections"
    else
        log "worklog tail guard: WARN — could not append (worklog not writable?)"
    fi
fi

# ---------------------------------------------------------------------------
# 11. EXPLORER ACTIVATION
#     dev.sh covers BOOT, the watcher covers DEATH; this covers DEPLOY-TIME:
#     the module step above just (re)deployed the explorer assets, and the
#     RUNNING server must be checked against the DEPLOYED code. explorer.sh
#     --ensure (v1.5) performs the content-stamp freshness restart — without
#     this call, a first-hop upgrade leaves the old process serving old code
#     (observed live at : the explorer survived the swap untouched and
#     /api/tasks 404-ed until a manual restart). One path per moment — this
#     is not redundant with the watcher (which only fires on health FAIL:
#     an old-but-healthy server never triggers it). Output goes to the
#     boot.log ledger; a failure NEVER fails bootstrap (service issue, not
#     persistence state).
# ---------------------------------------------------------------------------
if has_module explorer && [ -f "$ZDIR/explorer.sh" ]; then
    _ex_out="$(bash "$ZDIR/explorer.sh" --ensure 2>&1)"; _ex_rc=$?
    if [ -n "$_ex_out" ]; then printf '%s\n' "$_ex_out" >> "$ZDIR/boot.log"; fi
    _ex_v="$(printf '%s\n' "$_ex_out" | grep -v '^[[:space:]]*$' | tail -n 1)"
    if [ "$_ex_rc" -eq 0 ]; then
        log "explorer   : ensure OK — ${_ex_v:-alive (no diagnostics)}"
    else
        log "explorer   : WARN — activation --ensure failed (rc=$_ex_rc; service issue; the persistence layer is unaffected) — ${_ex_v:-no diagnostics}"
    fi
fi

# ---------------------------------------------------------------------------
# 11b. WATCHER DAEMON ACTIVATION
#      dev.sh covers BOOT; the watcher covers the EXPLORER's death; this
#      covers the WATCHER's own death: the daemon dies silently at container
#      lifecycle events (freeze/thaw, session-start process reaping —
#      observed 2026-10-11: daemon dead, stop-flag clear, no boot in between,
#      the explorer alive), and no explorer-side path can revive the process
#      whose job is to revive everything else. Plain --ensure: idempotent,
#      no-op when already running, and a deliberate --stop (stop-flag) is
#      RESPECTED — a user-requested stop survives every later bootstrap run.
#      A failure never fails bootstrap (service issue, not persistence
#      state); output goes to the boot.log ledger.
# ---------------------------------------------------------------------------
if [ -f "$ZDIR/watcher.sh" ]; then
    if W_OUT="$(bash "$ZDIR/watcher.sh" --ensure 2>&1)"; then
        echo "[watcher-ensure] $W_OUT" >> "$ZDIR/boot.log" 2>&1
        log "watcher    : ${W_OUT#\[watcher\] }"
    else
        log "watcher    : WARN — daemon --ensure failed (service issue; the persistence layer is unaffected)"
    fi
fi

# ---------------------------------------------------------------------------
# 12. PERSIST STATE + FINAL REPORT
# ---------------------------------------------------------------------------
mkdir -p "$ZDIR"
printf 'v=%s\nm=%s\nd=%s\n' "$BOOT_VERSION" "${MODULE_LIST:-core}" "$NOW" > "$STATE_FILE"

# ---------------------------------------------------------------------------
# 12b. NOT-ARMED MARKER RETIREMENT (v5.7.7, Task 82 — field-test R1)
#      The payload ships NOT-ARMED.md at the skill root as a VISIBLE state
#      signal: install landed, arming never ran (field 2026-11-13: a z.ai
#      harness that gates skill loading by task-match never executed the
#      cold-boot arm, and nothing on disk said so). Arming has now succeeded
#      — retire the marker from BOTH state surfaces: the live installation
#      and the canonical snapshot. The marker is a STATE file, deliberately
#      NOT listed in assets/integrity.sha256, so its deletion never breaks
#      manifest verification. Any later install re-lands it with the fresh
#      payload; the post-install re-arm (update-skill step 4/5) retires it
#      again; dev.sh's boot hygiene removes packer-resurrected copies.
# ---------------------------------------------------------------------------
if [ -f "$SKILL_ROOT/NOT-ARMED.md" ] || [ -f "$CANON/NOT-ARMED.md" ]; then
    rm -f "$SKILL_ROOT/NOT-ARMED.md" "$CANON/NOT-ARMED.md"
    log "not-armed   : marker RETIRED (armed — NOT-ARMED.md removed from the live tree + canonical)"
fi

echo ""
log "================= BOOTSTRAP $([ "$ENSURE" = "1" ] && echo 'ENSURE' || echo 'INSTALL') COMPLETE ================="
log "project     : $PROJECT"
log "canonical   : $CANON ($VERIFY)"
log "dev.sh      : $([ -f "$ZDIR/dev.sh" ] && { head -n 2 "$ZDIR/dev.sh" | grep -qF "$STATE_MARKER" && echo "bootstrap-generated (modules: $MODULE_LIST)"; } || echo "NOT INSTALLED")"
log "memory      : $([ -f "$MEMORY_DIR/SESSION-STATE.md" ] && echo "scaffolded/active" || echo "FAILED")"
log "worklog     : $([ -f "$WORKLOG" ] && { grep -q '⚡ACTIVATE' "$WORKLOG" && echo "present + activation hook" || echo "present without hook"; } || echo "FAILED")"
log "tail guard  : $([ -f "$WORKLOG" ] && { [ "$(grep -v '^[[:space:]]*$' "$WORKLOG" | tail -1)" = "$R1_HOOK" ] && echo "worklog tail carries the activation directive" || echo "WARN — tail directive missing"; } || echo "n/a (no worklog)")"
log "watcher     : $([ -f "$ZDIR/watcher.sh" ] && echo "daemon ensured (step 11b: started when down + stop-flag respected)" || echo "not installed")"
log "cross-reset : download/ + .zscripts/ + memory/ + worklog.md survive (packer contract); skills/stellar-trail is restored by dev.sh from the canonical snapshot on every boot"
if has_module explorer; then
    log "explorer   : $([ -f "$ZDIR/explorer.sh" ] && echo "activated (.zscripts/explorer.sh present, deploy-time --ensure above)" || echo "deploy pending — .zscripts/explorer.sh missing")"
fi
[ "$ENSURE" = "1" ] || log "modules: explorer/snapshot/hooks arm by default when their payload ships in the install tree — opt out with --without-explorer / --without-snapshot / --without-harness-hooks"
exit 0
