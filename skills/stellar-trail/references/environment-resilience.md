# Environment Resilience — Anti-Rollback Playbook (Container Platforms)

> **When to read this file:** your working environment runs in a resettable container/sandbox AND you see the symptoms: work files "disappearing" after a restart, versions degraded to an older state, or skills/scripts vanishing. On a local/static machine that is never reset, ignore this file.

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

Many container platforms restore the project directory from a **restore archive** (real example: `/home/sync/repo.tar`, extracted by the `/start.sh` hook at boot — `rm -rf <project>` except mountpoints, then `tar xf repo.tar`), ideally rewritten by a **pre-stop packer**. The problem: **pre-stop does not always run** (crash, force-kill, pack failure) — the next boot then restores an **old state**: a silent rollback that erases hours of work.

Four structural facts that can be exploited (verified empirically):

1. **The restore source is readable** — the boot hook and archive can be read from inside; dissect the format instead of guessing.
2. **Object-storage mounts survive** (e.g. ossfs) — outside the container, not rolled back; the rescue channel for backups and state markers.
3. **Boot tolerates a corrupt archive** (warning + continue) — a failed refresh does not kill the container.
4. **The packer can exclude important directories** (real forensics: `skills/` never made it into the platform archive) — a skill installation is the most frequent rollback victim. Platform generations differ (the 2026-10-23 upgrade restart preserved the FULL workspace, mtimes intact) — treat the exclusion list as the documented MINIMUM, never a promise; the defenses hold under both extremes.

## 2. Defense Layers

| Layer | Role | When it works |
|---|---|---|
| **L1 — Source refresh** (`scripts/snapshot-repo.sh`) | Overwrites the platform restore archive with a snapshot of the CURRENT state — including `skills/stellar-trail` (surgical append) — so the native boot restore = fresh state *for as long as that archive survives*; original backups pruned to the NEWEST ONLY (v5.7.0) | `--apply` after significant milestones; `--apply-auto` periodically (debounce + 15-min cooldown) |
| **L2a — Cache-replay boot restore** (`bootstrap-sandbox.sh` → generated `.zscripts/dev.sh`) | At every boot, verifies `skills/stellar-trail` against the canonical copy's SHA-256 manifest (`download/stellar-trail/`) and restores it byte-identically when broken or missing — with a **no-downgrade version gate** (a healthy NEWER live install is never overwritten; a corrupt-but-newer install raises a watcher alarm instead of a silent repair) | Automatic at every boot; the canonical copy persists via the platform archive (which does include `download/`) |
| **L2b — Verify-only monitoring** (`scripts/watcher.sh`) | Periodic integrity verification against the checksum manifest; on failure: **alarm + the remediation message** (the single install command). NO automatic multi-source repair — by design | Watchdog loop, ~every 10 minutes; started at boot (dev.sh) and at every `bootstrap --ensure` — the daemon can die silently at container lifecycle events, so the session path matters |
| **L3 — Original backup** | The platform's original restore archive is copied before being overwritten — restorable at any time | Always, before every L1 swap |

L1 prevents rollback at its source; L2a restores the installation from canonical bytes when a rollback still happens; L2b detects and reports drift the boot restore could not cover; L3 guarantees every intervention can be undone. The layers are mutually independent. Real repair — when even the canonical copy is bad — is NOT a layer: it is the single install command (`npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw -y`), the one and only installation flow, executed deliberately with full verification (section 9).

