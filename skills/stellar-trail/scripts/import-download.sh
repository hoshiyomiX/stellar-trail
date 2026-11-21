#!/usr/bin/env bash
# ============================================================================
# import-download.sh — download/ → .zscripts/ importer v1.0 (Task 84 / v5.7.10)
# stellar-trail · owner order #1 "add force copy files ke ..zscripts/ jika di
# folder download (default z.ai path) masih ada"
#
# WHAT THIS DOES (owner-confirmed semantics, session 74 clarification):
#   MOVE semantics — every top-level entry of download/ (the default z.ai
#   delivery path) is force-copied into .zscripts/ (overwrite allowed) and,
#   ONLY after a byte-exact verification of the copy, the original in
#   download/ is removed. Idempotent: an empty/absent download/ is a silent
#   no-op; a re-delivered file overwrites the .zscripts/ copy again.
#
#   Exceptions (never moved):
#     · ^ALERT* files — the watcher ALERT surface lives in download/
#       (ALERT-ACTIVE.md) and must stay there (platform-panel visibility,
#       duty-1 hash exclusion) — it is ALSO mirrored to .zscripts/ALERT-ACTIVE.md
#       by the sentinel since ROOTS became .zscripts/-only (explorer.py v1.13).
#     · PROTECTED operational names — an entry whose name collides with the
#       persistence layer's operational surface in .zscripts/ (dev.sh,
#       explorer.py, watcher.sh, stellar-trail-canonical/, *.pid, *.log, …)
#       is SKIPPED (left in download/) and noticed ONCE per episode — moving
#       it would overwrite live infrastructure. The list mirrors explorer.py
#       v1.13's HIDE_DIRS/HIDE_FILES/HIDE_SUFFIXES — keep the two in sync.
#
# INVOCATION:
#   bash scripts/import-download.sh            # run the import (default)
#   bash scripts/import-download.sh --run      # same
#   bash scripts/import-download.sh --dry-run  # print what would happen
#   STELLAR_PROJECT=/path bash scripts/import-download.sh   # non-default root
#
# Invoked by watcher.sh v2.5 duty 2d EVERY cycle (before the duty-1 download/
# hash, so a delivery is imported and the hash settles in one pass) and
# runnable manually at any time. Exit codes: 0 = ok / nothing to do (some
# items may have failed — they are logged and retried next cycle; a hard
# non-zero would make the watcher treat the whole duty as broken), 2 = usage.
# ============================================================================
set -u

PROJECT="${STELLAR_PROJECT:-/home/z/my-project}"
DOWNLOAD="$PROJECT/download"
ZDIR="$PROJECT/.zscripts"
WORKLOG="$PROJECT/worklog.md"
SKIP_STATE="$ZDIR/.import-skip.noticed"

# --- operational surface of .zscripts/ (MIRROR of explorer.py v1.13
#     HIDE_DIRS/HIDE_FILES/HIDE_SUFFIXES — keep in sync with that file) ------
PROTECTED_DIRS="explorer-ui stellar-trail-canonical"
PROTECTED_FILES="dev.sh dev.sh.foreign.bak explorer.py explorer.sh explorer.log \
explorer.pid explorer.port explorer.code-stamp watcher.sh watcher.log \
watcher.pid repo-snapshot.sh boot.log bootstrap.state ALERT-ACTIVE.md"
PROTECTED_SUFFIXES=".pid .log .port .state .code-stamp .noticed .probe .stop"

DRY_RUN=0
case "${1:-}" in
  "") ;;
  --run) ;;
  --dry-run) DRY_RUN=1 ;;
  -h|--help) sed -n '2,40p' "$0" | sed "s/^# \{0,1\}//"; exit 0 ;;
  *) echo "usage: $0 [--run|--dry-run]" >&2; exit 2 ;;
esac

ts() { date "+%F %T"; }

is_protected() {
  # $1 = entry name; returns 0 when the name collides with the operational set
  local n="$1" d
  for d in $PROTECTED_DIRS; do [ "$n" = "$d" ] && return 0; done
  for d in $PROTECTED_FILES; do [ "$n" = "$d" ] && return 0; done
  for d in $PROTECTED_SUFFIXES; do case "$n" in *"$d") return 0 ;; esac; done
  case "$n" in .*) return 0 ;; esac   # hidden dotfiles are operational state
  return 1
}

