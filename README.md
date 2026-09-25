# stellar-trail

[![skills.sh](https://skills.sh/b/hoshiyomiX/stellar-trail)](https://skills.sh/hoshiyomiX/stellar-trail)

Unified execution discipline + persistent cross-session memory protocol for AI agents.

stellar-trail governs **how a task executes** inside a turn — a mandatory 6-phase workflow (classify → clarify → plan → implement → validate → report) — and **how its context survives** across sessions — a memory lifecycle (restore → checkpoint → compress → handoff) — so long-running agent work survives context resets, session restarts, and multi-session handoffs.

## Install

### Option 1 — git clone + verify (recommended)

Zero remote code execution: this downloads static files only and runs nothing from the repo. The SHA-256 manifest turns "trust the publisher" into a deterministic check you can audit yourself.

```bash
git clone --depth 1 https://github.com/hoshiyomiX/stellar-trail.git /tmp/stellar-trail-src
# copy into your agent's skills directory, e.g. skills/ (OpenClaw) or .claude/skills/ (Claude Code)
cp -r /tmp/stellar-trail-src/skills/stellar-trail <skills-dir>/stellar-trail
cd <skills-dir>/stellar-trail && sha256sum -c assets/integrity.sha256   # expect: 25/25 OK
```

### Option 2 — skills.sh installer (one command)

```bash
# OpenClaw
npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw

# Claude Code, Cursor, Codex, Copilot, Windsurf, Gemini CLI, Cline, AMP, Antigravity…
npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a claude
```

The installer is the open-source [vercel-labs/skills](https://github.com/vercel-labs/skills) CLI. Both routes above are verified end-to-end on a live consumer sandbox (real installs, tree re-verified 25/25 against the manifest). If your environment's policy restricts `npx`, use Option 1. Whichever option you choose, verify the tree after installing:

```bash
cd <skills-dir>/stellar-trail && sha256sum -c assets/integrity.sha256   # expect: 25/25 OK
```

> **ClawHub registry — currently unavailable:** `clawhub install hoshiyomix/stellar-trail` stopped working when the registry suspended the publisher account via an automated malware-suspicion review (under appeal; the package passes the registry's own static analyzer, and every installed file is independently verifiable via the manifest). Until that resolves, this repository is the canonical channel — use Option 1 or 2.

> **Activation rule:** a skill description in a list is NOT activation — load the full body via `Skill('stellar-trail')` at the first turn of every session or continuation, before responding. The SKILL.md enforces this itself.

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
| core (always) | canonical copy under `download/stellar-trail/` + `.zscripts/dev.sh` boot hook + `worklog.md` (activation hook) + `memory/` scaffold | skill files wiped on reset · activation chain broken |
| `--with-explorer` | `.zscripts/` explorer (launcher + server + UI) revived at every boot | services killed permanently |
| `--with-snapshot` | `.zscripts/repo-snapshot.sh` refreshing the platform restore archive | extra anti-rollback layer |

The directories it writes (`download/`, `.zscripts/`, `memory/`, `worklog.md`) are exactly the ones the platform packer preserves; on every boot the `dev.sh` hook verifies the live skill installation against the release SHA-256 manifest and restores it from the canonical copy. Verified by a full fresh-sandbox reset simulation (38/38 checks, 3/3 field bugs closed, negative control reproduces the bugs without bootstrap). See `skills/stellar-trail/references/environment-resilience.md` section 7 for the complete guide.

The protocol itself invokes this at cold boot (Activation rule 14: `bootstrap-sandbox.sh --ensure` during M0), so arming no longer depends on remembering this page.

## What it does

- **6-phase execution discipline** — every user message, every session: classification grounded in a canonical rule book (Ground Base Knowledge), batched clarification, visible planning, tracked implementation, 5-layer validation, and concise reporting — all auditable via `## 🌠 FASE n` phase markers and the protocol banner.
- **Persistent cross-session memory** — `SESSION-STATE` / `MEMORY` / handoff archives with a 95% integrity standard, ACTIVE-only task tables, sealed-task anti-resurrection, stale-task flags, continuation-summary quarantine, and a version-sanity alarm for degraded installations.
- **User-controlled by design** — plain markdown files you can open at any time, a cold-start consent gate, a strict no-secrets minimization rule, and same-turn inspect / correct / redact / delete / purge commands (SKILL.md section 4b).

## Repository layout

```
skills/stellar-trail/     the skill (installable)
  SKILL.md                protocol body (bilingual: EN rules + ID explanations)
  references/             deep references per phase & per memory mechanism
  scripts/                deterministic gates: enforce-gates.sh, audit-compliance.sh,
                          heal-skill.sh, snapshot-repo.sh, vault-sync.sh
  assets/                 SHA-256 integrity manifest + Task Files Explorer (opt-in)
```

## Version

Current release: **v3.6.2** — see [CHANGELOG.md](CHANGELOG.md).

Verify the installation tree (run from `skills/stellar-trail/`):

```bash
sha256sum -c assets/integrity.sha256
```

## Background

Previously distributed via ClawHub (publisher [hoshiyomix](https://clawhub.ai/user/hoshiyomix)); this repository is now the canonical public distribution channel. Registry distribution is currently suspended by an automated security review that is under appeal — the package passes the registry's own static analyzer; the heuristic flag targets the skill's disclosed reset-survival features (boot hook, self-heal, activation seed) that exist to keep agent work alive across container resets, fully documented in `skills/stellar-trail/references/environment-resilience.md`. License: MIT-0 — see [LICENSE](LICENSE).
