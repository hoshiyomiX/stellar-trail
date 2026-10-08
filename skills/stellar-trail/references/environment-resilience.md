# Environment Resilience — Anti-Rollback Playbook (Container Platforms)

> **When to read this file:** your working environment runs in a resettable container/sandbox
> (e.g. a platform preview container, an ephemeral CI runner) AND you see the symptoms: work
> files "disappearing" after a restart, file versions degraded to an older state, or custom
> skills/scripts vanishing. If you work on a local/static machine that is never reset, this
> section does not apply — ignore it.

## Table of Contents

1. Threat Model: How a Container Rolls Back Your State
2. Defense Layers
3. Using the Scripts — 3a snapshot · 3b single-repair doctrine · 3c watcher · 3d audit
4. Post-Reset Procedure (Decision Tree at a Fresh Boot)
5. Limits & Ethics
6. Design Receipts (verified field findings)
7. Consumer Sandbox Deployment — bootstrap-sandbox.sh
8. Crash-Safe Version Migration + M0 Forensics
9. Pre-Phase Auto-Update — update-skill.sh
Appendix: Standalone-Helper Doctrine — small cross-script duplication = by-design

## 1. Threat Model: How a Container Rolls Back Your State

Many container platforms restore the project directory from a **restore archive** (real example:
`/home/sync/repo.tar`, extracted by the `/start.sh` hook at boot — `rm -rf <project>` except
mountpoints, then `tar xf repo.tar`). This archive is ideally rewritten by a **pre-stop packer**
when the container stops. The problem: **pre-stop does not always run** — the container can be
crashed, force-killed, or the pack can fail (a failure branch the platform hook itself
acknowledges). The next boot then restores an **old state**: a silent rollback that erases hours
of work.

Four structural facts that can be exploited (verified empirically on a real container platform):

1. **The restore source is readable**: the boot hook and the restore archive can usually be read
   from inside the container (`cat` the hook, `tar -tf` the archive) — you can dissect the format
   instead of guessing.
2. **Object-storage mounts survive**: directories mounted from object storage (e.g. ossfs) live
   OUTSIDE the container and are not rolled back — the rescue channel for backups and state markers.
3. **Boot tolerates a corrupt archive** (warning + continue) — a failed refresh does not kill the
   container.
