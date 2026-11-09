# GitHub Repository Structure — stellar-trail

> Reference for the `hoshiyomiX/stellar-trail` repository: the proper tree, per-path
> descriptions, README blueprint, and release conventions. Use it when restructuring
> the repo, reviewing a change, or re-seeding after a reset. Shipped with the skill
> (v5.7.3, Task 74, owner order session 65). This file is documentation only — it
> changes nothing at runtime and sits outside the M0 read path.

## 1. Layout contract — single-skill repository

The repo follows the skills-CLI single-skill layout: the installable unit is
`skills/stellar-trail/` (exactly what `npx skills add` copies); everything else at
the root is repo chrome or source material for the bundled asset.

```text
stellar-trail/
├── .github/
│   └── workflows/
│       └── release.yml            # Release CI — ONE rolling `latest` release per main push
├── .gitignore                    # build noise only (node_modules/, explorer build scratch)
├── LICENSE                       # MIT
├── README.md                     # public face — see §3 blueprint
├── CHANGELOG.md                  # release ledger — newest section at the very top
├── explorer-src/                 # Vite source project for the explorer UI
│   ├── src/                      # App.vue · explorer.js · main.js · preview.js · theme.js
│   │   ├── components/           # FileList.vue · IconSprite.vue
│   │   └── style/                # explorer.css + base styles
│   ├── index.html
│   ├── package.json
│   └── vite.config.js            # single-file build → assets/explorer/explorer-ui/index.html
└── skills/
    └── stellar-trail/            # THE SKILL — the installable unit
        ├── SKILL.md              # protocol body, rules only (~310 lines; frontmatter wording-frozen)
        ├── skill-card.md         # registry card (intentionally OUTSIDE the checksum manifest)
        ├── references/           # on-demand depth — NEVER in the M0 read path
        │   ├── ground-base-knowledge.md     # GBK-T/L/C/A/E classification reference
        │   ├── memory-hygiene.md            # M0–M3 procedures, templates, H1–H13, budgets
        │   ├── environment-resilience.md    # anti-rollback playbook (resettable containers)
        │   ├── task-files-explorer.md       # explorer deploy & persistence guide
        │   ├── github-repo-structure.md     # THIS FILE
        │   └── android-apk-compose.md       # Kotlin/CMP companion-APK blueprint
        ├── scripts/              # bundled tooling — exec-bit-independent (bash <script>)
        │   ├── bootstrap-sandbox.sh   # arm the persistence layer (idempotent, offline)
        │   ├── update-skill.sh        # single-flow installer wrapper (origin probe + verified override)
        │   ├── watcher.sh             # verify-only runtime watchdog daemon
        │   ├── enforce-gates.sh       # terminal-track gates (artifact/lint/check-skill/check-worklog)
        │   ├── audit-compliance.sh    # external PASS/WARN/FAIL compliance audit
        │   ├── snapshot-repo.sh       # restore-archive refresh (repo.tar)
        │   ├── relock-skill.sh        # skills-lock.json computedHash re-pin
        │   └── ground-truth.sh        # M0 disk ground-truth card (v5.7.3)
        └── assets/
            ├── integrity.version   # release pin — live/canonical/dev trees must all match
            ├── integrity.sha256    # per-file checksum manifest (skill-card.md excluded by design)
            ├── explorer/           # Task Files Explorer payload (explorer.py v1.10 + UI v5.0.2
            │                       #  single-file build + explorer.sh launcher + dev.sh.template)
            └── harness-hooks/      # CLAUDE.md/AGENTS.md seeds + seed-hashes.txt registry
```

## 2. Per-path descriptions & invariants

