# Environment Resilience — Anti-Rollback Playbook (Container Platforms)

> **When to read this file:** your working environment runs in a resettable container/sandbox
> (e.g. a platform preview container, an ephemeral CI runner) AND you see the symptoms: work
> files "disappearing" after a restart, file versions degraded to an older state, or custom
> skills/scripts vanishing. If you work on a local/static machine that is never reset, this
> section does not apply — ignore it.

## Table of Contents

(Since v3.6.1 as a one-line list; since v3.6.4 heading + list format per skill-creator
standards for references >300 lines — refreshing stale entries. Restructured in v3.6.7 for
the single-install-flow architecture: the retired repair scripts live in Appendix A.)

1. Threat Model: How a Container Rolls Back Your State
2. Defense Layers (v3.6.7 — cache-replay restore + verify-only monitoring; shadow backup removed v3.3.0; multi-source repair retired v3.6.7)
3. Using the Scripts — 3a snapshot · 3b retired repair chain · 3c watcher · 3d audit
4. Post-Reset Procedure (Decision Tree at a Fresh Boot)
5. Limits & Ethics
6. Field Evidence / Receipts (Task 36–38 forensics, 2026-09-19/20)
7. Consumer Sandbox Deployment — bootstrap-sandbox.sh (v3.6.1 Task 56; core+watcher v3.6.3 Task 62; release guard v3.6.4 Task 64; version+syntax gates v3.6.7)
8. Crash-Safe Version Migration + M0 Forensics (v3.6.3, Task 62)
9. Pre-Phase Auto-Update — update-skill.sh (v3.6.6 Task 67; module arming v3.6.7 Task 68)
Appendix A: Evolution of the heal-skill.sh Repair Chain — RETIRED v3.6.7 (moved from the SKILL.md body in v3.6.0)
Appendix B: Standalone-Helper Doctrine — small cross-script duplication = by-design (R6 audit T63)

## 1. Threat Model: How a Container Rolls Back Your State

Many container platforms restore the project directory from a **restore archive** (real example:
`/home/sync/repo.tar`, extracted by the `/start.sh` hook at boot — `rm -rf <project>` except
mountpoints, then `tar xf repo.tar`). This archive is ideally rewritten by a **pre-stop packer**
when the container stops. The problem: **pre-stop does not always run** — the container can be
crashed, force-killed, or the pack can fail (a failure branch the platform hook itself
acknowledges). The next boot then restores an **old state**: a silent rollback that erases hours
of work.

Four structural facts that can be exploited (verified empirically on one container platform, 2026):

1. **The restore source is readable**: the boot hook and the restore archive can usually be read
   from inside the container (`cat` the hook, `tar -tf` the archive) — you can dissect the format
   instead of guessing.
2. **Object-storage mounts survive**: directories mounted from object storage (e.g. ossfs) live
   OUTSIDE the container and are not rolled back — the rescue channel for backups and state markers.
3. **Boot tolerates a corrupt archive** (warning + continue) — a failed refresh does not kill the
   container.