4. **The packer can exclude important directories** (real forensics: `skills/` never made it into
   the platform packer's archive) — a skill installation is the most frequent rollback victim.

## 2. Defense Layers

| Layer | Role | When it works |
|---|---|---|
| **L1 — Source refresh** (`scripts/snapshot-repo.sh`) | Overwrites the platform restore archive with a snapshot of the CURRENT state — now including `skills/stellar-trail` (surgical append) — so the native boot restore = fresh state *for as long as that archive survives* | `--apply` after significant milestones; `--apply-auto` periodically (debounce + 15-min cooldown) |
| **L2a — Cache-replay boot restore** (`scripts/bootstrap-sandbox.sh` → generated `.zscripts/dev.sh`) | At every boot, verifies `skills/stellar-trail` against the canonical copy's SHA-256 manifest (`download/stellar-trail/`) and restores it byte-identically when broken or missing — with a **no-downgrade version gate** (a healthy NEWER live install is never overwritten; a corrupt-but-newer install raises a watcher alarm instead of a silent repair) | Automatic at every boot; the canonical copy persists via the platform archive (which does include `download/`) |
| **L2b — Verify-only monitoring** (`scripts/watcher.sh`) | Periodic integrity verification of the installed copies against the checksum manifest; on failure: **alarm + the remediation message** (the single install command). NO automatic multi-source repair — by design | Watchdog loop, ~every 10 minutes |
| **L3 — Original backup** | Undo: the platform's original restore archive is copied before being overwritten — restorable at any time | Always, before every L1 swap |

L1 prevents rollback **at its source**; L2a **restores the installation** from the canonical
bytes when a rollback or clobber still happens; L2b **detects and reports** drift that the boot
restore could not cover; L3 guarantees every infrastructure intervention **can be undone**. The
layers are mutually independent — one layer's failure does not disable the others. Real repair —
when even the canonical copy is bad — is NOT a layer: it is the single install command
(`npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw -y`), the one and
only installation flow, executed deliberately with full verification (see section 9).

**Architecture finding (boot forensics):** the platform pre-stop packer actually OVERWRITES the
restore archive with its own at every stop cycle — our L1 build (including the
`skills/stellar-trail` surgical append) never survives across boots. Evidence: a morning boot
found a "foreign" repo.tar (0 `skills/` entries) and the `skills/stellar-trail` directory gone
entirely, even though the previous night's L1 build carried 32 skill entries. Consequence, layer
roles shifted: **the truly effective cross-boot chain = the canonical `download/stellar-trail/`
(persistent via the platform archive, which does include `download/`) + the L2a boot restore**.
L1 remains valuable for intra-boot freshness (repo.tar never >15 min stale) and the L3 undo
channel.

**Two install-location conventions:** CLI installs may land owner-scoped
(`skills/@owner/stellar-trail`) or flat (`skills/stellar-trail`). The entire chain and the boot
hook are **location-aware**: they find and handle BOTH layouts.

**Why there is no shadow-backup layer and no multi-source self-repair:** an earlier generation of
this package shipped both, and field forensics condemned each for the same underlying reason — a
protection layer whose restore path was never tested, or a healer with ranked sources and silent
repairs, ADDS failure modes instead of removing them (false-positive restore attempts, the same
blind spots as the thing being protected, shared failure domains, a 62 MB/30-min write cost for
illusory protection, and a poisoned source once winning a version race). The general lessons:
**a backup whose restore path was never tested is more dangerous than no backup**, and **a healer
with six sources and silent repairs is a second, poisonable installer**. The current doctrine:
one installer, one source of truth, zero silent repairs — restore = the boot cache replay from
the ONE canonical copy, detect = verify-only monitoring, repair = THE install command.

## 3. Using the Scripts

### 3a. `scripts/snapshot-repo.sh` (L1 — restore-archive refresh)

```
bash scripts/snapshot-repo.sh --status             # diagnosis: restore-archive age, STALE/FRESH verdict
bash scripts/snapshot-repo.sh --dry-run            # build + full verification WITHOUT touching the archive
bash scripts/snapshot-repo.sh --apply              # backup original -> build -> verify -> swap -> verify
bash scripts/snapshot-repo.sh --apply-auto         # --apply with double gating (debounce + cooldown) —
                                                   # safe to call periodically from the boot hook / watcher
bash scripts/snapshot-repo.sh --restore-original   # undo: restore the latest original archive (verified)
```

Security principles the script holds (do not violate them when modifying):

- **Explicit consent for manual actions**: `--apply`/`--restore-original` run only on request;
  `--apply-auto` is deliberately heavily gated (debounce + cooldown) so it is safe to trigger periodically.
- **Backup-first**: the original archive is copied to a persistent mount BEFORE the swap; if the
  backup fails, the swap is cancelled.
- **Verify-before-swap**: the tar is validated (structure + entry count + key entries) twice —
  build and staging — before the rename-overwrite; verified again after the swap.
- **Anti-traversal member audit**: the platform extracts the restore archive via `tar xf` with no
  member validation, so the script guards it itself: absolute members or any `..` component are
  HARD-REJECTED, absolute-target symlinks are warned; `--restore-original` is audited before its
  swap too (undo stays byte-identical — verification only reads; a corrupt/hostile archive is
  rejected so it cannot break the next boot).
- **Anti argument-injection build**: NUL-separated entry list via `tar --null -T` — file names
  are never parsed as tar options (a file named `--use-compress-program=...` in the project root
  cannot make tar execute a command); names starting with `-` or containing a newline are skipped.
  Output discipline: functions producing data on stdout must not print diagnostics to stdout
  (`slog_q` logs only) — leaked diagnostics would be read as list entries.
- **Fingerprint marker**: our own archive is marked (mtime|size) so it is never backed up twice
  and a true original backup is never overwritten (lesson from a second-resolution name-collision bug).
- **Format follows the platform packer**: relative entries without the `./` prefix, excludes
  `node_modules/`, `db/`, `upload/`, `.venv/`, `.next/` — a different format = weird restores.
  The packer's `skills/` exclusion is closed by the `skills/stellar-trail` surgical append
  (literal path, not a file-name expansion — the injection vector does not apply).
- **As atomic as the mount allows**: build on local disk -> copy to a staging name on the same
  mount -> in-mount rename-overwrite (rename is generally supported by FUSE object storage).

### 3b. Single-repair doctrine (no parallel installer)

The package intentionally ships NO self-repair installer and NO alternate repair sources.
Integrity verification is verify-only (the watcher, §3c): when drift or damage is detected, the
alarm names THE install command, and real repair = re-running it deliberately (section 9 runs the
same flow with verification). Manifest regeneration is a release-time maintainer action, not a
runtime script. One installer, one source of truth, zero silent repairs.

### 3c. `scripts/watcher.sh` (runtime watchdog, verify-only monitoring)

```
bash .zscripts/watcher.sh --ensure        # start if not running (idempotent; dev.sh + M0 call this)
bash .zscripts/watcher.sh --status        # daemon status via PIDFILE (never trust pgrep — see §6)
bash .zscripts/watcher.sh --stop          # stop + set the stop-flag
bash .zscripts/watcher.sh --force-start   # start even with a stop-flag present
```

The 30-second loop runs six checks: (1) download/ change trigger → dev.sh; (2) explorer health →
auto-restart via explorer.sh --ensure (skipped when a Next.js project owns the preview port);
(3) release-file guard — `skill-card.md` + `assets/integrity.sha256` in the canonical copy must
exist and stay version-fresh, restored ONLY from a healthy local same-version install (no vault,
no network); (4) installation integrity ~every 10 minutes — **verify-only**: on manifest
failure it logs `INTEGRITY ALARM` with the remediation message (`npx skills add
hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw -y`); there is no silent repair by
design; (5) archive refresh ~every 15 minutes via repo-snapshot.sh --apply-auto; (6) compliance
sentinel ~every 2 minutes — alarms in the worklog when it grows without an M1 checkpoint. The
daemon survives per-tool-call process cleanup as a double-fork orphan (PPID=1, setsid).

### 3d. `scripts/audit-compliance.sh` (compliance audit from OUTSIDE the model)

Marker-less responses raise no errors at all — silent non-compliance is invisible to the model
itself. This script does NOT trust model discipline: it reads artifacts on disk and issues a
PASS/WARN/FAIL verdict + exit code (0 = no FAIL).

```
bash scripts/audit-compliance.sh [--root <project-root>] [--quiet]
```

Checks: **C1** memory/SESSION-STATE.md exists · **C2** Active-table hygiene (H2 — terminal rows
in the active table = FAIL) · **C3** worklog-vs-SESSION-STATE staleness (an active worklog with
no M1 checkpoint >30 min = WARN — the incident signature) · **C4** installed-vs-canonical
version sanity (4c) · **C5** R1 hook present at the worklog tail. Its companion pattern (**R2**,
per-project infra — not bundled): the **watcher sentinel** — the watchdog's compliance check
detects the same signature every ~2 minutes and appends a COMPLIANCE-ALARM to the worklog tail,
an anchor the next session is guaranteed to read. Together they close the "invisible
non-compliance" gap from outside the model.

## 4. Post-Reset Procedure (Decision Tree at a Fresh Boot)

1. **Detect whether a rollback/degrade happened**: quick symptoms — newest files missing, or
   the M0 version sanity alarm fired (installed banner version older than the release recorded
   in memory), or `INTEGRITY ALARM` lines from the watcher in `.zscripts/watcher.log`.
2. **Drift detected** ⇒ re-run THE install command — `npx skills add hoshiyomiX/stellar-trail
   --skill stellar-trail -a openclaw -y` (or `bash skills/stellar-trail/scripts/update-skill.sh
   --force`): the single flow re-installs verified bytes; then run L1 `--apply` so the source
   archive is fresh too; `git status` for extra leftover files from the restore.
3. **The canonical copy is gone too** (total wipe of `download/`) ⇒ the install command rebuilds
   it — run `bash skills/stellar-trail/scripts/bootstrap-sandbox.sh --ensure` after installing
   to re-seed the canonical + arm the boot hook (explorer/snapshot/hooks auto-enable; the hooks
   module also seeds CLAUDE.md + AGENTS.md at the project root, create-if-absent); repo.tar's
   `skills/stellar-trail` append (L1) is a same-boot fallback while the archive survives. If
   the agent's response banner still shows an old version after all this, see the skill-card
   Known Risks: the continuation-activation failure mode (rule 11).
4. **Nothing happened** ⇒ just ensure L1 is fresh if you are about to stop/rest.
5. **memory/ is gone too** (total reset) ⇒ recover from the latest handoff on the persistent
   mount; if none exists, run the cold-start protocol (Part II section 2) — never claim "no
   history" before checking every channel.

## 5. Limits & Ethics

- Never run L1 on an environment you do not own — overwriting the restore archive is an
  infrastructure intervention; it is only legitimate when the environment's owner requests it.
- The L1 archive includes `skills/stellar-trail` via surgical append, and its recovery channels
  are layered: that archive (L1) → the boot cache replay from canonical (L2a) → re-install via
  the single install command (the final resort, fully verified).
- These scripts handle the RESTORE ARCHIVE and the SKILL INSTALLATION; they do not replace
  `git`: commits remain the source of truth for diff/status; snapshots are for disaster recovery.

## 6. Design Receipts (verified field findings)

Recorded as receipts so the design can be audited, not accepted on faith:

- **Boot = wipe + extract**: the platform boot hook removes the project tree (except
  mountpoints) and extracts the restore archive; the packer EXCLUDES `skills/` — a skill
  installation is the most frequent rollback victim. A boot restore hook + a canonical copy on
  a preserved path is therefore mandatory (L2a).
- **The pre-stop packer overwrites the restore archive at every stop cycle** — an L1 build does
  not survive across boots; the effective cross-boot chain is canonical `download/` + the boot
  restore (§2 architecture finding).
- **`pgrep -f watcher.sh` is a false negative** (the daemon runs as an orphan inline `bash -c`,
  not matched by the pattern); watcher status MUST be checked via `watcher.sh --status`
  (PIDFILE), never pgrep.
- **Verification is mandatory after EVERY edit, including the last one** — an "everything
  aligned" checkpoint taken before a final edit is exactly how manifest-lag ships (a real
  post-reset audit caught a receipt edit that landed after the final manifest regen).
