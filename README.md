# stellar-trail

[![skills.sh](https://skills.sh/badge/hoshiyomiX/stellar-trail)](https://skills.sh/hoshiyomiX/stellar-trail)

Unified execution discipline + persistent cross-session memory protocol for AI agents.

stellar-trail governs **how a task executes** inside a turn — a mandatory 6-phase workflow (classify → clarify → plan → implement → validate → report) — and **how its context survives** across sessions — a memory lifecycle (restore → checkpoint → compress → handoff) — so long-running agent work survives context resets, session restarts, and multi-session handoffs.

## Install

```bash
# OpenClaw
npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw

# Claude Code, Cursor, Codex, Copilot, Windsurf, Gemini CLI, Cline, AMP, Antigravity…
npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a claude
```

> **Activation rule:** a skill description in a list is NOT activation — load the full body via `Skill('stellar-trail')` at the first turn of every session or continuation, before responding. The SKILL.md enforces this itself.

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

Current release: **v3.6.0** — see [CHANGELOG.md](CHANGELOG.md).

Verify the installation tree (run from `skills/stellar-trail/`):

```bash
sha256sum -c assets/integrity.sha256
```

## Background

Previously distributed via ClawHub (publisher [hoshiyomix](https://clawhub.ai/user/hoshiyomix)); this repository is now the canonical public distribution channel after registry-side publication stalls. License: MIT-0 — see [LICENSE](LICENSE).
