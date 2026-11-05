# stellar-trail

[![skills.sh](https://skills.sh/b/hoshiyomiX/stellar-trail)](https://skills.sh/hoshiyomiX/stellar-trail)

Unified execution discipline + persistent cross-session memory protocol — **purpose-built for z.ai GLM agents (Super Z)**.

stellar-trail governs **how a task executes** inside a turn — a mandatory 6-phase workflow (classify → clarify → plan → implement → validate → report) — and **how its context survives** across sessions — a memory lifecycle (restore → checkpoint → compress → handoff) — so long-running agent work survives context resets, session restarts, and multi-session handoffs. The protocol body is deliberately slim (~310 lines, English only): deep procedures live in four on-demand references, and the M0 read path is hard-budgeted — the field-proven diagnosis being that oversized read paths breed overthinking and compliance violations. Checkpoints follow a fixed write order (snapshot first, ledger append last, one checkpoint per completed artifact), every task-sealing checkpoint refreshes the restore archive, and an external audit script catches drift the model's own discipline misses.

## Install

One command — the verified install flow, live-tested on the z.ai sandbox platform:

```bash
npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw -y --json
```

- `--skill stellar-trail` selects the skill; `-a openclaw` selects the agent adapter (swap it for your harness id — `claude`, `cursor`, `codex`, …); `-y --json` makes the run fully non-interactive.
- **Keep `-a` and `-y`.** Without them the CLI drops into an interactive agent-selection prompt that cannot complete without a TTY (agent sandboxes, CI) — measured live: the minimal form aborts with `Interactive prompt required but stdin is not a TTY…`; the full form delivers byte-identical content in ~4 s, exit 0.
- This is deliberately the ONLY install flow — installing, re-installing, and repairing all run the same command; no parallel installer, no fallback route, and every alarm prints this command as the remediation. Installer: the open-source [vercel-labs/skills](https://github.com/vercel-labs/skills) CLI.

Verify the tree after installing (the SHA-256 manifest turns "trust the publisher" into a deterministic check you can audit yourself):

```bash
cd <skills-dir>/stellar-trail && sha256sum -c assets/integrity.sha256   # expect: all OK
npx skills list   # expect stellar-trail, source hoshiyomiX/stellar-trail
```

To update later: `bash skills/stellar-trail/scripts/update-skill.sh --ensure` (the bundled single-flow updater — an always-check origin probe at every M0, then a verified override that runs the same install command, re-arms the persistence layer, relocks the skills-lock.json pin, and closes with a RELOAD directive), or simply re-run the install command.

**Install ≠ activation.** The CLI copies the files and exits — the explorer server, the watcher daemon, the boot hook, and the canonical snapshot all come from the bundled bootstrap step, which the protocol runs at cold boot (Activation rule 4) and which you can run yourself at any time:

```bash
bash skills/stellar-trail/scripts/bootstrap-sandbox.sh --ensure
```

A plain `--ensure` arms the full stack — the explorer, snapshot, and harness-hooks modules auto-enable whenever their payload ships in the install tree (opt out with `--without-explorer` / `--without-snapshot` / `--without-harness-hooks`). The hooks module seeds `CLAUDE.md` + `AGENTS.md` at the project root (create-if-absent — an existing user file is never touched) so harnesses that auto-read them at session start receive a guaranteed-context activation directive.

### Activation, honestly measured

The shipped frontmatter description is the best activation captor ever measured for this skill — and honestly imperfect. On the reference battery (10 human first-turn task messages × 3 runs, real distractor skills present, zero errors) it captures **8/10**; the same-day control of the prior formula reproduced its historical 7/10 exactly (no day effect), and the z.ai GLM scoping sentence placed AFTER the fused opening recovered the mixed greeting+task cell — the first variant family ever to win it (a front-prefix variant measured 6/10 and was rejected). The 2 remaining misses are structural, not wording. The formula is wording-frozen by measurement (2026-10-12): a 16-character efficiency trim and a single-variable workflow-sentence swap were both rejected on the mixed cell (0/6 and 1/3 vs the control's 5/6 — 87 calls, zero final errors); the description stays byte-identical at 877/1024. Honest conclusion: wording alone cannot deliver "always load" — the harness hooks add a genuinely guaranteed activation context, and the recovery nets (R1 hooks on the memory headers + every worklog section's first line, the standing worklog-tail guard, rule 6's late-load recovery) catch the remainder.

**Field evidence (2026-10-21, first documented incident):** a continuation summary carrying heavy technical narrative defeated the 8/10 doorbell in the wild — two sessions of real, high-risk work ran with zero protocol compliance while every machine sentinel stayed silent (the compliance sentinel needed the worklog to grow; these sessions wrote nothing). The user caught it, not the machine. Consequences shipped in v5.4.0: the silent-work sentinel alarms from DISK evidence and raises a user-visible `download/ALERT-ACTIVE.md` (alarms previously reached only files a compliant session would read — the guard-that-cannot-wake-the-guard paradox); M0 gained an artifact-freshness sweep; the external audit runs on a ~6 h schedule with a `silent-work` check. Defense map: doorbell description (8/10) → harness hooks → R1 file hooks + tail guard → rule-6 recovery → duty-6b alarms + ALERT surface → M0 freshness sweep → periodic audit. The LAST layer is the owner's eyes: **audit the responses — every marked response opens with the stellar-trail banner.** A pre-response hook (block the first response until the skill loads) has no harness API — a documented limit, not an implemented feature.

## What's in the package

| Piece | Role |
|---|---|
| `SKILL.md` | The slim protocol body (~310 lines): 6-phase execution, memory lifecycle M0–M3, task pickup decision table + auto-seal (D14) Seal Ritual / Resume Protocol / UNSEAL pathway, platform alignment, enforcement dual-track |
| `scripts/bootstrap-sandbox.sh` | One-command persistence-layer arming: canonical copy, boot hook (SHA-256-verified restore with a no-downgrade gate), watcher deploy + daemon ensure, worklog seed + tail guard, memory scaffold; explorer/snapshot/hooks modules auto-enable with their payload |
| `scripts/update-skill.sh` | Single-flow updater: always-check origin probe, verified override, full-stack re-arm + pin relock + RELOAD directive |
| `scripts/watcher.sh` | Runtime watchdog v2.3 (verify-only): explorer health + revive, deployment-gap notice, integrity checks ~10 min, release-file guard, archive refresh ~15 min, compliance sentinel, silent-work sentinel + ALERT surface ~2 min, ~24h origin release probe (alarm-only), periodic compliance audit ~6 h; started at boot (dev.sh) and at every `bootstrap --ensure` — the daemon can die silently at container lifecycle events |
| `scripts/enforce-gates.sh` | Terminal-track gate checks (artifact, lint, check-skill, check-worklog) |
| `scripts/snapshot-repo.sh` | Restore-archive refresh: backup-first, verify-before-swap, anti-traversal audit, keep-latest retention, gated `--apply-auto` |
| `scripts/relock-skill.sh` | Standalone skills-lock.json pin re-pinner (the CLI's exact algorithm); `--check` = verify-only |
| `assets/explorer/` | Task Files Explorer (server v1.10, launcher v1.5, UI v5.0.2 miuix-vue — content-signature change detection, silent first paint + offscreen card skip, fetch resilience with steady 10 s retry, platform-preview kill + static-copy auto-breakout, zero in-app popups beyond the preview modal): the built-in dashboard on the preview URL |
| `assets/harness-hooks/` | CLAUDE.md + AGENTS.md templates — guaranteed-context activation for harnesses that auto-read project-root files |
| `references/` | Four on-demand references: memory-hygiene, ground-base-knowledge, environment-resilience, task-files-explorer |

All scripts are plain-file, auditable, exec-bit-independent (`bash scripts/<name>.sh`), make no network calls except the updater's explicit origin check, and run only when invoked.

## Troubleshooting

**`npx skills add` without flags fails with "Interactive prompt required but stdin is not a TTY"** — expected in every non-TTY environment: the CLI ends in an interactive agent-selection prompt. Re-run with the full verified form above.

**The skills CLI summary box prints a non-existent `.agents/skills/…` path** — a known upstream CLI display issue (vercel-labs/skills#2376); the JSON output and `skills-lock.json` are correct — the skill lands in `skills/stellar-trail/` as expected.

**The explorer shows a "Static copy" banner** — expected when `index.html` is opened without its server (platform file preview, a downloaded copy): on an http(s) origin the UI probes once for the live server and AUTO-BREAKS OUT to the live root (Task 67); when navigation is sandbox-blocked the banner + "Open live view" button remain. Deploy with `bash skills/stellar-trail/scripts/bootstrap-sandbox.sh --ensure` (or `bash .zscripts/explorer.sh --ensure`).

**The dashboard is up but the watcher daemon is dead** — expected after container freeze/thaw or session-start process reaping: the daemon can die silently while the explorer survives. It self-heals at the next `bootstrap-sandbox.sh --ensure` or container boot via dev.sh; check with `bash .zscripts/watcher.sh --status`. A deliberate `--stop` (stop-flag) is always respected — delete `.zscripts/watcher.stop` (or `--force-start`) to let it start again.

**The worklog tail has no ⚡ACTIVATE line even though the protocol ran** — an agent that never loaded the skill appends structurally-correct sections without their activation hook line, leaving the tail (the one part the next session reads) bare. The tail guard re-appends the directive at the next `bootstrap-sandbox.sh --ensure` or boot — append-only, existing content is never edited; nothing is lost.

**`download/ALERT-ACTIVE.md` appeared in the file list** — the watcher's user-visible alarm surface (v5.4.0): work artifacts or uploaded evidence are running ahead of the last memory checkpoint, or the worklog is growing without one — i.e. the protocol is not running as specified in some session. Read the file: it names the active classes and the remediation. The agent should load the skill, run M0, and verify the unlogged work from disk (rule-6 posture); the file is removed automatically once every class clears. Ignoring it at session start is a protocol violation.

## License

MIT No Attribution — see [LICENSE](LICENSE).
