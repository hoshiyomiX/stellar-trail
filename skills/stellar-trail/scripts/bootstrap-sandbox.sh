#!/usr/bin/env bash
# ============================================================================
# bootstrap-sandbox.sh — arm the persistence layer for reset-prone sandboxes
# stellar-trail v3.6.7 · 2026-09-27
#
# WHAT THIS SOLVES (three confirmed failure modes of container sandboxes
# whose platform restores the project from an archive on every boot):
#   1. skill files vanish after a reset — the platform packer excludes
#      skills/ from the restore archive, wiping the installation each boot
#   2. explorer/services stay dead — no boot hook restarts processes that
#      the reset killed
#   3. the activation chain breaks — worklog.md is never created, so the
#      activation hook is missing and the skill is never loaded next session
#
# THE SOLUTION (one proven path per module — no redundant fallbacks):
#   core     : copy the live installation to the canonical snapshot at
#              download/stellar-trail/ (the platform packer PRESERVES
#              download/ + .zscripts/ + memory/ + worklog.md — verified
#              against the packer's own archive), then install
#              .zscripts/dev.sh (boot hook on the /start.sh contract) which
#              restores skills/stellar-trail from the canonical snapshot on
#              EVERY boot, plus .zscripts/watcher.sh (runtime watchdog
#              daemon v2.0: explorer health, release-file guard,
#              installation integrity checks, archive refresh, compliance
#              alarm; started by dev.sh and by the cold-boot step).
#   explorer : --with-explorer  installs .zscripts/{explorer.sh,explorer.py,
#              explorer-ui/} and an --ensure step in dev.sh — plus, since
#              v3.6.9, a DEPLOY-TIME activation call at the end of every
#              bootstrap run (the running server is checked against the
#              just-deployed code; explorer.sh v1.5 does the content-stamp
#              freshness restart — closes the upgrade-path gap where a
#              first-hop left the old process serving).
#   snapshot : --with-snapshot  installs .zscripts/repo-snapshot.sh and an
#              --apply-auto step in dev.sh (platforms with /home/sync).
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
#   bash scripts/bootstrap-sandbox.sh                     # install core + report
#   bash scripts/bootstrap-sandbox.sh --ensure            # idempotent (cold-boot path; uses modules from state)
#   bash scripts/bootstrap-sandbox.sh --with-explorer     # enable the explorer module
#   bash scripts/bootstrap-sandbox.sh --with-snapshot     # enable the snapshot module
#   bash scripts/bootstrap-sandbox.sh --status            # read-only report
#   bash scripts/bootstrap-sandbox.sh --project-dir PATH  # override project-root detection
#   bash scripts/bootstrap-sandbox.sh --force-devsh       # overwrite a dev.sh owned by another deployment
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

for arg in "$@"; do
    case "$arg" in
        --ensure)        ENSURE=1 ;;
        --status)        MODE="status" ;;
        --with-explorer) MODULE_ARGS+=("explorer") ;;
        --with-snapshot) MODULE_ARGS+=("snapshot") ;;
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

CANON="$PROJECT/download/stellar-trail"
ZDIR="$PROJECT/.zscripts"
STATE_FILE="$ZDIR/bootstrap.state"
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
            echo "dev.sh     : present but NOT owned by bootstrap (skipped without --force-devsh)"
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
    echo "watcher    : .zscripts/watcher.sh $([ -f "$ZDIR/watcher.sh" ] && echo OK || echo 'NOT PRESENT (core)')"
    echo "memory     : $([ -f "$MEMORY_DIR/SESSION-STATE.md" ] && echo "scaffolded/active ($MEMORY_DIR)" || echo "NOT CREATED")"
    echo "worklog    : $([ -f "$WORKLOG" ] && { grep -q '⚡ACTIVATE' "$WORKLOG" && echo "present + activation hook OK" || echo "present WITHOUT activation hook"; } || echo "NOT CREATED")"
    echo "state file : $([ -f "$STATE_FILE" ] && cat "$STATE_FILE" | tr '\n' ' ' || echo "not created yet")"
    rm -f "$MODULES_FILE"
    exit 0
fi