- **Boot traces in `.zscripts/boot.log` are reversible after the hook** (a root-level actor
  re-extracted the workspace archive after dev.sh finished — the entire morning's hook trace
  gone from the log); for M0 forensics use sources OUTSIDE the restore tree (`/tmp` boot
  timeline, snapshot state, live `ps`).
- **Ordinary processes die when a tool call finishes** (the platform kills the descendant
  tree); the only way a daemon stays alive is a double-fork orphan (PPID=1 + setsid).
- **A pinned skill blocks its own update and can make bulk updates skip it SILENTLY**
  (success-looking no-ops) — never pin this skill.
- **Object-storage mounts (e.g. ossfs `upload/`) live outside the container** and are not
  rolled back — the rescue channel for state markers.
- **An alive-but-stale deployment is a real failure mode** (files updated, the running process
  still serving old code): freshness checks must compare CONTENT (code stamps / md5), not
  mtimes.

## 7. Consumer Sandbox Deployment — `bootstrap-sandbox.sh`

The persistence layers above need to be installed in a consumer sandbox too — and a fresh
install has none of them. `scripts/bootstrap-sandbox.sh` installs the same architecture in ONE
command:

| Module | Installed | Single path (no redundant fallbacks) |
|---|---|---|
| core (always) | canonical `download/stellar-trail/` + `.zscripts/dev.sh` + `.zscripts/watcher.sh` + `worklog.md` seed (R1 hook) + `memory/` scaffolding | seed = a copy of the live installation (self-locating, offline); dev.sh restores `skills/stellar-trail` from the canonical at every boot (SHA-256 manifest verification + the no-downgrade version gate); the runtime watchdog (explorer health + verify-only integrity checks + release-file guard with local-only restore + archive refresh + compliance alarm), started by dev.sh |
| explorer (auto-enabled) | `.zscripts/{explorer.sh, explorer.py, explorer-ui/}` + an `--ensure` step in dev.sh | self-locating launcher + drift-sync from canonical; the Next.js guard still applies |
| snapshot (auto-enabled) | `.zscripts/repo-snapshot.sh` + an `--apply-auto` step in dev.sh | the `WMG_PROJECT` env is forwarded by dev.sh (for platforms with `/home/sync`) |

