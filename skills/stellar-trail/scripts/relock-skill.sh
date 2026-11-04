#!/usr/bin/env bash
# ============================================================================
# relock-skill.sh — re-pin skills-lock.json computedHash to the CURRENT tree
# stellar-trail · bundled asset (owner order #2, Task 68, v5.7.0)
#
# WHAT THIS SOLVES:
#   The skills CLI (<project>/skills-lock.json) pins each installed skill's
#   tree hash (computedHash). `npx skills add` rewrites the pin, but a MANUAL
#   deploy (dev-repo -> live skills/stellar-trail) does not — the pin goes
#   stale and `skills experimental_install --frozen-lockfile` then treats the
#   live tree as "changed since skills-lock.json was written". This script
#   recomputes the hash with the CLI's OWN algorithm and rewrites the pin.
#
# ALGORITHM (extracted from skills@1.7.6 dist, computeSkillFolderHash):
#   sha256 over (relativePath + content) of every file under the skill dir,
#   excluding .git/ and node_modules/, sorted by relativePath (localeCompare).
#   Replicated 1:1 — byte-identical by construction. Sibling copy embedded in
#   scripts/update-skill.sh step [5/5] (that one must stay self-contained: the
#   install flow overwrites this very directory mid-run).
#
# Usage:
#   bash scripts/relock-skill.sh [--check] [skillDir] [skillName]
#     --check   verify only — report drift, never write (exit 1 on stale)
#     skillDir  default: <project>/skills/stellar-trail (auto-located)
#     skillName default: stellar-trail (the lock entry to re-pin)
# Exit: 0 relocked/already-current (or --check current) · 1 --check stale or
#       failure · 2 usage
# ============================================================================
set -u

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && { CHECK_ONLY=1; shift; }

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(dirname "$SELF_DIR")"

# project root: walk up from the skill root (same markers as update-skill.sh)
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
PROJECT="${PROJECT:-$(dirname "$SKILL_ROOT")}"

SKILL_DIR="${1:-$PROJECT/skills/stellar-trail}"
SKILL_NAME="${2:-stellar-trail}"
LOCKF="$PROJECT/skills-lock.json"

[ -d "$SKILL_DIR" ] || { echo "[relock] FAIL: skill dir not found: $SKILL_DIR"; exit 1; }
[ -f "$LOCKF" ]     || { echo "[relock] FAIL: no skills-lock.json at $LOCKF"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "[relock] FAIL: node not available"; exit 1; }

# the node core — identical to update-skill.sh step [5/5] (keep both in sync)
_rl="$(mktemp /tmp/stellar-relock.XXXXXX.js)" || exit 1
trap 'rm -f "$_rl"' EXIT
cat > "$_rl" <<'RELOCK_JS'
const {createHash} = require("crypto");
const {readdirSync, readFileSync, writeFileSync} = require("fs");
const {join, relative} = require("path");
const [dir, lockPath, name, checkOnly] = process.argv.slice(2);
function collect(baseDir, currentDir, results) {
  for (const entry of readdirSync(currentDir, {withFileTypes: true})) {
    const fullPath = join(currentDir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === ".git" || entry.name === "node_modules") continue;
      collect(baseDir, fullPath, results);
    } else if (entry.isFile()) {
      results.push({relativePath: relative(baseDir, fullPath).split("\\").join("/"), content: readFileSync(fullPath)});
    }
  }
}
const files = []; collect(dir, dir, files);
files.sort((a, b) => a.relativePath.localeCompare(b.relativePath));
const hash = createHash("sha256");
for (const file of files) { hash.update(file.relativePath); hash.update(file.content); }
const digest = hash.digest("hex");
const lock = JSON.parse(readFileSync(lockPath, "utf8"));
const entry = lock.skills && lock.skills[name];
if (!entry) { console.log("[relock] no lock entry for " + name + " — nothing to " + (checkOnly === "1" ? "check" : "relock")); process.exit(0); }
if (entry.computedHash === digest) {
  console.log("[relock] pin CURRENT (" + digest.slice(0, 8) + ") — matches the " + name + " tree");
  process.exit(0);
}
if (checkOnly === "1") {
  console.log("[relock] pin STALE: lock " + entry.computedHash.slice(0, 8) + " != tree " + digest.slice(0, 8) + " (run without --check to relock)");
  process.exit(1);
}
const old = entry.computedHash;
entry.computedHash = digest;
writeFileSync(lockPath, JSON.stringify(lock, null, 2) + "\n");
console.log("[relock] RELOCKED " + name + ": " + (old ? old.slice(0, 8) : "none") + " -> " + digest.slice(0, 8));
RELOCK_JS

node "$_rl" "$SKILL_DIR" "$LOCKF" "$SKILL_NAME" "$CHECK_ONLY"
