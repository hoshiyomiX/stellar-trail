# stellar-trail

[![skills.sh](https://skills.sh/b/hoshiyomiX/stellar-trail)](https://skills.sh/hoshiyomiX/stellar-trail)

Unified execution discipline + persistent cross-session memory protocol for AI agents.

stellar-trail governs **how a task executes** inside a turn — a mandatory 6-phase workflow (classify → clarify → plan → implement → validate → report) — and **how its context survives** across sessions — a memory lifecycle (restore → checkpoint → compress → handoff) — so long-running agent work survives context resets, session restarts, and multi-session handoffs. Checkpoints follow a fixed write order — the snapshot is rewritten before the audit ledger is appended, and long stretches take one checkpoint per artifact — so a session dying mid-write never orphans its ledger (incident-hardened 2026-09-29). Since 4.1.0 the body is a slim read (~240 lines — the owner's field-proven diagnosis: big read paths → overthinking → compliance violations), deep procedures live in four on-demand references, every completed task deterministically refreshes the restore archive, and the M0 read path is hard-budgeted.

## Install

One command — the single install flow (verified end-to-end on a live consumer sandbox, v3.6.6, 2026-09-27: exit 0 in 3.93 s, the skill listed by `npx skills list`, `computedHash` in `skills-lock.json` matching the stdout hash):

```bash
# OpenClaw — the -y --json flags make it fully non-interactive (see Troubleshooting)
npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw -y --json

# Claude Code, Cursor, Codex, Copilot, Windsurf, Gemini CLI, Cline, AMP, Antigravity…
npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a claude -y --json
```

The installer is the open-source [vercel-labs/skills](https://github.com/vercel-labs/skills) CLI. Keep the `-y --json` flags: they skip the interactive confirmation prompts and are **required in any environment without a TTY** (agent sandboxes, CI) — without them the CLI can hang after the download (see [Troubleshooting](#troubleshooting)).

Since v3.6.7 this is deliberately the ONLY install flow — installing, re-installing, and repairing all run the same command; the package itself has no parallel installer and no fallback route, and every alarm it can raise prints this command as the remediation. After installing, verify the tree (the SHA-256 manifest turns "trust the publisher" into a deterministic check you can audit yourself):

```bash
cd <skills-dir>/stellar-trail && sha256sum -c assets/integrity.sha256   # expect: 16/16 OK
npx skills list   # expect stellar-trail, source hoshiyomiX/stellar-trail
```

To update later: `bash skills/stellar-trail/scripts/update-skill.sh --ensure` (the bundled single-flow updater — always-check origin probe, then a four-step verified override that runs the same install command and re-arms the persistence layer; the runtime watcher also probes the origin every ~24h and alarms the worklog when a newer release lands), or simply re-run the install command.

> **ClawHub registry — currently unavailable:** `clawhub install hoshiyomix/stellar-trail` stopped working when the registry suspended the publisher account via an automated malware-suspicion review (under appeal; the package passes the registry's own static analyzer, and every installed file is independently verifiable via the manifest). Until that resolves, this repository is the canonical channel — use Option 1 or 2.

> **Activation rule:** a skill description in a list is NOT activation — load the full body via `Skill('stellar-trail')` at the first turn of every session or continuation, before responding. If the body loads late (mid-session, after unmarked responses), Activation rule 16 makes it a recovery event: run M0 immediately, append a `LATE-ACTIVATION` note to the worklog, and resume markers from that turn — never continue unmarked. The SKILL.md enforces this itself.

## Troubleshooting

**`npx skills add` seems to hang, then times out (~5 minutes)** — confirmed on a real sandbox install (skills CLI v1.7.0): the command ends with an interactive `readline` prompt (agent/scope selection) that never resolves without a TTY, even though the skill files are already on disk and `skills-lock.json` is already written by the time it hangs. Re-run with the non-interactive flags:

```bash
npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw -y --json
```

`-y` skips the confirmations and `--json` forces structured non-interactive output (exit 0 on success); exporting `CI=true` works too. Re-running after a hang is safe — the installer overwrites cleanly and re-records the lock entry (observed live: `overwrites: OpenClaw` in the summary, stdout hash identical to the `skills-lock.json` `computedHash`).

## Reset-prone sandbox deployment

If your agent runs in a container/sandbox that the platform can reset (ephemeral CI runners, preview containers), a bare install is not enough: field forensics on consumer sandboxes (three confirmed failure modes) showed that a platform reset wipes `skills/` (the packer excludes it from the restore archive), kills long-running services with no hook to revive them, and leaves the activation chain broken because `worklog.md` was never created.

One command arms the whole persistence layer (idempotent, offline, self-locating):

```bash
bash skills/stellar-trail/scripts/bootstrap-sandbox.sh              # core
bash skills/stellar-trail/scripts/bootstrap-sandbox.sh --with-explorer --with-snapshot
```

What it installs — one proven path per module, no redundant fallbacks:

| Module | Installs | Closes |
|---|---|---|
| core (always) | canonical copy under `download/stellar-trail/` + `.zscripts/dev.sh` boot hook (skill restore with the no-downgrade version gate, v3.6.7) + `.zscripts/watcher.sh` runtime watchdog v2.0 (explorer health + auto-restart, verify-only integrity checks, release-file guard, archive refresh, compliance sentinel) + `worklog.md` (R1 activation hook) + `memory/` scaffold (R1-seeded headers) | skill files wiped on reset · activation chain broken · services dead between boots |
| `--with-explorer` | `.zscripts/` explorer (launcher + server + UI) revived at every boot | services killed permanently |
| `--with-snapshot` | `.zscripts/repo-snapshot.sh` refreshing the platform restore archive | extra anti-rollback layer |

The directories it writes (`download/`, `.zscripts/`, `memory/`, `worklog.md`) are exactly the ones the platform packer preserves; on every boot the `dev.sh` hook verifies the live skill installation against the release SHA-256 manifest and restores it from the canonical copy. Verified by a full fresh-sandbox reset simulation (38/38 checks, 3/3 field bugs closed, negative control reproduces the bugs without bootstrap). See `skills/stellar-trail/references/environment-resilience.md` section 7 for the complete guide.

The protocol itself invokes this at cold boot (Activation rule 14: `bootstrap-sandbox.sh --ensure` during M0), so arming no longer depends on remembering this page. Since v3.6.7 the update path finishes the job on its own: after every verified upgrade, `update-skill.sh` step [4/4] runs `bootstrap-sandbox.sh --ensure --with-explorer --with-snapshot`, so a post-update environment carries the FULL persistence layer (explorer + snapshot modules) instead of core alone — override with `STELLAR_UPDATE_BOOTSTRAP_ARGS` if your environment must stay core-only.

**Expected audit output before the first bootstrap:** on a fresh install `bash skills/stellar-trail/scripts/audit-compliance.sh` reports `C1 memory FAIL` (no `memory/` scaffold yet) and `C5 hook-R1 WARN` (worklog activation hook not appended yet) — by design. Both messages are installation-stage hints pointing at the fix; run `bootstrap-sandbox.sh` once and both checks flip to PASS.

### Task Files Explorer (opt-in)

`--with-explorer` also installs a built-in file browser — a stdlib Python server plus an MD3 Expressive web UI (a hero of two status tiles — Guard Status and Session Reset & Restore — a full-width Session Task list with expandable content summaries, a multi-column file card grid, search with debounce, filter chips, sorting, copy-path, adaptive theme) — as a functional replacement for popup "all files" previews. Launch it straight from the install tree:

```bash
bash skills/stellar-trail/assets/explorer/explorer.sh --ensure
```

The launcher (v1.4 — auto-deploy + process-freshness restart) deploys itself into `<project>/.zscripts/` and re-executes from there, leaving the install tree untouched; the boot hook then revives it after resets. Day-to-day control is idempotent: `bash .zscripts/explorer.sh --status | --stop | --ensure`. It serves on port 3000 by default and stands down automatically when a Next.js dev server owns that port; the boot chain health-checks it via `/healthz` and restores a stale copy from the canonical tree.

## What it does

- **6-phase execution discipline** — every user message, every session: classification grounded in a canonical rule book (Ground Base Knowledge), batched clarification, visible planning, tracked implementation, 5-layer validation, and concise reporting — all auditable via `## 🌠 PHASE n` phase markers and the protocol banner.
- **Persistent cross-session memory** — `SESSION-STATE` / `MEMORY` / handoff archives with a 95% integrity standard, ACTIVE-only task tables, sealed-task anti-resurrection, stale-task flags, continuation-summary quarantine, and a version-sanity alarm for degraded installations.
- **User-controlled by design** — plain markdown files you can open at any time, a cold-start consent gate, a strict no-secrets minimization rule, and same-turn inspect / correct / redact / delete / purge commands (SKILL.md section 4b).

## Repository layout

```
skills/stellar-trail/     the skill (installable)
  SKILL.md                protocol body — slim read, ~240 lines (English, v4.1.0)
  skill-card.md           canonical version + manifest card
  references/             4 deep references: ground-base-knowledge (classification),
                          memory-hygiene (full memory procedures + templates),
                          environment-resilience + task-files-explorer (deploy docs,
                          outside the M0 read path)
  scripts/                6 deterministic scripts: bootstrap-sandbox.sh, watcher.sh,
                          enforce-gates.sh, audit-compliance.sh, snapshot-repo.sh,
                          update-skill.sh
  assets/                 SHA-256 integrity manifest + Task Files Explorer (opt-in)
```

## Version

Current release: **v4.1.0** — see [CHANGELOG.md](CHANGELOG.md).

Verify the installation tree (run from `skills/stellar-trail/`):

```bash
sha256sum -c assets/integrity.sha256
```

## Background

Previously distributed via ClawHub (publisher [hoshiyomix](https://clawhub.ai/user/hoshiyomix)); this repository is now the canonical public distribution channel. Registry distribution is currently suspended by an automated security review that is under appeal — the package passes the registry's own static analyzer; the heuristic flag targets the skill's disclosed reset-survival features (boot hook, cache-replay installation restore, activation seed) that exist to keep agent work alive across container resets, fully documented in `skills/stellar-trail/references/environment-resilience.md`. License: MIT-0 — see [LICENSE](LICENSE).
