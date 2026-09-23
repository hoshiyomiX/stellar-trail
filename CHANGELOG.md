# Changelog

## v3.6.0 — 2026-09-23

First public GitHub release. Skill content is identical to the ClawHub-packaged 3.6.0 (SHA-256 integrity manifest preserved).

- 6-phase execution discipline + persistent cross-session memory lifecycle (protocol banner + FASE / [MEM] markers on every marked response)
- Memory hygiene: ACTIVE-only task table, same-write sealing, sealed-task anti-resurrection, stale flags (>72 h without progress), continuation-summary quarantine (H1–H13)
- Self-heal chain: multi-source `heal-skill.sh` with source self-verify, ClawHub-lock cross-check (DOWNGRADED verdict on rollback), sibling-location repair, class-A vault with anti-downgrade assert
- Enforcement dual-track: terminal-verifiable rules executed via `enforce-gates.sh`; external compliance audit via `audit-compliance.sh` (PASS/WARN/FAIL + exit code)
- Distribution migrated to GitHub + [skills.sh](https://skills.sh) after ClawHub registry publication stalls (3.5.6 → 3.6.0 never left "pending publication")

## v3.0.0 – v3.5.8 — ClawHub era

Highlights, newest first: v3.5.8 source self-verify (poisoned repair sources are skipped) · v3.5.7 ClawHub-lock cross-check + sibling-location healing · v3.5.5 worklog activation hook + external audit script · v3.5.4 class-A skill vault + Explorer UI v3.0 · v3.5.2 location-aware healing (flat + owner-scoped installs) · v3.5.1 M0 version-sanity alarm · v3.5.0 memory hygiene H1–H7 · v3.4.0 protocol banner · v3.3.0 bundled self-heal + integrity manifest · v3.1.0 Task Files Explorer · v3.0.0 🌠 on every phase marker (rename from workflow-memory-guardian, formerly stellar-trails).