What survives resets (packer contract, verified from the original archive): `download/` +
`.zscripts/` + `memory/` + `worklog.md`. What gets wiped: `skills/` — exactly what dev.sh
restores from the canonical.

Commands: `bash scripts/bootstrap-sandbox.sh` (core + auto-enabled modules) · `--ensure`
(idempotent, invoked by Activation rule 14 at M0) · `--with-explorer` / `--with-snapshot`
(force-on) · `--without-explorer` / `--without-snapshot` (opt-out) · `--status` (read-only) ·
`--project-dir` · `--force-devsh` (overwrite a non-bootstrap dev.sh — the reference deployment
is never overwritten without this flag).

Discipline held: idempotent (writes only when content differs); NEVER overwrites `memory/`,
`worklog.md`, or a foreign dev.sh; the memory scaffold carries consent-pending status
(SKILL.md 4b) — the first session must ask the user for confirmation before writing substantive
state. Hardening (lifecycle-validated 16/16): the generated hook's restore step carries the
no-downgrade version gate, and the generated hook itself is syntax-checked (`bash -n`) at
generation time — a heredoc typo dies at generation, never inside `/start.sh` at next boot.

## 8. Crash-Safe Version Migration + M0 Forensics

Two lessons from consumer forensic reports:

**Crash-safe migration order (R2/F5).** The order "swap the working directory FIRST, refresh
the resilience layers after" opens a mixed-version window (~4 minutes observed in the field)
with no runtime safety net: a crash inside that window → the next boot restores an old archive →
recovery converges to the OLD version and the migration must be repeated manually. The safe
order: (1) prepare the new-version source (verified clone), (2) swap the canonical
`download/stellar-trail/` to the new version, (3) redeploy the watcher from the new canonical,
(4) ONLY THEN swap the live working install `skills/stellar-trail` LAST. With this order a
crash at any point converges the next boot to the NEW version (every restore source is already
new; the live swap is the cheapest step to repeat).