4. **The packer can exclude important directories** (real forensics: `skills/` never made it into
   the platform packer's archive) — a skill installation is the most frequent rollback victim.

## 2. Defense Layers (v3.6.7 — cache-replay restore + verify-only monitoring)

| Layer | Role | When it works |
|---|---|---|
| **L1 — Source refresh** (`scripts/snapshot-repo.sh`) | Overwrites the platform restore archive with a snapshot of the CURRENT state — now including `skills/stellar-trail` (surgical append) — so the native boot restore = fresh state *for as long as that archive survives* | `--apply` after significant milestones; `--apply-auto` periodically (debounce + 15-min cooldown) |
| **L2a — Cache-replay boot restore** (`scripts/bootstrap-sandbox.sh` → generated `.zscripts/dev.sh`) | At every boot, verifies `skills/stellar-trail` against the canonical copy's SHA-256 manifest (`download/stellar-trail/`) and restores it byte-identically when broken or missing — with a **no-downgrade version gate** (a healthy NEWER live install is never overwritten; a corrupt-but-newer install raises a watcher alarm instead of a silent repair) | Automatic at every boot; the canonical copy persists via the platform archive (which does include `download/`) |
| **L2b — Verify-only monitoring** (`scripts/watcher.sh` v2.0) | Periodic integrity verification of the installed copies against the checksum manifest; on failure: **alarm + the remediation message** (the single install command). NO automatic multi-source repair — by design | Watchdog loop, ~every 10 minutes |
| **L3 — Original backup** | Undo: the platform's original restore archive is copied before being overwritten — restorable at any time | Always, before every L1 swap |

L1 prevents rollback **at its source**; L2a **restores the installation** from the canonical
bytes when a rollback or clobber still happens; L2b **detects and reports** drift that the boot
restore could not cover; L3 guarantees every infrastructure intervention **can be undone**. The
layers are mutually independent — one layer's failure does not disable the others. Real repair —
when even the canonical copy is bad — is NOT a layer: it is the single install command
(`npx skills add hoshiyomiX/stellar-trail`), the one and only installation flow, executed
deliberately with full verification (see section 9).

**Architecture finding 2026-09-19 (boot forensics):** the platform pre-stop packer actually
OVERWRITES the restore archive with its own at every stop cycle — our L1 build (including the
`skills/stellar-trail` surgical append) **never survives across boots**. Evidence: the 05:34 boot
found a "foreign" repo.tar (0 `skills/` entries) and the `skills/stellar-trail` directory gone
entirely, even though the previous night's L1 build carried 32 skill entries. Consequence, layer
roles shifted: **the truly effective cross-boot chain = the canonical `download/stellar-trail/`
(persistent via the platform archive, which does include `download/`) + the L2a boot restore**.
L1 remains valuable for intra-boot freshness (repo.tar never >15 min stale) and the L3 undo
channel.

**Two clawhub install-location conventions (finding 2026-09-19):** clawhub CLI ≥ 0.23.3 installs
fresh as **owner-scoped**: `skills/@owner/stellar-trail`; installations from older-CLI eras may
be flat: `skills/stellar-trail`. Since v3.5.2 the entire chain and the boot hook are
**location-aware**: they find and handle BOTH layouts.

**Why there is no shadow-backup layer anymore (empirical lesson, removed in v3.3.0):** an
earlier architecture generation shipped a rolling shadow backup (periodic project snapshots to a
persistent mount, auto-restored on stale detection). Four forensic findings condemned it:
(1) its stale detection was **false-positive-prone** — its own backup activity raised the
heartbeat and triggered failing restore attempts (the 07:38 UTC incident: two consecutive failed
extract restores); (2) **the same blind spot** as its source — `skills/` remained unprotected by
the very layer claiming to protect it; (3) **the same failure domain** — it lived on the exact
object-storage mount as the archive it secured; (4) a 62 MB write cost per 30 minutes for
illusory protection. The general lesson: **a backup whose restore path was never tested is more
dangerous than no backup** — it provides a feeling of safety while adding new failure modes.

**Why the multi-source self-repair chain was retired (v3.6.7):** the heal-skill.sh chain
(v3.3.0 → v3.5.8, Appendix A) was a second, parallel installer — six candidate sources ranked by
version, silent repairs by default. It violated the single-install-flow requirement, and its
silent self-repair once let a poisoned canonical copy win a version selection (the 2026-09-22
post-reset incident's root cause). v3.6.7 replaces it with the division of labor above: restore
= boot cache replay (L2a, from the ONE canonical copy), detect = verify-only monitoring (L2b),
repair = THE install command. One installer, one source of truth, zero silent repairs.

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

### 3b. RETIRED in v3.6.7: `scripts/heal-skill.sh` + `scripts/vault-sync.sh`

Both scripts were **deleted** in the v3.6.7 architecture redo. The full evolution history and
the incidents that shaped them remain documented in **Appendix A** (historical record — the
lessons are still true; the mechanism is gone). The succession map, verified line-by-line from
the retired sources:

| Retired responsibility | Successor in v3.6.7 |
|---|---|
| Periodic integrity verification (`--check`) | `watcher.sh` v2.0 check 4 — verify-only, ~every 10 min, alarm + install hint (3c) |
| Multi-source repair (6 sources, version-ranked) | **The single install command** `npx skills add hoshiyomiX/stellar-trail` — no alternate sources exist anymore |
| Install execution (rsync + verify) | `update-skill.sh` — thin wrapper that runs THE command with a verified override (section 9) |
| Downgrade detection (version-assert) | Triple: `update-skill.sh` refuses older origins · the boot restore's version gate skips older canonicals · the M0 sanity alarm |
| Release-file restore (skill-card.md etc.) | `watcher.sh` v2.0 check 3 — local-only restore from a healthy same-version install |
| Canonical refresh | `bootstrap-sandbox.sh --ensure` |
| Vault refresh (`vault-sync.sh --apply`) | **Retired with zero successors — the vault had zero readers once heal-skill was gone** (a writer with no readers is dead code manufacturing stale-copy downgrade risk) |
| Manifest regeneration (`--manifest`) | Release-time maintainer action (the release checklist), not a runtime script |
| `version_lt()` trio doctrine | Now exactly TWO controlled copies: `update-skill.sh` + the `bootstrap-sandbox.sh` generated-hook gate (Appendix B) |

Why deletion was correct (from the recovered sources): heal-skill.sh was a **parallel installer**
(6 sources, 7 paths) that directly violated the locked single-install-flow requirement, and its
seven evolution stages were incident patches piled on patches; vault-sync.sh was a **writer with
no readers** (its header named heal-skill.sh as its sole consumer) — keeping it would only
manufacture a third stale copy with downgrade risk.

### 3c. `scripts/watcher.sh` (v2.0 — runtime watchdog, verify-only monitoring)

```
bash .zscripts/watcher.sh --ensure        # start if not running (idempotent; dev.sh + M0 call this)
bash .zscripts/watcher.sh --status        # daemon status via PIDFILE (never trust pgrep — see §6 drill finding)
bash .zscripts/watcher.sh --stop          # stop + set the stop-flag
bash .zscripts/watcher.sh --force-start   # start even with a stop-flag present
```

The 30-second loop runs six checks: (1) download/ change trigger → dev.sh; (2) explorer health →
auto-restart via explorer.sh --ensure (skipped when a Next.js project owns the preview port);
(3) release-file guard — `skill-card.md` + `assets/integrity.sha256` in the canonical copy must
exist and stay version-fresh, restored ONLY from a healthy local same-version install (no vault,
no network); (4) installation integrity ~every 10 minutes — **verify-only**: on manifest
failure it logs `INTEGRITY ALARM` with the remediation message (`npx skills add
hoshiyomiX/stellar-trail`); there is no silent repair by design; (5) archive refresh ~every 15
minutes via repo-snapshot.sh --apply-auto; (6) compliance sentinel ~every 2 minutes — alarms in
the worklog when it grows without an M1 checkpoint. The daemon survives per-tool-call process
cleanup as a double-fork orphan (PPID=1, setsid).

### 3d. `scripts/audit-compliance.sh` (v3.5.5 — compliance audit from OUTSIDE the model, R3)

Born from the 2026-09-21 incident report: three sessions of another project ran ZERO-compliance
(no banner/checkpoint/handoff) and were only caught by a manual user audit — silent violations
because marker-less responses raise no errors at all. This script does NOT trust model
discipline: it reads artifacts on disk and issues a PASS/WARN/FAIL verdict + exit code
(0 = no FAIL).

```
bash scripts/audit-compliance.sh [--root <project-root>] [--quiet]
```

Checks: **C1** memory/SESSION-STATE.md exists · **C2** Active-table hygiene (H2 — terminal rows
in the active table = FAIL) · **C3** worklog-vs-SESSION-STATE staleness (an active worklog with
no M1 checkpoint >30 min = WARN — exactly the incident signature) · **C4** installed-vs-canonical
version sanity (4c) · **C5** R1 hook present at the worklog tail. Its companion pattern (**R2**,
per-project infra — not bundled): the **watcher sentinel** — the watchdog's compliance check
detects the same signature every ~2 minutes and appends a COMPLIANCE-ALARM to the worklog tail,
an anchor the next session is guaranteed to read. Together they close the "invisible
non-compliance" gap from outside the model.

## 4. Post-Reset Procedure (Decision Tree at a Fresh Boot)

1. **Detect whether a rollback/degrade happened**: quick symptoms — newest files missing, or
   the M0 version sanity alarm fired (installed banner version older than the release recorded
   in memory), or `INTEGRITY ALARM` lines from the watcher in `.zscripts/watcher.log`.
2. **Drift detected** ⇒ re-run THE install command — `npx skills add hoshiyomiX/stellar-trail`
   (or `bash skills/stellar-trail/scripts/update-skill.sh --force`): the single flow re-installs
   verified bytes; then run L1 `--apply` so the source archive is fresh too; `git status` for
   extra leftover files from the restore.
3. **The canonical copy is gone too** (total wipe of `download/`) ⇒ the install command rebuilds
   it — run `bash skills/stellar-trail/scripts/bootstrap-sandbox.sh --ensure` after installing
   to re-seed the canonical + arm the boot hook (explorer/snapshot auto-enable); repo.tar's
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
- `skills/` used to be a platform-packer exclusion; since v3.3.0 the L1 archive includes
  `skills/stellar-trail` via surgical append, and its recovery channels are layered: that
  archive (L1) → the boot cache replay from canonical (L2a) → re-install via the single install
  command (the final resort, fully verified).
- These scripts handle the RESTORE ARCHIVE and the SKILL INSTALLATION; they do not replace
  `git`: commits remain the source of truth for diff/status; snapshots are for disaster recovery.

## 6. Field Evidence / Receipts (Task 36–38 forensics, 2026-09-19/20)

Verified findings underpinning this section's architecture — recorded as receipts so the design
can be audited, not accepted on faith. Rows describing the retired heal chain describe the
mechanism AS IT WAS; see Appendix A.

| Receipt | Verified evidence | Design implication |
|---|---|---|
| **Task 36 — boot mechanism** | The "zip overwrites the install" hypothesis FELL (no `stellar-trail.zip` ever existed on disk/in archives); `skills/` non-persistence was REAL (boot = wipe + packer excludes `skills/`); heal worked 2/2 on real boots + sandbox A/B PASSED (the no-heal control stayed broken, the healed one recovered) | A boot restore hook is mandatory; the canonical `download/` = the cross-boot anchor |
| **Task 37 — pin = version lock** | `clawhub pin` blocked `update --force --version` exactly when a restore/upgrade needed it; `upload/` turned out to be class-A ossfs (not class-C as briefly believed) | Pin is not used for persistence; `upload/` is legitimate vault territory (era note: the vault itself was retired in v3.6.7) |
| **Task 38 — pin = anti-restore (0/6)** | A pinned skill + missing directory: `update`/`install` = error exit 1; `update --all` = "Skipped … pinned" SILENTLY exit 0 (the most dangerous — looks like success); `list` showed zombie "pinned" entries for skills absent from disk; pin state was sticky across heals. WITHOUT a pin: `update`/`install` = a healthy registry re-download (the registry restore path PROVEN to exist). A local canonical heal took 0.112 s offline | `clawhub pin stellar-trail` is forbidden; pin reporting for all skills shipped (v3.5.3); the registry was the last-resort net (until its retirement-era suspension) |
| **Task 39 → product** | Findings 37–38 carried into the product: `pin_report()` for all skills + `age_info()` healthy-but-old + labeled sources — suite 32/32, five layers aligned | Receipts became features, not just notes |
| **Task 40 → v3.5.4** | Boot-heal downgraded 3.5.4 on the live install at session restart WITHOUT a lock sync (the walk-up canonical source worked in the field); the registry's "suspicious" verdict (class 3.0.0 — disclosed-but-overbroad) did NOT block latest promotion nor `update --force` | The multi-source chain was production-validated (era); a Review-level verdict = honestly disclosed protocol character, not a defect |
| **Incident 2026-09-21 → v3.5.5** | 3 sessions of another project ZERO-compliance — caught only by a manual user audit; roots: description in the system prompt ≠ body loaded (the 2nd production confirmation of Activation rule 11's failure mode) + the continuation summary carried no activation trigger (RC2) + violations were invisible (RC3) | R1 worklog hook + R2 sentinel + R3 audit script + R4 imperative description (v3.5.5) — layered defenses OUTSIDE model discipline |
| **Consumer incident 2026-09-22 → v3.5.7** | A container recycle restored `skills/` from a stale archive: flat 3.5.5→3.5.4 SILENTLY, the `@owner` directory gone, both vaults empty (the consumer never filled them), `heal --check` reported CLEAN (manifest-vs-itself); `clawhub update --force` succeeded but ONLY refreshed the owner-scoped copy; continuation activation failed (3rd production confirmation of rule 11) — report: upload/stellar-trail-feedback-issue.md §6.1–6.8 | Verdict DOWNGRADED + exit ≠ 0 on version drift (out-of-band cross-check); sibling-convention as a heal source; vault self-arm hint + version stamp; one-line re-arm; packaging version-consistency gate — all era mechanisms, superseded in v3.6.7 by the single-flow doctrine |
| **Controlled drill 2026-09-22 → v3.5.7 (Task 43)** | The incident replicated end-to-end via a drill script (project-scope, not shipped; isolated sandbox, hermetic env): **Drill A** killing `explorer.py` → watcher auto-heal recovered it in **20 seconds** (target <60 s); **Drill B** stale-archive restore + fresh lock + ALL sources dead → verdict `DOWNGRADED` + **hard FAIL exit 1** + zero false-CLEAN claims (the incident's false-CLEAN closed), then a fresh owner-scoped sibling → labeled sibling heal → CLEAN zero drift — **14/14 assertions PASS**; **Drill C** injected drift into the deployed `explorer.py` → `--ensure` restored md5 from canonical + restarted the server + healthz ok. Side finding: `pgrep -f watcher.sh` = **false negative** (the watcher runs as an orphan inline `bash -c`, not matched by the pattern) — watcher status MUST be checked via `watcher.sh --status` (PIDFILE), never pgrep | The v3.5.7 mechanisms were field-proven-under-control (not just suite-tested): lock tripwire + sibling source + process auto-heal + deployment freshness sync — each with a reproducible receipt |
| **3.5.7 release-flow defects (found post-submit, fixed in canonical)** | 1) `vault-sync.sh`: markdown backticks inside a double-quoted `README_BODY` string were executed by bash (stderr noise + the `<install-dir>` placeholder eaten) — fixed by escaping; 2) order discipline: canonical edits MUST be followed by `--manifest` before `--apply`/packaging; 3) a sed version-bump did not touch escaped regex patterns in the suite — 18 FAILs were all fixture bugs; 4) suite assertions depending on real environment state must be hermetic from the start | Suite +2 regression assertions (109/109); verify after EVERY edit, not only after batches |
| **Platform post-reset audit 2026-09-22 22:28 UTC (Task 43, session 26)** | Container dead ~16 hours (since ~06:29 UTC) → boot 22:27:57; the platform archive restore brought yesterday's final state INTACT (tar preserves mtimes). A 6-hour audit window: **ZERO version rollback** — 3.5.7 survived on live flat + canonical + both vaults; lock 3.5.5 (out-of-band; disk ≥ lock = healthy, not DOWNGRADED); watcher + explorer rose automatically (new pids, healthz ok, `fresh` vs canonical ok); repo.tar refreshed at boot (2773 entries). The single finding: force boot-heal reported **FAIL — 1 corrupt** (`environment-resilience.md` vs manifest) — **not reset damage**: yesterday's final receipt edit (05:50:06) landed AFTER the final manifest (05:47:12) + package (05:47:35) + vault-sync, leaving the canonical manifest-inconsistent; the reset merely exposed it | Two lessons: (1) verification is mandatory AFTER every edit **including the last one** — yesterday's "everything aligned" checkpoint came from a pre-final-edit verification; (2) force-mode verification proved itself in the field (unplanned) as a manifest-lag catcher — its hard FAIL was CORRECT detection, not a false alarm |
| **Hardening v3.5.8 from the post-reset audit findings (Task 44, 2026-09-23)** | Two layers born from the 2026-09-22 manifest-lag incident: (1) **source self-verify** in `heal-skill.sh` — a source candidate carrying a manifest must pass tree ≡ its own manifest before selection; (2) a **tree ≡ manifest gate** in packaging — the build FAILS exit 1 before the zip is written when canonical ≠ manifest in either direction | Failover over failure: the last line of defense must be immune to poisoning of ITS OWN source; the build gate = the last automatic checkpoint before damage spreads to consumers. (Era note: both mechanisms were retired with the heal chain in v3.6.7 — the verified-override install in section 9 carries the same spirit: staging + full manifest verification BEFORE anything is swapped) |

