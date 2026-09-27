#!/usr/bin/env bash
# ============================================================================
# repo-snapshot.sh — REFRESH /home/sync/repo.tar (anti failed pre-stop)
# v1.4 — bundled asset of skill stellar-trail v3.3.1; live project copy:
#        <project>/.zscripts/repo-snapshot.sh (identical content — keep in sync)
#
# CHANGELOG v1.4 (Task 27, stellar-trail v3.3.0):
#   - Shadow backup layer REMOVED ENTIRELY (user verdict: worthless — forensic
#     incident 07:38: stale false-positive detection, blind spot & failure
#     domain identical to the archive it protected, 62MB written/30 min).
#     No more opportunistic backup from --apply-auto.
#   - State directories split: WMG_ORIG_DIR (original repo.tar backups,
#     default $WMG_SYNC/repo-originals — legacy alias WMG_SHADOW_DIR still
#     honored) and WMG_STATE_DIR (debounce/cooldown/fingerprint markers,
#     default $WMG_SYNC/repo-state). wmg-shadow/ is no longer used.
#
# CHANGELOG v1.3 (Task 26 — resilience architecture v2):
#   - NEW MODE --apply-auto: refresh with double gating — debounce (material
#     change since last apply) + 15-minute cooldown; invoked automatically by
#     the boot hook and the periodic watcher.
#     Manual --apply stays ungated (force).
#   - build_tar INCLUDES skills/stellar-trail (surgical append via tar -rf;
#     other official skills stay excluded) — closes the gap "skills/ never
#     made it into repo.tar", the cause of the 07:37 UTC post-restart degrade.
#
# CHANGELOG v1.2 (response to clawscan v2.2.1 finding "tar command-injection"):
#   - build_tar uses a NUL-separated list via 'tar --null -T' — entry names
#     are NEVER parsed as tar options, closing the argument-injection vector
#     (a file named '--use-compress-program=...' in the project root cannot
#     make tar execute a command)
#   - top_entries SKIPS suspicious names: leading '-' (readable as an option
#     by other list-consuming tools) or containing a newline — layered defense
#
# CHANGELOG v1.1 (response to clawscan v2.2.0 finding "unsafe tar invocation"):
#   - new member audit: a tar installed on the boot-restore path MUST be free
#     of path traversal (absolute members or any '..' component HARD-REJECTED;
#     absolute-target symlinks warned) — /start.sh extracts repo.tar via
#     'tar xf' with no member protection, so the check lives here
#   - --restore-original VERIFIED before swap (structure + member audit):
#     undo stays byte-identical, but a corrupt/hostile archive is REJECTED so
#     it cannot break the next boot; the original backup is never deleted
#
# PROBLEM THIS SOLVES:
#   /home/sync/repo.tar is the container's only boot-restore source (read by
#   /start.sh: rm -rf project except upload -> tar xf repo.tar). This tar is
#   normally rewritten by the platform's PRE-STOP hook when the container
#   stops — but pre-stop DOES NOT ALWAYS run (crash, force-kill, pack
#   failure; a branch start.sh itself acknowledges). When that happens, the
#   next boot restores an old state = a silent rollback.
#
# SOLUTION: refresh repo.tar with a snapshot of the CURRENT state, so the
#   boot restore ALWAYS receives fresh state regardless of pre-stop's fate.
#   Companion layers: the boot hook's cache-replay skill restore (canonical
#   download/stellar-trail) and --restore-original (undo).
#
# FORMAT COMPATIBILITY (Task 16-d forensics):
#   - relative entries WITHOUT the ./ prefix (e.g. ".zscripts/dev.sh",
#     "worklog.md")
#   - platform packer excludes: skills/, node_modules/, db/
#   - upload/ excluded (separate OSS mount, also skipped during extraction
#     by start.sh --exclude); .venv/.next = build artifacts, also excluded
#   - start.sh tolerates a corrupt tar (warning + continue) — non-fatal, and
#     this script verifies the tar BEFORE swap + backs up the original first.
#
# SWAP SAFETY (empirically tested on ossfs):
#   build in /tmp (local, fast) -> verify (structure + member audit)
#   -> back up original to repo-originals/ -> copy to .repo.tar.staged (same
#   mount) -> mv rename-overwrite (supported by ossfs, tested 2026-09-16)
#   -> final verify. Restore-original is likewise verified (structure +
#   members) before swap.
#
# COMMANDS:
#   repo-snapshot.sh --status             # repo.tar age diagnosis (default)
#   repo-snapshot.sh --dry-run            # build + verify, NO swap
#   repo-snapshot.sh --apply              # backup original -> build -> swap -> verify
#   repo-snapshot.sh --apply-auto         # --apply with double gating (periodic)
#   repo-snapshot.sh --restore-original   # restore the latest original repo.tar
#
# Sandbox overrides: WMG_PROJECT, WMG_SYNC, WMG_ORIG_DIR (legacy alias:
# WMG_SHADOW_DIR), WMG_STATE_DIR, WMG_TMP
# Exit: 0 success/no-action · 1 failure · 2 usage error
# ============================================================================
WMG_PROJECT="${WMG_PROJECT:-/home/z/my-project}"
WMG_SYNC="${WMG_SYNC:-/home/sync}"
WMG_ORIG_DIR="${WMG_ORIG_DIR:-${WMG_SHADOW_DIR:-$WMG_SYNC/repo-originals}}"
WMG_STATE_DIR="${WMG_STATE_DIR:-$WMG_SYNC/repo-state}"
WMG_TMP="${WMG_TMP:-/tmp}"
TAR_PATH="$WMG_SYNC/repo.tar"
LOG="$WMG_PROJECT/.zscripts/boot.log"
KEEP_ORIG=5                      # rolling retention of original repo.tar backups
COOLDOWN_AUTO=900                # minimum spacing between --apply-auto runs (seconds)