**Restore-immune forensic sources for M0 (R4/F3).** Boot traces in `.zscripts/boot.log` were
PROVEN reversible after the hook: a root-level actor re-extracted the workspace archive AFTER
dev.sh finished (the hook demonstrably ran, yet boot.log came back byte-identical to the
archived copy — the entire morning's hook trace gone; pids/logs back to old mtimes; the hook
"never ran" as far as the log showed). For M0 forensics, use sources OUTSIDE the restore tree:
`/tmp/boot-timeline.log` (written by /start.sh), `/home/sync/repo-state/*` (auto-apply
snapshots), and `ps` (live processes) — never boot.log alone.

**Audit rhythm (R6).** Run `scripts/audit-compliance.sh` at major M0/M1 checkpoints — this
external audit is the only tool that mechanically catches version-lock and hook drift (see also
SKILL.md section 3 M1).

## 9. Pre-Phase Auto-Update — `update-skill.sh`

Section 7 installs the defense layers; section 8 repairs migration damage; this section closes
the remaining gap: **an installation that is healthy but OLD** — not broken, not a manual
migration, just behind a release. The protocol calls `scripts/update-skill.sh --ensure` at M0,
after `bootstrap --ensure`, BEFORE the phases begin (Activation rule 15).

**Trigger — always check.** Invoked at every M0 and the network check ALWAYS runs (a 24h
debounce gate was removed after it hid same-day releases behind a stale window — every M0
inside the window skipped the probe entirely, and the skip line read as the feature being
broken). M0 stays cheap and offline-first: one anonymous `git ls-remote` (~2 s, 25 s timeout),
and an unreachable origin is a one-line report with exit 0. `.zscripts/.update-check.last`
remains as a record for `--status` (never a gate); `--force` is a compatibility alias,
`--check` a dry-run. The runtime watcher (duty 7) adds an independent background probe every
~24h — epoch-state-gated so container reboots do not reset the clock, offline-tolerant with a
~1h retry — that raises a one-line worklog alarm when the origin carries a NEWER release tag
(once per unseen version, remediation = the install command). ALARM-ONLY: the watcher never
installs. The watcher also raises a one-line NOTICE (watch log + worklog, once per gap episode)
when the explorer payload is installed but `.zscripts/explorer.sh` is not deployed — the
fresh-install observability gap (suppressed when a `package.json` owns the preview URL; it
never installs anything).