## 7. Consumer Sandbox Deployment — `bootstrap-sandbox.sh` (v3.6.1 Task 56; core+watcher v3.6.3 Task 62; release guard v3.6.4 Task 64; gates v3.6.7)

The reference sandbox built the section 2–4 defense layers manually across Tasks 26–47; the
public package ships only the protocol + scripts + assets. Task 55 forensics (3/3 field claims
confirmed) proved the consequences in a consumer sandbox: (1) skill files gone after a reset —
the packer excludes `skills/` from the restore archive (evidence: the original packer archive
had 3807 entries, 0 under `skills/`); (2) services (explorer) dead permanently — no boot hook
revived them; (3) the activation chain broken — `worklog.md` was never created, the R1 hook was
absent, and after a total wipe the skill vanished from the system prompt while `memory/`
survived on disk with no reader.

`scripts/bootstrap-sandbox.sh` installs the same architecture in ONE command:

| Module | Installed | Single path (no redundant fallbacks) | Bugs closed |
|---|---|---|---|
| core (always) | canonical `download/stellar-trail/` + `.zscripts/dev.sh` + `.zscripts/watcher.sh` (v3.6.3) + `worklog.md` seed (R1 hook) + `memory/` scaffolding | seed = a copy of the live installation (self-locating, offline); dev.sh restores `skills/stellar-trail` from the canonical at every boot (SHA-256 manifest verification + the v3.6.7 no-downgrade version gate); watcher v2.0 = the runtime watchdog (explorer health + verify-only integrity checks + release-file guard with local-only restore + archive refresh + compliance alarm), started by dev.sh — closing the T46 F2 consumer gap: its contract was long referenced by 4 components whose file was never shipped | #1 #2 #3 |
| explorer (auto-enabled since Task 19) | `.zscripts/{explorer.sh, explorer.py, explorer-ui/}` + an `--ensure` step in dev.sh | self-locating launcher + drift-sync from canonical; the Next.js guard still applies | #2 |
| snapshot (auto-enabled since Task 19) | `.zscripts/repo-snapshot.sh` + an `--apply-auto` step in dev.sh | the `WMG_PROJECT` env is forwarded by dev.sh (for platforms with `/home/sync`) | #1 (an extra layer) |