[ -d "$DOWNLOAD" ] || exit 0
# shellcheck disable=SC2012  # filenames here are owner deliveries, not newlines
ENTRIES="$(ls -A "$DOWNLOAD" 2>/dev/null)"
[ -n "$ENTRIES" ] || exit 0

MOVED=0; FAILED=0; MOVED_NAMES=""; SKIP_NAMES=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  case "$name" in ALERT*) SKIP_NAMES="$SKIP_NAMES $name"; continue ;; esac
  if is_protected "$name"; then SKIP_NAMES="$SKIP_NAMES $name"; continue; fi
  SRC="$DOWNLOAD/$name"
  DST="$ZDIR/$name"
  if [ "$DRY_RUN" = 1 ]; then
    echo "[$(ts)] [import-download] would move: $name"
    continue
  fi
  # force-copy (overwrite allowed), verify byte-exact, then remove the source
  if [ -d "$SRC" ]; then
    rm -rf "$DST.tmp-import" 2>/dev/null
    cp -a "$SRC" "$DST.tmp-import" 2>/dev/null && \
      diff -r -q "$DST.tmp-import" "$SRC" >/dev/null 2>&1 && \
      rm -rf "$DST" && mv "$DST.tmp-import" "$DST" && rm -rf "$SRC" || {
        rm -rf "$DST.tmp-import"; FAILED=$((FAILED+1));
        echo "[$(ts)] [import-download] FAILED (dir): $name — left in download/, retried next cycle"; continue; }
  else
    cp -a "$SRC" "$DST.tmp-import" 2>/dev/null && \
      cmp -s "$DST.tmp-import" "$SRC" && \
      mv -f "$DST.tmp-import" "$DST" && rm -f "$SRC" || {
        rm -f "$DST.tmp-import"; FAILED=$((FAILED+1));
        echo "[$(ts)] [import-download] FAILED (file): $name — left in download/, retried next cycle"; continue; }
  fi
  MOVED=$((MOVED+1)); MOVED_NAMES="$MOVED_NAMES $name"
done <<EOF
$ENTRIES
EOF

if [ "$DRY_RUN" = 1 ]; then
  [ -n "$SKIP_NAMES" ] && echo "[$(ts)] [import-download] skip (ALERT/protected):$SKIP_NAMES"
  exit 0
fi

# worklog ledger line — ONE line per episode with movement (machine-source,
# [CRON]-class: exempt from task triage, never open work)
if [ "$MOVED" -gt 0 ]; then
  NAMES_TRIMMED="$(echo "$MOVED_NAMES" | sed "s/^ //" | cut -c1-300)"
  printf "\n> IMPORT-DOWNLOAD %s: %s entr%s moved download/ -> .zscripts/ (watcher duty 2d, v5.7.10 — move semantics: force-copy + byte-verify + source removal):%s\n" \
    "$(ts)" "$MOVED" "$([ "$MOVED" = 1 ] && echo y || echo ies)" "$NAMES_TRIMMED" >> "$WORKLOG" 2>/dev/null
  echo "[$(ts)] [import-download] moved $MOVED entr$([ "$MOVED" = 1 ] && echo y || echo ies):$MOVED_NAMES"
fi

# protected-collision notice — once per episode-set (state-gated like the
# other watcher notices; re-notices only when the skip SET changes)
if [ -n "$SKIP_NAMES" ]; then
  SKIP_SET="$(echo "$SKIP_NAMES" | tr " " "\n" | sed "/^$/d" | sort | tr "\n" " " | sed "s/ $//")"
  LAST_SET=""
  [ -f "$SKIP_STATE" ] && LAST_SET="$(cat "$SKIP_STATE" 2>/dev/null)"
  if [ "$SKIP_SET" != "$LAST_SET" ]; then
    printf "%s" "$SKIP_SET" > "$SKIP_STATE" 2>/dev/null
    echo "[$(ts)] [import-download] SKIP (ALERT/protected name collision — left in download/):$SKIP_NAMES — rename the delivery to import it"
  fi
else
  rm -f "$SKIP_STATE" 2>/dev/null
fi

[ "$FAILED" -gt 0 ] && echo "[$(ts)] [import-download] episode done: $MOVED moved, $FAILED failed (retry next cycle)"
exit 0
