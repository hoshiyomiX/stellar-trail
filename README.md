# stellar-trail

[![skills.sh](https://skills.sh/b/hoshiyomiX/stellar-trail)](https://skills.sh/hoshiyomiX/stellar-trail)

Unified execution discipline + persistent cross-session memory protocol — **purpose-built for z.ai GLM agents (Super Z)**.

stellar-trail governs **how a task executes** inside a turn — a mandatory 6-phase workflow (classify → clarify → plan → implement → validate → report) — and **how its context survives** across sessions — a memory lifecycle (restore → checkpoint → compress → handoff) — so long-running agent work survives context resets, session restarts, and multi-session handoffs. The protocol body is deliberately slim (~240 lines, English only): deep procedures live in four on-demand references, and the M0 read path is hard-budgeted — the field-proven diagnosis being that oversized read paths breed overthinking and compliance violations. Checkpoints follow a fixed write order (snapshot first, ledger append last, one checkpoint per completed artifact), every task-sealing checkpoint refreshes the restore archive, and an external audit script catches drift the model's own discipline misses.

## Install

One command — the verified install flow, live-tested on the z.ai sandbox platform:

```bash
npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw -y --json
```

- `--skill stellar-trail` selects the skill from the repo; `-a openclaw` selects the agent adapter (swap it for your harness id — `claude`, `cursor`, `codex`, …); `-y --json` makes the run fully non-interactive.
- **Keep `-a` and `-y`.** Without them the CLI drops into an interactive agent-selection prompt that cannot complete in any environment without a TTY (agent sandboxes, CI). Measured live on the z.ai sandbox: the minimal form aborts with `Interactive prompt required but stdin is not a TTY. Nothing was installed. Use --agent <name> (or --agent '*') and -y to run non-interactively.` — while the full form delivers byte-identical content in ~4 s, exit 0.
- This is deliberately the ONLY install flow — installing, re-installing, and repairing all run the same command; the package has no parallel installer and no fallback route, and every alarm it can raise prints this command as the remediation.
- The installer is the open-source [vercel-labs/skills](https://github.com/vercel-labs/skills) CLI.

Verify the tree after installing (the SHA-256 manifest turns "trust the publisher" into a deterministic check you can audit yourself):

```bash
cd <skills-dir>/stellar-trail && sha256sum -c assets/integrity.sha256   # expect: 18/18 OK
npx skills list   # expect stellar-trail, source hoshiyomiX/stellar-trail
```

To update later: `bash skills/stellar-trail/scripts/update-skill.sh --ensure` (the bundled single-flow updater — an always-check origin probe at every M0, then a four-step verified override that runs the same install command and re-arms the persistence layer), or simply re-run the install command.

**Install ≠ activation.** The CLI copies the files and exits — the explorer server, the watcher daemon, the boot hook, and the canonical snapshot all come from the bundled bootstrap step, which the protocol runs at cold boot (Activation rule 14) and which you can run yourself at any time:

```bash
bash skills/stellar-trail/scripts/bootstrap-sandbox.sh --ensure
```

A plain `--ensure` arms the full stack — the explorer, snapshot, and harness-hooks modules auto-enable whenever their payload ships in the install tree (opt out with `--without-explorer` / `--without-snapshot` / `--without-harness-hooks`). The hooks module seeds `CLAUDE.md` + `AGENTS.md` at the project root (create-if-absent — an existing user file is never touched) so harnesses that auto-read them at session start receive a guaranteed-context activation directive.

### Activation, honestly measured

The shipped frontmatter description is the best activation captor ever measured for this skill — and honestly imperfect. On the reference battery (10 human first-turn task messages × 3 runs, real distractor skills present, zero errors) it captures **8/10** — the best score of any description variant ever measured for this skill. The same-day control of the prior formula reproduced its historical 7/10 exactly, ruling out a day effect; the z.ai GLM scoping sentence ("Purpose-built for z.ai GLM agents (Super Z)", placed after the fused opening) also recovered the mixed greeting+task cell — the first variant family ever to win it. A front-prefix scoping variant measured 6/10 the same day and was rejected: scoping AFTER the fused opening is the winning position. The 2 remaining misses are structural, not wording — a quick technical question reads as conversational, and an explicit chart ask is won by the host harness's own domain-skill-first rule. The machine-content NOT-clause is byte-identical to the previously measured formula (its negative battery was not re-run for this release; the field record there is unchanged). The honest conclusion: description wording alone cannot deliver "always load" — the harness hooks add a genuinely guaranteed activation context wherever the host harness auto-reads project-root files, and the recovery nets (R1 header hooks on the memory files + worklog, and Activation rule 16's late-load recovery) catch the remainder.

## What's in the package

| Piece | Role |
|---|---|
| `SKILL.md` | The slim protocol body (~240 lines): 6-phase execution, memory lifecycle M0–M3, task-table hygiene, enforcement dual-track |
| `scripts/bootstrap-sandbox.sh` | One-command persistence-layer arming: canonical copy, boot hook (SHA-256-verified restore with a no-downgrade gate), watcher deploy, worklog seed, memory scaffold; explorer/snapshot/hooks modules auto-enable with their payload |
| `scripts/update-skill.sh` | Single-flow updater: always-check origin probe, four-step verified override, full-stack re-arm |
| `scripts/watcher.sh` | runtime watchdog v2.2 (verify-only): explorer health + revive, deployment-gap notice, integrity checks ~10 min, release-file guard, archive refresh ~15 min, compliance sentinel, ~24h origin release probe (alarm-only) |
| `scripts/enforce-gates.sh` | Terminal-track gate checks (artifact, lint, check-skill, check-worklog) |
| `scripts/snapshot-repo.sh` | Restore-archive refresh: backup-first, verify-before-swap, anti-traversal audit, gated `--apply-auto` |
| `scripts/audit-compliance.sh` | External compliance audit from on-disk artifacts: PASS/WARN/FAIL + exit code |
| `assets/explorer/` | Task Files Explorer (server v1.4, launcher v1.5, UI v3.4): the built-in dashboard on the preview URL |
| `assets/harness-hooks/` | CLAUDE.md + AGENTS.md templates — guaranteed-context activation for harnesses that auto-read project-root files |
| `references/` | Four on-demand references: memory-hygiene, ground-base-knowledge, environment-resilience, task-files-explorer |

All scripts are plain-file, auditable, exec-bit-independent (`bash scripts/<name>.sh`), make no network calls except the updater's explicit origin check, and run only when invoked.

## Troubleshooting

**`npx skills add` without flags fails with "Interactive prompt required but stdin is not a TTY"** — expected in every non-TTY environment (agent sandboxes, CI): the CLI ends in an interactive agent-selection `readline` prompt that cannot resolve without a TTY. Re-run with the full verified form above (`--skill … -a <agent> -y --json`).

**The skills CLI summary box prints a non-existent `.agents/skills/…` path** — a known upstream CLI display issue (vercel-labs/skills#2376); the JSON output and `skills-lock.json` are correct — the skill lands in `skills/stellar-trail/` as expected.

**The explorer shows a "Static copy" banner** — expected when `index.html` is opened without its server (platform file preview, a downloaded copy): the UI degrades to an informational banner; on an http(s) origin it probes once for the live server and offers an "Open live view" button. Deploy the explorer with `bash skills/stellar-trail/scripts/bootstrap-sandbox.sh --ensure` (or `bash .zscripts/explorer.sh --ensure`).

## License

MIT No Attribution — see [LICENSE](LICENSE).