What survives resets (packer contract, verified from the original archive): `download/` +
`.zscripts/` + `memory/` + `worklog.md`. What gets wiped: `skills/` — exactly what dev.sh
restores from the canonical.

Commands: `bash scripts/bootstrap-sandbox.sh` (core + auto-enabled modules) · `--ensure`
(idempotent, invoked by Activation rule 14 at M0) · `--with-explorer` / `--with-snapshot`
(force-on) · `--without-explorer` / `--without-snapshot` (opt-out) · `--status` (read-only) ·
`--project-dir` · `--force-devsh` (overwrite a non-bootstrap dev.sh — the reference deployment
is never overwritten without this flag).

Discipline held: idempotent (writes only when content differs); NEVER overwrites `memory/`,
`worklog.md`, or a foreign dev.sh; the memory scaffold carries
consent-pending status (SKILL.md 4b) — the first session must ask the user for confirmation
before writing substantive state. v3.6.7 hardening (lifecycle-validated 16/16): the generated
hook's restore step carries the no-downgrade version gate, and the generated hook itself is
syntax-checked (`bash -n`) at generation time — a heredoc typo dies at generation, never inside
`/start.sh` at next boot.

## 8. Crash-Safe Version Migration + M0 Forensics (v3.6.3, Task 62)

Two lessons from a consumer forensic report (2026-09-25, an npx 3.5.4 → 3.6.2 migration):