**Architecture finding (boot forensics):** the platform pre-stop packer OVERWRITES the restore archive with its own at every stop cycle — our L1 build never survives across boots (a morning boot found a "foreign" repo.tar with 0 `skills/` entries and the live skill directory gone, though the previous night's L1 build carried 32 skill entries). The truly effective cross-boot chain = the canonical `download/stellar-trail/` + the L2a boot restore. L1 remains valuable for intra-boot freshness (repo.tar never >15 min stale) and the L3 undo channel.

**Two install-location conventions:** CLI installs may land owner-scoped (`skills/@owner/stellar-trail`) or flat (`skills/stellar-trail`) — the chain and boot hook are location-aware and handle BOTH.

**Why there is no shadow-backup layer and no multi-source self-repair:** an earlier generation shipped both; field forensics condemned each for the same reason — an untested restore path or a healer with ranked sources and silent repairs ADDS failure modes (false-positive restores, shared blind spots, a 62 MB/30-min write cost for illusory protection, a poisoned source once winning a version race). Lessons: **a backup whose restore path was never tested is more dangerous than no backup**; **a healer with six sources and silent repairs is a second, poisonable installer**. Doctrine: one installer, one source of truth, zero silent repairs — restore = the boot cache replay from the ONE canonical copy, detect = verify-only monitoring, repair = THE install command.

**v5.7.0 hardening (Task 68, owner order #2):** (a) the boot hook's skill restore now runs CANONICAL HYGIENE — when the live tree verifies against the manifest, snapshot-ONLY files are deleted from the canonical copy at every boot (the packer can resurrect a pre-prune `download/` with stale extras — measured 2026-11-04: 14 v3.6.5-era files sat one `cp -a` away from the live tree); (b) `update-skill.sh` relocks the skills-lock.json pin after every install (step 5/5 — the CLI's own hash algorithm, replicated from skills@1.7.6; standalone re-pin: `scripts/relock-skill.sh --check`); (c) after any version-changing update the session MUST reload the protocol body before continuing — never run stale skill logic.

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

- **Explicit consent for manual actions**: `--apply`/`--restore-original` run only on request; `--apply-auto` is heavily gated (debounce + cooldown) so it is safe to trigger periodically.
- **Backup-first**: the original archive is copied to a persistent mount BEFORE the swap; a failed backup cancels the swap.
- **Verify-before-swap**: the tar is validated (structure + entry count + key entries) twice — build and staging — before the rename-overwrite; verified again after.
- **Anti-traversal member audit**: the platform extracts via `tar xf` with no member validation, so the script guards it itself — absolute members or any `..` component are HARD-REJECTED, absolute-target symlinks warned; `--restore-original` is audited before its swap too (a corrupt/hostile archive is rejected so it cannot break the next boot).
- **Anti argument-injection build**: NUL-separated entry list via `tar --null -T` — file names are never parsed as tar options (a file named `--use-compress-program=...` cannot make tar execute a command); names starting with `-` or containing a newline are skipped. Data-producing functions never print diagnostics to stdout (`slog_q` logs only) — leaked diagnostics would be read as list entries.
- **Fingerprint marker**: our own archive is marked (mtime|size) so it is never backed up twice and a true original backup is never overwritten.
- **Format follows the platform packer**: relative entries without `./`, excludes `node_modules/`, `db/`, `upload/`, `.venv/`, `.next/`; the packer's `skills/` exclusion is closed by the `skills/stellar-trail` surgical append (literal path — the injection vector does not apply).
- **Keep-latest original retention (owner order #1, v5.7.0)**: exactly ONE original repo.tar backup is kept (the newest) — older originals auto-deleted at every apply; `--restore-original` only ever consumes the newest.
- **As atomic as the mount allows**: build on local disk → copy to a staging name on the same mount → in-mount rename-overwrite.

### 3b. Single-repair doctrine (no parallel installer)

The package intentionally ships NO self-repair installer and NO alternate repair sources. Verification is verify-only (§3c): when drift is detected, the alarm names THE install command, and real repair = re-running it deliberately (section 9). Manifest regeneration is a release-time maintainer action, not a runtime script. One installer, one source of truth, zero silent repairs.

### 3c. `scripts/watcher.sh` (runtime watchdog, verify-only monitoring)

```
bash .zscripts/watcher.sh --ensure        # start if not running (idempotent; dev.sh at boot + bootstrap --ensure at every run — the daemon dies silently at container lifecycle events, so both paths matter)
bash .zscripts/watcher.sh --status        # daemon status via PIDFILE (never trust pgrep — see §6)
bash .zscripts/watcher.sh --stop          # stop + set the stop-flag
bash .zscripts/watcher.sh --force-start   # start even with a stop-flag present
```

The 30-second loop runs eight checks: (1) download/ change trigger → dev.sh (the ALERT surface is excluded from this hash — an alarm never kicks the boot hook); (2) explorer health → auto-restart via explorer.sh --ensure (skipped when a Next.js project owns the preview port); (3) release-file guard — `skill-card.md` + `assets/integrity.sha256` in the canonical copy must exist and stay version-fresh, restored ONLY from a healthy local same-version install (no vault, no network); (4) installation integrity ~every 10 minutes — **verify-only**: on manifest failure it logs `INTEGRITY ALARM` with the remediation message (`npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw -y`); no silent repair by design; (5) archive refresh ~every 15 minutes via repo-snapshot.sh --apply-auto; (6) compliance sentinel ~every 2 minutes — alarms when the worklog grows without an M1 checkpoint; (6b) silent-work sentinel + ALERT surface ~every 2 minutes (v5.4.0, incident 2026-10-21) — WORK-SILENCE (artifacts outrunning the last checkpoint by >30 min) and EVIDENCE-PENDING (upload/ evidence unprocessed >2 h); alarms append to the worklog AND refresh `download/ALERT-ACTIVE.md` (the user-visible surface, removed on all-clear — the worklog paradox: alarms written only where a compliant session read let the incident run unseen); (7) origin release probe ~every 24 h (epoch-gated, alarm-only); (8) periodic compliance audit ~every 6 h — the external verdict lands in watcher.log as greppable history, a FAIL also alarms the worklog. The daemon survives per-tool-call process cleanup as a double-fork orphan (PPID=1, setsid) but can still die at container lifecycle events; revival paths: dev.sh at boot, `bootstrap --ensure` (step 11b), manual `--ensure`. A deliberate `--stop` (stop-flag) is respected by every path.

### 3d. `scripts/audit-compliance.sh` (compliance audit from OUTSIDE the model)

Marker-less responses raise no errors at all — silent non-compliance is invisible to the model itself. This script does NOT trust model discipline: it reads artifacts on disk and issues a PASS/WARN/FAIL verdict + exit code (0 = no FAIL).

```
bash scripts/audit-compliance.sh [--root <project-root>] [--quiet]
```

Checks: **C1** memory/SESSION-STATE.md exists · **C2** Active-table hygiene (H2 — terminal rows in the active table = FAIL) · **C3** worklog-vs-SESSION-STATE staleness (an active worklog with no M1 checkpoint >30 min = WARN — the incident signature) · **C4** installed-vs-canonical version sanity (4c) · **C5** R1 hook present at the worklog tail. Its companion pattern (**R2**, per-project infra — not bundled): the **watcher sentinel** — the same signature detected every ~2 minutes, appended as a COMPLIANCE-ALARM to the worklog tail, an anchor the next session is guaranteed to read. Together they close the "invisible non-compliance" gap from outside the model.

## 4. Post-Reset Procedure (Decision Tree at a Fresh Boot)

1. **Detect whether a rollback/degrade happened**: newest files missing, or the M0 version sanity alarm fired (installed banner older than the release recorded in memory), or `INTEGRITY ALARM` lines in `.zscripts/watcher.log`.
2. **Drift detected** ⇒ re-run THE install command — `npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw -y` (or `bash skills/stellar-trail/scripts/update-skill.sh --force`): the single flow re-installs verified bytes; then run L1 `--apply` so the source archive is fresh too; `git status` for leftover files.
3. **The canonical copy is gone too** (total wipe of `download/`) ⇒ the install command rebuilds it — run `bash skills/stellar-trail/scripts/bootstrap-sandbox.sh --ensure` after installing to re-seed the canonical + arm the boot hook (explorer/snapshot/hooks auto-enable; the hooks module seeds CLAUDE.md + AGENTS.md at the project root, create-if-absent + refresh-if-byte-identical); repo.tar's `skills/stellar-trail` append (L1) is a same-boot fallback while the archive survives. If the response banner still shows an old version after all this, see the skill-card Known Risks (the continuation-activation failure mode, rule 1).
4. **Nothing happened** ⇒ just ensure L1 is fresh if you are about to stop/rest.
5. **memory/ is gone too** (total reset) ⇒ recover from the latest handoff on the persistent mount; if none exists, run the cold-start protocol (memory-hygiene §2) — never claim "no history" before checking every channel.

## 5. Limits & Ethics

- Never run L1 on an environment you do not own — overwriting the restore archive is an infrastructure intervention; it is only legitimate when the environment's owner requests it.
- Recovery channels are layered: the L1 archive → the boot cache replay from canonical (L2a) → re-install via the single install command (final resort, fully verified).
- These scripts handle the RESTORE ARCHIVE and the SKILL INSTALLATION; they do not replace `git`: commits remain the source of truth for diff/status; snapshots are for disaster recovery.

## 6. Design Receipts (verified field findings)

Recorded as receipts so the design can be audited, not accepted on faith:

- **Boot = wipe + extract**: the boot hook removes the project tree (except mountpoints) and extracts the restore archive; the packer EXCLUDES `skills/` — a boot restore hook + a canonical copy on a preserved path is therefore mandatory (L2a).
- **The pre-stop packer overwrites the restore archive at every stop cycle** — the effective cross-boot chain is canonical `download/` + the boot restore (§2 architecture finding).
- **`pgrep -f watcher.sh` is a false negative** (the daemon runs as an orphan inline `bash -c`); watcher status MUST go through `watcher.sh --status` (PIDFILE), never pgrep.
- **Verification is mandatory after EVERY edit, including the last one** — an "everything aligned" checkpoint taken before a final edit is exactly how manifest-lag ships (a real post-reset audit caught a receipt edit that landed after the final manifest regen).
- **Boot traces in `.zscripts/boot.log` are reversible after the hook** (a root-level actor re-extracted the workspace archive after dev.sh finished — the morning's hook trace gone from the log); for M0 forensics use sources OUTSIDE the restore tree (`/tmp` boot timeline, snapshot state, live `ps`).
- **Ordinary processes die when a tool call finishes** (the platform kills the descendant tree); the only surviving daemon form is a double-fork orphan (PPID=1 + setsid).
- **A pinned skill blocks its own update and can make bulk updates skip it SILENTLY** (success-looking no-ops) — never pin this skill.
- **Object-storage mounts live outside the container** and are not rolled back — the rescue channel for state markers.
- **An alive-but-stale deployment is a real failure mode** (files updated, the running process still serving old code): freshness checks must compare CONTENT (code stamps / md5), not mtimes.

### 6b. Documented incidents (field evidence)

**Incident 2026-10-21 — cross-session protocol skip ("silent work"), deployment container (skill v5.3.1).** Between protocol sessions 94 and 95, at least two continuation sessions ran entirely without loading the protocol body: they analyzed diagnosis output, implemented a build, packaged a release zip, and guided an on-device deploy — zero banner, zero markers, zero M1s, zero worklog appends; SESSION-STATE froze while the disk advanced two stages and the user's 05:25 field-evidence upload sat unprocessed. Findings: every machine sentinel was silent — correctly so — because the compliance sentinel keyed on "worklog growing without a checkpoint" and these sessions wrote NOTHING (sentinel coverage keyed on the wrong signal); the incident was caught by the USER (the missing banner — the guard-that-cannot-wake-the-guard paradox); artifacts-on-disk saved the recovery (the compliant session re-verified everything from disk — md5, perms, diffs — debunking the wrong "zip packaging regression" framing; the on-device extractor was stripping exec bits). Rule 6 executed as designed: unverified-input posture, debt settled, no retro-edits; permanent damage zero. **Shipped in v5.4.0 as a direct consequence:** watcher duty 6b (silent-work sentinel keyed on ARTIFACT MTIMES vs the checkpoint — the exact forensic signal) + the `download/ALERT-ACTIVE.md` user-visible surface + the M0 artifact-freshness sweep + the audit `silent-work` check + duty 8's ~6 h audit. **Honest limits (unchanged):** the description stays wording-frozen (877/1024, measured local optimum); a pre-response blocking hook has no harness API (documented infeasible); the last defense layer remains the owner's eyes — audit for the banner on every response.

**Incident 2026-10-23 — platform-upgrade restart + dead-session delivery debt (skill v5.4.3 in flight).** The platform upgraded mid-morning; the container restarted 12:31:45 UTC and the FULL workspace survived (mtimes intact). Two findings: (1) the persistence design HELD — the boot chain self-healed by 12:31:56, zero data loss; but generations differ, the documented preserve-set (`download/` · `.zscripts/` · `memory/` · `worklog.md`) is the MINIMUM guarantee — do not tune defenses DOWN on one generous generation (the wipe-class reset, 7 occurrences in the Task-22 era, remains the design case); (2) the upgrade exposed a dead-session delivery debt — the prior session had committed + tagged v5.4.3 (06:48) but died before its M1/worklog writes, and its MANUAL three-tree promotion missed exactly one file (task-files-explorer.md stale in live+canonical, dev+git correct); the watcher duty-4 caught it at 12:41:49 (INTEGRITY ALARM) but only in watcher.log, and the audit PASSED 8/8 over the broken tree (version-equality blind); the continuation summary then narrated the missing steps as DONE — the files disproved every one. **Shipped in v5.4.4:** audit tree-integrity (per-tree checksum) + release-recording (newest tag hash vs the ledger) + watcher-liveness checks; the M0 release-consistency sweep; the INTEGRITY class on the ALERT surface; SCRIPTED (never manual) three-tree promotion. Durable rule: disk version-stamps (mtimes, tag hashes, manifests) are the arbiter — a summary is a claim, not a record.

## 7. Consumer Sandbox Deployment — `bootstrap-sandbox.sh`

The persistence layers above need to be installed in a consumer sandbox too — and a fresh install has none of them. `scripts/bootstrap-sandbox.sh` installs the same architecture in ONE command:

| Module | Installed | Single path (no redundant fallbacks) |
|---|---|---|
| core (always) | canonical `download/stellar-trail/` + `.zscripts/dev.sh` + `.zscripts/watcher.sh` + `worklog.md` seed (R1 hook) + tail guard + `memory/` scaffolding | seed = a copy of the live installation (self-locating, offline); dev.sh restores `skills/stellar-trail` from the canonical at every boot (SHA-256 manifest verification + the no-downgrade gate); the runtime watchdog started by dev.sh at boot and by bootstrap at every run; the tail guard keeps the activation directive as the worklog's last line |
| explorer (auto-enabled) | `.zscripts/{explorer.sh, explorer.py, explorer-ui/}` + an `--ensure` step in dev.sh | self-locating launcher + drift-sync from canonical; the Next.js guard still applies |
| snapshot (auto-enabled) | `.zscripts/repo-snapshot.sh` + an `--apply-auto` step in dev.sh | the `WMG_PROJECT` env is forwarded by dev.sh (for platforms with `/home/sync`) |

What survives resets (packer contract, verified from the original archive): `download/` + `.zscripts/` + `memory/` + `worklog.md`. What gets wiped: `skills/` — exactly what dev.sh restores from the canonical.

Commands: `bash scripts/bootstrap-sandbox.sh` (core + auto-enabled modules) · `--ensure` (idempotent, Activation rule 4 at M0) · `--with-explorer` / `--with-snapshot` (force-on) · `--without-explorer` / `--without-snapshot` (opt-out) · `--status` (read-only) · `--project-dir` · `--force-devsh` (overwrite a non-bootstrap dev.sh — the reference deployment is never overwritten without this flag).

Discipline held: idempotent (writes only when content differs); NEVER overwrites `memory/`, `worklog.md`, or a foreign dev.sh; the memory scaffold carries consent-pending status — the first session must ask the user for confirmation before writing substantive state. Hardening (lifecycle-validated 16/16): the generated hook's restore step carries the no-downgrade version gate, and the generated hook is syntax-checked (`bash -n`) at generation time — a heredoc typo dies at generation, never inside `/start.sh` at next boot.

## 8. Crash-Safe Version Migration + M0 Forensics

**Crash-safe migration order (R2/F5).** "Swap the working directory FIRST, refresh the resilience layers after" opens a mixed-version window (~4 minutes observed) with no runtime safety net: a crash inside it → the next boot restores an old archive → recovery converges to the OLD version. Safe order: (1) prepare the new-version source (verified clone), (2) swap the canonical `download/stellar-trail/` to the new version, (3) redeploy the watcher from the new canonical, (4) ONLY THEN swap the live install `skills/stellar-trail` LAST. A crash at any point then converges the next boot to the NEW version.

**Restore-immune forensic sources for M0 (R4/F3).** Boot traces in `.zscripts/boot.log` were PROVEN reversible after the hook (a root-level actor re-extracted the workspace archive AFTER dev.sh finished — the hook demonstrably ran, yet boot.log came back byte-identical to the archived copy). Use sources OUTSIDE the restore tree: `/tmp/boot-timeline.log` (written by /start.sh), `/home/sync/repo-state/*` (auto-apply snapshots), and `ps` — never boot.log alone.

**Audit rhythm (R6).** Run `scripts/audit-compliance.sh` at major M0/M1 checkpoints — the only tool that mechanically catches version-lock and hook drift (see also SKILL.md §3 M1).

## 9. Pre-Phase Auto-Update — `update-skill.sh`

Section 7 installs the defense layers; section 8 repairs migration damage; this section closes the remaining gap: **an installation that is healthy but OLD**. The protocol calls `scripts/update-skill.sh --ensure` at M0, after `bootstrap --ensure`, BEFORE the phases begin (Activation rule 5).

**Trigger — always check.** Invoked at every M0 and the network check ALWAYS runs (a 24h debounce gate was removed after it hid same-day releases behind a stale window). M0 stays cheap and offline-first: one anonymous `git ls-remote` (~2 s, 25 s timeout); an unreachable origin is a one-line report with exit 0. `.zscripts/.update-check.last` remains a record for `--status` (never a gate); `--force` is a compatibility alias, `--check` a dry-run. The watcher (duty 7) adds an independent background probe every ~24h — epoch-state-gated, offline-tolerant (~1h retry) — raising a one-line worklog alarm when the origin carries a NEWER release tag (once per unseen version; ALARM-ONLY, never installs). The watcher also raises a one-line NOTICE (once per gap episode) when the explorer payload is installed but `.zscripts/explorer.sh` is not deployed — suppressed when a `package.json` owns the preview URL; it never installs anything.

**Semantics: a VERIFIED override, not a blind pull.** Origin = GitHub hoshiyomiX/stellar-trail (the sole channel, public read, no PAT). The check: `git ls-remote` latest tag → staging clone `--depth 1 --branch` → full SHA-256 manifest verification → tag≡content assert (anti-poisoning: a tag containing another version's content = hard abort exit 1) → anti-downgrade assert (an origin older than local = refused). Copying corruption is not healing — and copying an unverified source is not an upgrade.

**The install IS the single flow.** When the origin is newer, the wrapper runs THE install command as step `[1/4]` of a verified override, verifies the landed bytes against the manifest, swaps targets with per-target rollback backups (`.update-bak`), and finishes canonical-first → live-last per section 8 (a crash anywhere converges the next boot to the NEW version). The script copies itself to a temp file and re-execs from there before swapping (overwriting the directory a running script lives in is undefined behavior); file modes normalize to 0644 (the package-wide exec-bit doctrine).

**Offline = a report, not a block.** Network/git failure → a one-line report, exit 0 — M0 never depends on the network. The whole installation prints step by step (`[1/4]`…`[4/4]`). After an update lands, response banners carry the new version; the skill body is reloaded immediately (Activation rule 5).

**Post-install module arming.** Empirical basis: a consumer install + bootstrap-ensure report — the install succeeded and the canonical was fresh, BUT the post-update bootstrap ran core-only: the persistence layer came up half-armed (explorer dead, snapshot not installed) until the user remembered to run `--with-*` manually. The final step therefore runs `--ensure --with-explorer --with-snapshot --with-harness-hooks`: after an update, the layer comes up FULLY armed. Override: env `STELLAR_UPDATE_BOOTSTRAP_ARGS` (e.g. `"--ensure"` for the old core-only behavior). The fresh-install path auto-enables the modules too — a plain `--ensure` arms explorer + snapshot + hooks whenever their payload ships in the install tree (`--without-*` opts out, including disarming a module armed by a previous run).

## Appendix: Standalone-Helper Doctrine — Small Cross-Script Duplication = By-Design

> Recorded explicitly so future audits do not re-flag it as a redundancy finding.

Every script in this package (`update-skill.sh`, `snapshot-repo.sh`, `bootstrap-sandbox.sh`, `watcher.sh`, `enforce-gates.sh`, `audit-compliance.sh`, plus the explorer assets) carries its own small helpers — `log`/`say`/`ts`/`die` variants. A classic DRY refactor would unify them into one shared library; this package's resilience doctrine FORBIDS it: **every script must keep standing alone when its siblings break or are deleted** — a repair script must be able to fix its sibling exactly when that sibling, and any shared library, is itself broken (an entire fallback chain once died together from sharing one failure point). Duplicating 3–8 lines per helper is a consciously paid price for **failure-domain isolation**; cross-file consolidation is NOT recommended. The one exact duplicate is `version_lt()` (8 lines; exactly TWO locations — a controlled pair: `update-skill.sh` + the `bootstrap-sandbox.sh` generated-hook version gate) — kept with controlled-copy comments at both locations: change them together, never merge them.