**Semantics: a VERIFIED override, not a blind pull.** Origin = GitHub hoshiyomiX/stellar-trail
(the sole channel, public read, no PAT). The check: `git ls-remote` latest tag → staging clone
`--depth 1 --branch` → full SHA-256 manifest verification → tag≡content assert (anti-poisoning:
a tag containing another version's content = hard abort exit 1) → anti-downgrade assert (an
origin older than local = refused). Copying corruption is not healing — and copying an
unverified source is not an upgrade.

**The install IS the single flow.** When the origin is newer, the wrapper runs THE install
command — `npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw -y` — as
step `[1/4]` of a verified override, then verifies the landed bytes against the manifest, swaps
targets with per-target rollback backups (`.update-bak`), and finishes with canonical-first →
live-last ordering per the section 8 doctrine (a crash anywhere converges the next boot to the
NEW version). The script copies itself to a temp file and re-execs from there before swapping
(overwriting the directory a running script lives in is undefined behavior); file modes
normalize to 0644 (the package-wide exec-bit doctrine).

**Offline = a report, not a block.** Network/git failure → a one-line report, exit 0 — M0 never
depends on the network (the boot chain stays offline-first; the boot cache replay and the
watcher remain the offline safety nets). The whole installation process prints to stdout step
by step (`[1/4]`…`[4/4]`) — the user stays informed and can follow up. After an update lands,
response banners carry the new version; the skill body is reloaded next session (Activation
rule 11).

**Post-install module arming.** Empirical basis: a consumer install + bootstrap-ensure report —
the install succeeded and the canonical was fresh, BUT the post-update bootstrap ran core-only:
the persistence layer came up half-armed (explorer dead, snapshot not installed) until the user
remembered to run `--with-*` manually. The final step therefore runs `--ensure
--with-explorer --with-snapshot --with-harness-hooks`: after an update, the layer comes up
FULLY armed. Override: env `STELLAR_UPDATE_BOOTSTRAP_ARGS` (e.g. `"--ensure"` for the old
core-only behavior). Posture note: the fresh-install path auto-enables the modules too — a
plain `--ensure` arms explorer + snapshot + hooks whenever their payload ships in the install
tree (`--without-*` opts out, including disarming a module armed by a previous run).

## Appendix: Standalone-Helper Doctrine — Small Cross-Script Duplication = By-Design

> Recorded explicitly so future audits do not re-flag it as a redundancy finding.

Every script in this package (`update-skill.sh`, `snapshot-repo.sh`, `bootstrap-sandbox.sh`,
`watcher.sh`, `enforce-gates.sh`, `audit-compliance.sh`, plus the explorer assets
`explorer.sh`/`explorer.py`/`dev.sh.template`) carries its own small helpers — `log`/`say`/`ts`/
`die` variants. A classic DRY refactor would unify these into one shared library; this
package's resilience doctrine FORBIDS it: **every script must keep standing alone when its
siblings break or are deleted**. A repair script must be able to fix its sibling exactly when
that sibling — and any shared library — is itself broken; an entire fallback chain once died
together from sharing one failure point. Duplicating 3–8 lines per helper is a consciously paid
price for **failure-domain isolation**; cross-file consolidation is NOT recommended. The one
exact duplicate in this package is `version_lt()` (8 lines; exactly TWO locations — a controlled
pair: `update-skill.sh` + the `bootstrap-sandbox.sh` generated-hook version gate) — kept with
controlled-copy comments at both locations: change them together, never merge them.