**Crash-safe migration order (R2/F5).** The order "swap the working directory FIRST, refresh
the resilience layers after" opens a mixed-version window (~4 minutes in the report) with no
runtime safety net: a crash inside that window → the next boot restores an old archive →
recovery converges to the OLD version and the migration must be repeated manually. The safe
order: (1) prepare the new-version source (verified clone), (2) swap the canonical
`download/stellar-trail/` to the new version, (3) redeploy the watcher from the new canonical,
(4) ONLY THEN swap the live working install `skills/stellar-trail` LAST. With this order a
crash at any point converges the next boot to the NEW version (every restore source is already
new; the live swap is the cheapest step to repeat).

**Restore-immune forensic sources for M0 (R4/F3).** Boot traces in `.zscripts/boot.log` were
PROVEN reversible after the hook: a root-level actor re-extracted the workspace archive AFTER
dev.sh finished (2026-09-25 incident: the hook ran 03:25:54–03:26:11, but boot.log came back
byte-identical to the archived copy + 6 lines — the entire morning's hook trace gone; pids/logs
back to old mtimes; the hook "never ran" as far as the log showed). For M0 forensics, use
sources OUTSIDE the restore tree: `/tmp/boot-timeline.log` (written by /start.sh),
`/home/sync/repo-state/*` (auto-apply snapshots), and `ps` (live processes) — never boot.log
alone.