| Path | What it is | Invariants to respect |
|---|---|---|
| `SKILL.md` | the protocol body — 6 phases, M0–M3, task-table hygiene, dual-track enforcement | frontmatter description is a measured trigger instrument, **wording-frozen**; the banner version string is a release constant (3 slots); validator anchors ride the body |
| `skill-card.md` | registry card shown by skill marketplaces | carries the version heading `## Skill Version(s):`; intentionally excluded from `integrity.sha256` (guarded by the watcher's release-file guard instead) |
| `references/*.md` | on-demand depth (GBK, memory-hygiene, env-resilience, TFE, + the two v5.7.3 additions) | never in the M0 read budget; each file keeps its own validator anchors |
| `scripts/*.sh` | the 8 bundled tools | plain-file, auditable; network ONLY in `update-skill.sh`'s explicit origin probe; `ground-truth.sh` never prints remote URLs (credential hygiene, D15) |
| `assets/integrity.version` + `integrity.sha256` | release pin + per-file manifest | all three trees (live `skills/`, canonical `download/`, dev `stellar-trail-dev/`) must match; regen rebuilds from the EXISTING path list — insert new files' paths first, then hash |
| `assets/explorer/` | the Task Files Explorer deploy payload | the UI is a single-file Vite build; source lives in `explorer-src/` and CI rebuilds it — the committed dist must stay reproducible |
| `assets/harness-hooks/` | guaranteed-context activation seeds for other harnesses | seeded create-if-absent + refreshed-if-byte-identical; a user-edited file is never touched; hashes registered in `seed-hashes.txt` |
| `explorer-src/` | UI source project | the ONLY place to edit the UI; the committed dist is a build product |
| `.github/workflows/release.yml` | the single release channel | trigger = every push to `main`; rolling `latest` release, deleted + re-created each run; vX.Y.Z tags are history, not release sources |

## 3. README blueprint

A proper README for this repo carries, in order:

1. **Title + one-liner** — what stellar-trail is (execution protocol + memory lifecycle for z.ai GLM agents).
2. **Install** — exactly one flow, verbatim: `npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw -y` (the deterministic full form; the minimal form fails in non-TTY sandboxes).
3. **What it does** — the 6-phase workflow and the M0–M3 memory lifecycle in one short table each.
4. **Bundled tooling** — the 8-script table (duty per script).
5. **References** — the six on-demand reference files with one-line descriptions.
6. **The Task Files Explorer** — the bundled dashboard (versions: server v1.10, launcher v1.5, UI v5.0.2), what it shows, how to opt out.
7. **Release conventions** — vX.Y.Z tags, rolling `latest`, CHANGELOG-first history.
8. **Compatibility & positioning** — z.ai GLM (Super Z) harnesses; harness-hooks for Claude Code-class readers.
9. **License** — MIT + pointer to `LICENSE`.

Keep it factual and versioned — stale versions in the README are validator-flagged (the v5.7.2 release fixed explorer v1.7/v4.4 → v1.10/v5.0.2).

## 4. Release conventions

- **Version slots** (all must move together): the 3 banner-constant slots in `SKILL.md`, the skill-card version line, `assets/integrity.version` ×3 trees, the manifest, and the skills-lock pin (relock after sync).
- **Three trees, one direction:** author in the dev clone → sync to the live install and the canonical `download/stellar-trail/` seed. Never sync backwards.
- **Tagging:** `vX.Y.Z` on `main`; the CHANGELOG section is prepended at the very top of the file (newest first).
- **Release CI:** one rolling `latest` release rebuilt on every push to `main` (trigger `branches: [main]`); vX.Y.Z tags are history, not release sources. (Verification note: confirm trigger filters with byte-level reads — terminal rendering can eat literal `[m` sequences from bracketed YAML lists and manufacture phantom "corruption.")
- **Manifest regen:** rebuild from the existing path list (the Task-11 lesson: a find-by-extension rebuild is wrong — `dev.sh.template` matches no extension). Insert new paths next to their siblings, then hash.
- **Census:** the sandbox tree census pin (`task62-verify`) gets re-pinned whenever files are added or removed.

## 5. Hygiene rules

- Never commit secrets. The sandbox's dev remote carries an embedded push credential in `git config` only — it must never appear in a committed file, a script output, or the repo.
- Validator anchors are contracts (`scripts/t70-anchor-contract.json` at the sandbox level): an edit that drops an anchor fails the chain — keep anchors verbatim.
- The worklog and memory files are append-only / atomic-rewrite respectively; the repo never rewrites history.
- `grep-first` line format for every ledger/memory entry (one fact per line, `[tag]` anchors, ISO dates).
