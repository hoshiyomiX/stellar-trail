# Changelog

## v3.6.1 — 2026-09-24

Consumer-sandbox remediation, born from field forensics on reset-prone sandboxes (three confirmed failure modes: skill files wiped because the packer excludes `skills/` from the restore archive; services killed with no boot hook to revive them; activation chain broken because `worklog.md` was never created).

- **New `scripts/bootstrap-sandbox.sh`** — one command arms the persistence layer: canonical copy under `download/stellar-trail/`, `.zscripts/dev.sh` boot hook that verifies the live install against the release manifest and restores it from the canonical copy on every boot, `worklog.md` seeded with the activation hook, `memory/` scaffolding with a consent-pending marker. Modular (`--with-explorer`, `--with-snapshot`), idempotent (`--ensure`), offline, self-locating; never touches `.clawhub/`, existing memory content, or a foreign `dev.sh`. One proven path per module — no redundant fallbacks.
- **Activation rule 14 + M0 step** — the protocol body now runs `bootstrap-sandbox.sh --ensure` at cold boot in reset-prone environments, so arming no longer depends on the user manually rebuilding the reference deployment.
- **Fix: packaged `explorer.sh`** — initialization-order bug (`ZDIR` computed before `PROJECT`); the launcher is now self-locating and exports `STELLAR_PROJECT`.
- **Fix: portability** — `bootstrap-sandbox.sh` uses `grep` only (no ripgrep dependency), matching the rest of the bundled scripts.
- **Refactor: protocol body** — heal-chain release history (v3.3.0 → v3.5.8) moved from SKILL.md section 4c to `references/environment-resilience.md` Appendix A (progressive disclosure; body stays under 500 lines at 490); Quick Reference and the final self-audit gained bootstrap lines; `environment-resilience.md` gained a table of contents and section 7 (consumer deployment guide).
- **Hygiene** — `__pycache__` no longer ships in the skill tree.
- Verification: fresh-sandbox reset simulation 38/38 PASS (3/3 field bugs closed, negative control reproduces them without bootstrap) + smoke: idempotency (double `--ensure`, zero changes), manifest 25/25 in canonical and live install.

## v3.6.0 — 2026-09-23

First public GitHub release. Skill content is identical to the ClawHub-packaged 3.6.0 (SHA-256 integrity manifest preserved).

- 6-phase execution discipline + persistent cross-session memory lifecycle (protocol banner + FASE / [MEM] markers on every marked response)
- Memory hygiene: ACTIVE-only task table, same-write sealing, sealed-task anti-resurrection, stale flags (>72 h without progress), continuation-summary quarantine (H1–H13)
- Self-heal chain: multi-source `heal-skill.sh` with source self-verify, ClawHub-lock cross-check (DOWNGRADED verdict on rollback), sibling-location repair, class-A vault with anti-downgrade assert
- Enforcement dual-track: terminal-verifiable rules executed via `enforce-gates.sh`; external compliance audit via `audit-compliance.sh` (PASS/WARN/FAIL + exit code)
- Distribution migrated to GitHub + [skills.sh](https://skills.sh) after ClawHub registry publication stalls (3.5.6 → 3.6.0 never left "pending publication")

## v3.0.0 – v3.5.8 — ClawHub era

Highlights, newest first: v3.5.8 source self-verify (poisoned repair sources are skipped) · v3.5.7 ClawHub-lock cross-check + sibling-location healing · v3.5.5 worklog activation hook + external audit script · v3.5.4 class-A skill vault + Explorer UI v3.0 · v3.5.2 location-aware healing (flat + owner-scoped installs) · v3.5.1 M0 version-sanity alarm · v3.5.0 memory hygiene H1–H7 · v3.4.0 protocol banner · v3.3.0 bundled self-heal + integrity manifest · v3.1.0 Task Files Explorer · v3.0.0 🌠 on every phase marker (rename from workflow-memory-guardian, formerly stellar-trails).