**Audit rhythm (R6).** Run `scripts/audit-compliance.sh` at major M0/M1 checkpoints — this
external audit is the only tool that mechanically catches version-lock and hook drift (the
3-session 2026-09-21 incident was only caught by a manual audit; see also SKILL.md section 3 M1).

## 9. Pre-Phase Auto-Update — `update-skill.sh` (v3.6.6 Task 67 · module arming + single-flow wrapper v3.6.7 Task 68)

Section 7 installs the defense layers; section 8 repairs migration damage; this section closes
the remaining gap: **an installation that is healthy but OLD** — not broken, not a manual
migration, just behind a release. Before v3.6.6, catching up waited for manual initiative;
since Task 67 (Activation rule 15), the protocol calls `scripts/update-skill.sh --ensure` at
M0, after `bootstrap --ensure`, BEFORE the phases begin.

**Trigger — always check.** Invoked at every M0 and the network check ALWAYS runs (the 24h
debounce gate was removed in the 2026-09-28 always-check fix after it hid same-day releases
behind a stale window — every M0 inside the window skipped the probe entirely, and the skip
line read as the feature being broken). M0 stays cheap and offline-first: one anonymous
`git ls-remote` (~2 s, 25 s timeout), and an unreachable origin is a one-line report with
exit 0. `.zscripts/.update-check.last` remains as a record for `--status` (never a gate);
`--force` is a compatibility alias, `--check` a dry-run. The runtime watcher (v2.1, duty 7)
adds an independent background probe every ~24h — epoch-state-gated so container reboots do
not reset the clock, offline-tolerant with a ~1h retry — that raises a one-line worklog alarm
when the origin carries a NEWER release tag (once per unseen version, remediation = the
install command). ALARM-ONLY: the watcher never installs.