# ---------------------------------------------------------------------------
# 6. CORE MODULE A — SEED THE CANONICAL SNAPSHOT: live install → download/stellar-trail/
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
#    A bootstrap-owned dev.sh is marked; a foreign dev.sh is never overwritten
#    unless --force-devsh is given.
# ---------------------------------------------------------------------------
build_devsh() {
    cat <<'DEVSH_HEAD'
#!/usr/bin/env bash
DEVSH_HEAD
    echo "$STATE_MARKER v$BOOT_VERSION (modules: $MODULE_LIST)"
    cat <<'DEVSH_BODY'
# dev.sh — PERSISTENT BOOT HOOK (run automatically by /start.sh on every boot)
# GENERATED BY bootstrap-sandbox.sh — do not edit by hand; regenerate with
#   bash download/stellar-trail/scripts/bootstrap-sandbox.sh [--with-*]
#
# ONE PATH PER MODULE (no redundant fallbacks):
#   1. SKILL RESTORE : skills/stellar-trail is verified against the canonical
#      snapshot download/stellar-trail (SHA-256 manifest); broken/missing →
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
    cat <<'DEVSH_VARS'

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOAD="$PROJECT/download"
ARCHIVE="$PROJECT/archive"
BOOTLOG="$PROJECT/.zscripts/boot.log"
LOCKDIR="/tmp/dev-sh.lock"
CANON="$DOWNLOAD/stellar-trail"

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
fi
DEVSH_RESTORE

    cat <<'DEVSH_FULLSTACK'

# --- 2. FULLSTACK GUARD ------------------------------------------------------
if [ -f "$PROJECT/package.json" ]; then
    log "package.json detected -> delegating to the standard fullstack boot flow"
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
    if bash "$PROJECT/.zscripts/explorer.sh" --ensure >> "$BOOTLOG" 2>&1; then
        log "explorer --ensure: OK (running / guard active)"
    else
        log "WARN: explorer --ensure failed"
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
    if [ "$FORCE_DEVSH" = "1" ]; then
        cp -p "$DEVSH_SRC" "$ZDIR/dev.sh"
        log "foreign dev.sh OVERWRITTEN (--force-devsh) — the bootstrap version is installed"
    else
        log "SKIP dev.sh: a non-bootstrap dev.sh already exists at $ZDIR (owned by another deployment). Use --force-devsh to overwrite."
        log "NOTE: without a bootstrap-owned dev.sh, the skill is NOT restored automatically after a reset."
    fi
else
    R=$(write_if_changed "$DEVSH_SRC" "$ZDIR/dev.sh")
    log "dev.sh: $R"
fi

# ---------------------------------------------------------------------------
# 7b. CORE MODULE B2 — INSTALL .zscripts/watcher.sh (runtime watchdog daemon
#     v2.0, part of the package since v3.6.3; dev.sh step 4 starts it)
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
    log "explorer module: NOT enabled (use --with-explorer to enable)"
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
    log "snapshot module: NOT enabled (use --with-snapshot to enable)"
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
- $NOW: canonical snapshot download/stellar-trail/ seeded; .zscripts/dev.sh installed (modules: $MODULE_LIST); memory/ + worklog.md scaffolded by bootstrap-sandbox.sh v$BOOT_VERSION

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
# 11. EXPLORER ACTIVATION (v3.6.9 — closes the upgrade-path gap)
#     dev.sh covers BOOT, the watcher covers DEATH; this covers DEPLOY-TIME:
#     the module step above just (re)deployed the explorer assets, and the
#     RUNNING server must be checked against the DEPLOYED code. explorer.sh
#     --ensure (v1.5) performs the content-stamp freshness restart — without
#     this call, a first-hop upgrade leaves the old process serving old code
#     (observed live at v3.6.7: the explorer survived the swap untouched and
#     /api/tasks 404-ed until a manual restart). One path per moment — this
#     is not redundant with the watcher (which only fires on health FAIL:
#     an old-but-healthy server never triggers it). Output goes to the
#     boot.log ledger; a failure NEVER fails bootstrap (service issue, not
#     persistence state).
# ---------------------------------------------------------------------------
if has_module explorer && [ -f "$ZDIR/explorer.sh" ]; then
    if bash "$ZDIR/explorer.sh" --ensure >> "$ZDIR/boot.log" 2>&1; then
        log "explorer   : activated — deployed code live on :3000 (freshness restart handled by explorer.sh v1.5)"
    else
        log "explorer   : WARN — activation --ensure failed (service issue; the persistence layer is unaffected)"
    fi
fi

# ---------------------------------------------------------------------------
# 12. PERSIST STATE + FINAL REPORT
# ---------------------------------------------------------------------------
mkdir -p "$ZDIR"
printf 'v=%s\nm=%s\nd=%s\n' "$BOOT_VERSION" "${MODULE_LIST:-core}" "$NOW" > "$STATE_FILE"

echo ""
log "================= BOOTSTRAP $([ "$ENSURE" = "1" ] && echo 'ENSURE' || echo 'INSTALL') COMPLETE ================="
log "project     : $PROJECT"
log "canonical   : $CANON ($VERIFY)"
log "dev.sh      : $([ -f "$ZDIR/dev.sh" ] && { head -n 2 "$ZDIR/dev.sh" | grep -qF "$STATE_MARKER" && echo "bootstrap-generated (modules: $MODULE_LIST)"; } || echo "NOT INSTALLED")"
log "memory      : $([ -f "$MEMORY_DIR/SESSION-STATE.md" ] && echo "scaffolded/active" || echo "FAILED")"
log "worklog     : $([ -f "$WORKLOG" ] && { grep -q '⚡ACTIVATE' "$WORKLOG" && echo "present + activation hook" || echo "present without hook"; } || echo "FAILED")"
log "cross-reset : download/ + .zscripts/ + memory/ + worklog.md survive (packer contract); skills/stellar-trail is restored by dev.sh from the canonical snapshot on every boot"
if has_module explorer; then
    log "explorer   : $([ -f "$ZDIR/explorer.sh" ] && echo "activated (.zscripts/explorer.sh present, deploy-time --ensure above)" || echo "deploy pending — .zscripts/explorer.sh missing")"
fi
[ "$ENSURE" = "1" ] || log "optional modules: --with-explorer (task files explorer) · --with-snapshot (platform archive refresh, /home/sync)"
exit 0