ts() { date '+%Y-%m-%d %H:%M:%S'; }
# always print to stdout (this script is manual/diagnostic, not cron-silent)
slog() {
    echo "[repo-snap] $*"
    echo "[$(ts)] [repo-snap] $*" >> "$LOG" 2>/dev/null
}
# log-only WITHOUT stdout — required inside functions that produce data on
# stdout (e.g. top_entries): diagnostics leaking to stdout would be read as
# list entries by the caller (real v1.2 bug, caught in sandbox testing)
slog_q() {
    echo "[$(ts)] [repo-snap] $*" >> "$LOG" 2>/dev/null
}

# Top-level project entries follow the platform packer convention
EXCLUDE_TOP="skills node_modules db upload .venv .next"

top_entries() {
    local e name
    for e in "$WMG_PROJECT"/* "$WMG_PROJECT"/.[!.]*; do
        [ -e "$e" ] || continue
        name="$(basename "$e")"
        case " $EXCLUDE_TOP " in
            *" $name "*) continue ;;
        esac
        # anti argument-injection (v1.2): a leading '-' name can be read as
        # an option by list-consuming tools; a newline name breaks the list
        # format. slog_q (not slog): this function's stdout is LIST DATA,
        # not log output.
        case "$name" in
            -*) slog_q "SKIP suspicious entry (leading '-'): $name"; continue ;;
            *$'\n'*) slog_q "SKIP newline entry: $name"; continue ;;
        esac
        printf '%s\n' "$name"
    done
}

build_tar() {  # $1 = output path (local)
    # v1.2 anti command-injection: NUL-separated entry list via -T — file
    # names are NEVER interpreted as tar options (unlike unquoted $ents
    # expansion, which would let a file named '--use-compress-program=...'
    # execute).
    local list="$WMG_TMP/repo-snap-list-$$.nul"
    top_entries | while IFS= read -r e; do printf '%s\0' "$e"; done > "$list"
    [ -s "$list" ] || { slog "FAIL: no top-level entries in $WMG_PROJECT"; rm -f "$list"; return 1; }
    if ! tar -cf "$1" --null -C "$WMG_PROJECT" -T "$list" 2>>"$LOG"; then
        rm -f "$list"; return 1
    fi
    rm -f "$list"
    # v1.3: surgical append of skills/stellar-trail — hardcoded literal path
    # (not a file-name expansion; the v1.2 argument-injection vector does not
    # apply). Best-effort: an append failure does not abort the apply (the
    # primary layer for skills/ remains the boot hook's cache-replay restore).
    if [ -d "$WMG_PROJECT/skills/stellar-trail" ]; then
        if tar -rf "$1" -C "$WMG_PROJECT" skills/stellar-trail 2>>"$LOG"; then
            slog_q "append skills/stellar-trail: $(tar -tf "$1" 2>/dev/null | grep -c '^skills/stellar-trail') entries"
        else
            slog "WARN: failed to append skills/stellar-trail (non-fatal)"
        fi
    else
        slog_q "skip append skills/stellar-trail (absent — the boot hook restores it from canonical)"
    fi
}

audit_members() {  # $1 = tar path, $2 = label; success = 0 (anti path-traversal)
    # /start.sh extracts repo.tar via 'tar xf' with NO member validation —
    # an absolute member or a '..' component could write outside the project
    # root. The boot-restore path is a critical asset: this audit cannot be
    # skipped.
    local t="$1" label="$2" bad
    bad="$(tar -tf "$t" 2>/dev/null \
          | awk 'BEGIN{FS="/"} /^\//{print; next} {for(i=1;i<=NF;i++) if($i==".."){print; break}}' \
          | head -2)"
    if [ -n "$bad" ]; then
        slog "FAIL audit $label: unsafe member: $(printf '%s' "$bad" | head -1)"
        return 1
    fi
    # best-effort: symlink members with absolute targets (potential escape on extraction)
    local sym
    sym="$(tar -tvf "$t" 2>/dev/null | awk '$1 ~ /^l/ && / -> \//' | head -2)"
    [ -z "$sym" ] || slog "WARNING audit $label: absolute-target symlink detected — inspect manually"
    return 0
}

verify_tar() {  # $1 = tar path, $2 = label; success = 0
    local t="$1" label="$2" n
    [ -s "$t" ] || { slog "FAIL verify $label: file empty/missing"; return 1; }
    if ! tar -tf "$t" >/dev/null 2>&1; then
        slog "FAIL verify $label: invalid tar structure"; return 1
    fi
    audit_members "$t" "$label" || return 1
    n="$(tar -tf "$t" 2>/dev/null | wc -l)"
    [ "$n" -ge 10 ] || { slog "FAIL verify $label: only $n entries (too few)"; return 1; }
    # key entries MUST exist (proof we packed the right directory)
    local key missing=0
    for key in .zscripts/dev.sh worklog.md memory/SESSION-STATE.md; do
        if ! tar -tf "$t" 2>/dev/null | grep -qx "$key"; then
            slog "FAIL verify $label: key entry '$key' missing"; missing=1
        fi
    done
    [ "$missing" -eq 0 ] || return 1
    slog "verify $label OK: $n entries, key entries complete ($(du -h "$t" | cut -f1))"
    VERIFIED_ENTRIES="$n"
    return 0
}

newest_orig() { ls -1t "$WMG_ORIG_DIR"/repo.tar.orig-* 2>/dev/null | head -1; }

# fingerprint of our own last-swapped tar (mtime|size) — so we never back up
# our own build and never overwrite a true original backup
ours_marker() { cat "$WMG_STATE_DIR/repo-snapshot.last" 2>/dev/null; }
tar_fingerprint() { stat -c '%Y|%s' "$TAR_PATH" 2>/dev/null; }

do_status() {
    echo "=== REPO SNAPSHOT (manual repo.tar refresh) ==="
    echo "project  : $WMG_PROJECT"
    echo "sync     : $WMG_SYNC"
    echo "orig dir : $WMG_ORIG_DIR · state dir: $WMG_STATE_DIR"
    if [ -f "$TAR_PATH" ]; then
        local tm age
        tm="$(stat -c %Y "$TAR_PATH" 2>/dev/null)"
        age=$(( $(date +%s) - tm ))
        echo "repo.tar : $(stat -c '%s bytes · %y' "$TAR_PATH" 2>/dev/null) (age $((age/3600))h $(((age%3600)/60))m)"
        if [ "$age" -gt 3600 ]; then
            echo "verdict  : *** STALE — if the container stops without pre-stop, the next boot rolls back to that state. Run --apply to refresh. ***"
        else
            echo "verdict  : FRESH (age < 1 hour)"
        fi
    else
        echo "repo.tar : not found (next boot = clean-project branch!)"
    fi
    local o
    o="$(newest_orig)"
    echo "orig bkp : ${o:-none yet}$([ -n "$o" ] && echo " ($(du -h "$o" | cut -f1))")"
    local al ac
    al="$(cat "$WMG_STATE_DIR/repo-snap.auto.last" 2>/dev/null)"
    ac="$(cat "$WMG_STATE_DIR/repo-snap.auto.count" 2>/dev/null)"
    [ -n "$al" ] && echo "auto     : #${ac:-0} last $(date -d @"$al" '+%F %T' 2>/dev/null) (cooldown ${COOLDOWN_AUTO}s)"
    echo "skills/  : $([ -d "$WMG_PROJECT/skills/stellar-trail" ] && echo 'stellar-trail included in tar (append)' || echo 'stellar-trail ABSENT (append skipped)')"
    return 0
}

do_apply() {  # $1 = dry|full
    local mode="$1"
    # Precondition: sync dir writable
    if ! mkdir -p "$WMG_ORIG_DIR" "$WMG_STATE_DIR" 2>/dev/null; then
        slog "FAIL: $WMG_SYNC not writable — cannot refresh repo.tar"; return 1; fi
    [ -d "$WMG_PROJECT" ] || { slog "FAIL: $WMG_PROJECT does not exist"; return 1; }

    local build="$WMG_TMP/repo-snap-build-$$.tar"
    trap 'rm -f "$build"' EXIT

    # 1. BUILD locally
    if ! build_tar "$build"; then rm -f "$build"; return 1; fi
    # 2. VERIFY before touching anything
    if ! verify_tar "$build" "build"; then rm -f "$build"; return 1; fi

    if [ "$mode" = dry ]; then
        echo "[repo-snap] DRY-RUN OK — $VERIFIED_ENTRIES entries, $(du -h "$build" | cut -f1); repo.tar NOT touched"
        rm -f "$build"; return 0
    fi

    # 3. BACK UP a foreign repo.tar (BEFORE swap) — platform-owned / unknown
    #    tar. A tar whose fingerprint matches our marker = our own build -> skip.
    if [ -f "$TAR_PATH" ]; then
        local fp marker
        fp="$(tar_fingerprint)"; marker="$(ours_marker)"
        if [ -n "$marker" ] && [ "$fp" = "$marker" ]; then
            slog "current repo.tar = our previous build — skip backup"
        else
            # ms-resolution name + anti-collision (lesson from a second-collision bug)
            local bk="$WMG_ORIG_DIR/repo.tar.orig-$(date +%Y%m%d-%H%M%S-%3N)" n=0
            while [ -e "$bk" ] && [ $n -lt 50 ]; do
                bk="$WMG_ORIG_DIR/repo.tar.orig-$(date +%Y%m%d-%H%M%S)-$n"; n=$((n+1)); done
            if cp "$TAR_PATH" "$bk" 2>>"$LOG"; then
                slog "backed up foreign repo.tar -> $(basename "$bk")"
                ls -1t "$WMG_ORIG_DIR"/repo.tar.orig-* 2>/dev/null | tail -n +$((KEEP_ORIG + 1)) \
                  | while read -r old; do rm -f "$old" && slog "retention: deleted $(basename "$old")"; done
            else
                slog "FAIL backing up original — swap ABORTED for safety"; rm -f "$build"; return 1
            fi
        fi
    fi

    # 4. STAGE to the same mount then rename-overwrite (as atomic as ossfs gets)
    local staged="$WMG_SYNC/.repo.tar.staged"
    if ! cp "$build" "$staged" 2>>"$LOG"; then
        slog "FAIL staging to $staged"; rm -f "$build" "$staged"; return 1; fi
    if ! verify_tar "$staged" "staged"; then rm -f "$build" "$staged"; return 1; fi
    if ! mv -f "$staged" "$TAR_PATH" 2>>"$LOG"; then
        slog "FAIL rename-overwrite repo.tar"; rm -f "$build" "$staged"; return 1; fi

    # 5. FINAL VERIFY
    if ! verify_tar "$TAR_PATH" "final"; then
        slog "*** FINAL FAILED — recover with: repo-snapshot.sh --restore-original ***"
        rm -f "$build"; return 1
    fi
    rm -f "$build"
    mkdir -p "$WMG_STATE_DIR" 2>/dev/null
    tar_fingerprint > "$WMG_STATE_DIR/repo-snapshot.last" 2>/dev/null
    slog "REPO.TAR REFRESHED: $VERIFIED_ENTRIES entries ($(du -h "$TAR_PATH" | cut -f1)) — next boot restore = current state"
    echo "[repo-snap] repo.tar refreshed successfully ($VERIFIED_ENTRIES entries)."
    return 0
}

do_apply_auto() {
    # periodic refresh with double gating — invoked by the boot hook (step 5)
    # and the watcher. Goal: while the container lives, repo.tar is never
    # more than ~15 minutes older than the project state.
    local now last
    now="$(date +%s)"
    last="$(cat "$WMG_STATE_DIR/repo-snap.auto.last" 2>/dev/null)"
    if [ -n "$last" ] && [ $((now - last)) -lt "$COOLDOWN_AUTO" ]; then
        slog_q "auto: cooldown ($((now - last))s < ${COOLDOWN_AUTO}s) — skip"
        return 0
    fi
    # debounce: only when a material change happened since the last apply
    # (the marker is deliberately re-stamped after each apply so only later
    # material changes trigger the next refresh — rsync -a preserves old
    # mtimes, so find -newer would not see them)
    local mark="$WMG_STATE_DIR/.repo-auto-trigger"
    if [ -f "$mark" ]; then
        local changed
        changed="$(find "$WMG_PROJECT" \
            \( -path "$WMG_PROJECT/skills" -o -path "$WMG_PROJECT/node_modules" \
               -o -path "$WMG_PROJECT/.venv" -o -path "$WMG_PROJECT/.next" \
               -o -path "$WMG_PROJECT/upload" -o -path "$WMG_PROJECT/db" \
               -o -path "$WMG_PROJECT/.git" -o -path "$WMG_PROJECT/archive" \
               -o -name "*.log" -o -name "*.pid" \) -prune \
            -o -type f -newer "$mark" -print 2>/dev/null | head -1)"
        # deliberate exception: skills/stellar-trail counts as material
        # (boot-hook restore output)
        if [ -z "$changed" ] && [ -d "$WMG_PROJECT/skills/stellar-trail" ]; then
            changed="$(find "$WMG_PROJECT/skills/stellar-trail" -type f -newer "$mark" 2>/dev/null | head -1)"
        fi
        if [ -z "$changed" ]; then
            slog_q "auto: no material change — skip"
            return 0
        fi
    fi
    if do_apply full; then
        mkdir -p "$WMG_STATE_DIR" 2>/dev/null
        date +%s > "$WMG_STATE_DIR/repo-snap.auto.last" 2>/dev/null
        touch "$WMG_STATE_DIR/.repo-auto-trigger" 2>/dev/null
        local n; n=$(( $(cat "$WMG_STATE_DIR/repo-snap.auto.count" 2>/dev/null || echo 0) + 1 ))
        echo "$n" > "$WMG_STATE_DIR/repo-snap.auto.count" 2>/dev/null
        slog "auto-apply #$n success"
        return 0
    fi
    slog_q "auto: apply failed — cooldown set to avoid retry spam"
    date +%s > "$WMG_STATE_DIR/repo-snap.auto.last" 2>/dev/null
    return 1
}

do_restore_original() {
    # EXPLICIT UNDO: restore the latest original repo.tar — VERIFIED first.
    # Undo stays byte-identical (no rebuild/filtering); verification only
    # READS the archive: valid structure + member audit (anti traversal). A
    # corrupt or hostile archive is REJECTED — installing it would break the
    # next boot, the exact failure this script prevents. The original backup
    # is never deleted on rejection. Verification deliberately does NOT use
    # verify_tar's full entry-count/key-entry thresholds — a legitimate
    # platform original may not contain our key entries.
    local o; o="$(newest_orig)"
    [ -n "$o" ] || { slog "no original repo.tar backup to restore"; return 1; }
    [ -s "$o" ] || { slog "original backup empty — refuse"; return 1; }
    if ! tar -tf "$o" >/dev/null 2>&1; then
        slog "FAIL restore: original backup corrupt (invalid tar structure) — swap ABORTED; backup intact at $(basename "$o")"; return 1
    fi
    if ! audit_members "$o" "restore-original"; then
        slog "FAIL restore: original backup contains unsafe members — swap ABORTED; backup intact at $(basename "$o")"; return 1
    fi
    local staged="$WMG_SYNC/.repo.tar.staged"
    cp "$o" "$staged" 2>>"$LOG" || { slog "FAIL staging restore"; return 1; }
    mv -f "$staged" "$TAR_PATH" 2>>"$LOG" || { rm -f "$staged"; return 1; }
    rm -f "$WMG_STATE_DIR/repo-snapshot.last"   # tar is no longer ours
    slog "repo.tar restored to original: $(basename "$o")"
    echo "[repo-snap] repo.tar restored to the latest original snapshot."
    return 0
}

case "${1:---status}" in
    --status)           do_status ;;
    --dry-run)          do_apply dry ;;
    --apply)            do_apply full ;;
    --apply-auto)       do_apply_auto ;;
    --restore-original) do_restore_original ;;
    *)
        echo "usage: repo-snapshot.sh --status | --dry-run | --apply | --apply-auto | --restore-original"
        exit 2 ;;
esac
exit $?