**Semantics: a VERIFIED override, not a blind pull.** Origin = GitHub hoshiyomiX/stellar-trail
(D24 — the sole channel, public read, no PAT). The check: `git ls-remote` latest tag → staging
clone `--depth 1 --branch` → full SHA-256 manifest verification → tag≡content assert
(anti-poisoning: a tag containing another version's content = hard abort exit 1) →
anti-downgrade assert (an origin older than local = refused). Copying corruption is not
healing — and copying an unverified source is not an upgrade.

**The install IS the single flow (v3.6.7).** When the origin is newer, the wrapper runs THE
install command — `npx skills add hoshiyomiX/stellar-trail` — as step `[1/4]` of a verified
override, then verifies the landed bytes against the manifest, swaps targets with per-target
rollback backups (`.update-bak`), and finishes with canonical-first → live-last ordering per
the section 8 doctrine (a crash anywhere converges the next boot to the NEW version). The
script copies itself to a temp file and re-execs from there before swapping (overwriting the directory a running script lives
in is undefined behavior); file modes normalize to 0644 (the package-wide exec-bit doctrine).

**Offline = a report, not a block.** Network/git failure → a one-line report, exit 0 — M0 never
depends on the network (the boot chain stays offline-first; the boot cache replay and the
watcher remain the offline safety nets). The whole installation process prints to stdout
step by step (`[1/4]`…`[4/4]`) — the user stays informed and can follow up (the explicit Task 67
mandate). After an update lands, response banners carry the new version; the skill body is
reloaded next session (Activation rule 11).

**Post-install module arming (v3.6.7, Task 68).** Empirical basis: a consumer install +
bootstrap-ensure report (zai-web sandbox, 2026-09-27) — the install succeeded and the canonical
was fresh, BUT the post-update bootstrap ran core-only (`bootstrap.state m=-`, "explorer module:
NOT enabled") — the persistence layer came up half-armed: explorer dead, snapshot not
installed, until the user remembered to run `--with-*` manually. Since v3.6.7 the final step
runs `--ensure --with-explorer --with-snapshot`: after an update, the layer comes up FULLY
armed. Override: env `STELLAR_UPDATE_BOOTSTRAP_ARGS` (e.g. `"--ensure"` for the old core-only
behavior). Posture note (Task 19, 2026-10-04): the fresh-install path now auto-enables BOTH
modules too — a plain `--ensure` arms explorer + snapshot whenever their payload ships in the
install tree (`--without-explorer` / `--without-snapshot` opt out, including disarming a
module armed by a previous run) — closing the v4.1.0 consumer report's fresh-install trap.

## Appendix A: Evolution of the heal-skill.sh Repair Chain — RETIRED v3.6.7 (moved from the SKILL.md body in v3.6.0)

> The full history is preserved here so the body stays operational (the Task 56 audit lens:
> focused, directed, in control — long history lives in references, not in the protocol read
> every turn). The text below describes the mechanism AS IT WAS, verbatim in structure from
> SKILL.md v3.6.0 section 4c. **The script was deleted in v3.6.7** — see section 3b for the
> succession map; the lessons that produced each stage remain true and are why the current
> architecture verifies sources, refuses downgrades, and never repairs silently.

`scripts/heal-skill.sh` (since v3.3.0; location-aware since v3.5.2) — self-healed THIS skill's
installation at BOTH clawhub install-location conventions: flat `skills/stellar-trail` and
owner-scoped `skills/@owner/stellar-trail` (clawhub CLI ≥ 0.23.3 installs fresh installs
there). SHA-256 manifest
verification (`assets/integrity.sha256`) + release-version cross-check; multi-source repair
with a multi-level walk-up from the skill's location → class-A vault (v3.5.4) → the restore
archive matching the actual layout → a `clawhub update --force` reinstall hint. clawhub install
identity was never overwritten; `_meta.json`/`origin.json` were recreated when a boot wiped the
install entirely. No manifest AND no source = hard FAIL exit 1. Since v3.5.3: pin-state
reporting for ALL installed skills (pinned = WARN — it blocks that skill's update/install and
makes `update --all` skip it SILENTLY), a healthy-but-old info line, labeled heal sources
(env/walk-up-N/platform/archive). Since v3.5.4: the class-A vault (`/home/sync/skill-vault` +
`upload/skill-vault`, filled by `scripts/vault-sync.sh`) joined the chain — version-based
source selection + an anti-overwrite-newer version assert. Since v3.5.7: an out-of-band version
cross-check (recorded release newer than disk = verdict `DOWNGRADED` + update hint; still behind
after healing = FAIL exit 1 — the 2026-09-22 consumer incident), the sibling-convention source (`skills/stellar-trail` ↔ `skills/@owner/stellar-trail` as mutual
candidates), the vault self-arm hint. Since v3.5.8: source self-verify — a source candidate
carrying a manifest had to pass its own internal verification before selection; poisoned
sources (the 2026-09-22 post-reset boot-heal incident) were SKIPPED; all-eligible-candidates-
poisoned = hard FAIL; env overrides were honored with hard warnings.

`scripts/vault-sync.sh` (v3.5.4, adopted Tasks 35/41) — refreshed the class-A skill vault:
copied the canonical → `/home/sync/skill-vault` + `upload/skill-vault` with symmetric
anti-overwrite-newer asserts + manifest verification; `--apply` at release time (the same write
as the publish), `--check` for periodic drills, a version+date stamp in the vault's root
`README.md`, and consumer-side self-arm (`--apply` runnable directly from the install tree).
Its header named heal-skill.sh as its sole consumer — with heal gone, the vault had zero
readers, and the script was deleted with it.

**Rationale:** Why did this section exist in a memory skill? Because a memory protocol is only
as strong as its environment: SESSION-STATE and MEMORY mean nothing when their own directory is
rolled back to the past by the platform. Empirical experience showed silent rollback is a real
failure mode — and the solution did not need fancy tooling, just cheap, tested, layered
discipline: refresh the source, restore the install, keep the original for undo. The shadow
backup that once existed proved the principle from the opposite direction — a backup with a
never-tested restore path ADDS failure modes instead of removing them, and was deleted. The
repair chain that replaced it eventually proved the same principle again: a healer with six
sources and silent repairs became a second installer — a poisonable one — and was retired in
favor of one installer, one source of truth, and honest alarms. All infrastructure interventions
must be explicit and undoable; a guardian that silently rewrites the platform is a guardian
that has become a risk.

## Appendix B: Standalone-Helper Doctrine — Small Cross-Script Duplication = By-Design (R6 audit T63, since v3.6.5)

> Recorded explicitly so future audits do not re-flag it as a redundancy finding (audit T63 F5;
> the T46 consumer forensic report touched the same class).

Every script in this package (`update-skill.sh`, `snapshot-repo.sh`, `bootstrap-sandbox.sh`,
`watcher.sh`, `enforce-gates.sh`, `audit-compliance.sh`, plus the explorer assets
`explorer.sh`/`explorer.py`/`dev.sh.template`) carries its own small helpers — `log`/`say`/`ts`/
`die` variants. A classic DRY refactor would unify these into one shared library; this
package's resilience doctrine FORBIDS it: **every script must keep standing alone when its
siblings break or are deleted**. A repair script must be able to fix its sibling exactly when
that sibling — and any shared library — is itself broken; the empirical lesson of the
2026-09-22 incident, when an entire fallback chain died together from sharing one failure
point. Duplicating 3–8 lines per helper is a consciously paid price for **failure-domain
isolation**; cross-file consolidation is NOT recommended. The one exact duplicate in this
package is `version_lt()` (8 lines; since v3.6.7 exactly TWO locations — a controlled pair:
`update-skill.sh` + the `bootstrap-sandbox.sh` generated-hook version gate) — kept with
controlled-copy comments at both locations (R5): change them together, never merge them.
