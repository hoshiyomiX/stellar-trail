# Task Files Explorer (Built-in Asset) — Deploy & Operations Reference

> A stellar-trail built-in asset: server v1.4 · launcher v1.5 · UI v3.4. The explorer is an
> **optional & opt-in tool** — not part of the protocol mandate. It functionally replaces the
> platform's "All files in task" popup with a custom page on the preview URL.

## 0. When to Use

Use when the user (any language):
- wants a custom web page / index.html served on the platform preview URL;
- wants a persistent file dashboard (download/ + archive/) that comes alive automatically at every boot;
- asks how to make a script/service survive container restarts (the /start.sh hook).

**Do NOT use** when the project is an interactive web app (Next.js etc.) — the project's web
server always has priority rights to port 3000; the explorer stands down automatically (the
guard lives in explorer.sh).

## 1. Architecture (verified empirically on the Z.ai container platform)

```
preview-<bot-id>.space-z.ai        (platform frontend — the popup can simply be ignored)
  -> platform ingress :81          (reverse proxy, env FC_CUSTOM_LISTEN_PORT)
     -> 127.0.0.1:3000             (upstream — OUR SIDE)
        -> explorer.py             (Python stdlib server; UI = explorer-ui/index.html, adaptive MD3-style)
```

Key facts:
1. When the :3000 upstream is empty, the ingress answers with a 502 placeholder; as soon as a
   server listens on 3000, the entire preview URL serves that server.
2. The preview popup is a platform browser frontend — it cannot be turned off from inside the
   container; what CAN be replaced is the CONTENT of the preview URL.
3. Ordinary processes die when a tool call finishes (the platform kills the descendant tree);
   the only way a daemon stays alive is a **double-fork orphan** (PPID=1 + setsid).

## 2. File Manifest (assets/explorer/)

| File | Role |
|------|-------|
| `explorer.py` | Python stdlib server v1.4 (ThreadingHTTPServer): `/api/files` walk (depth-4, task parsing from worklog.md) with the `guard` block (live vs canonical version + in-sync flag, watcher liveness/pid, THIS process's code freshness via its content stamp, Next.js stand-down flag) and `resets` block (boot resets, skill restores, snapshot restores, explorer restarts — counters + last timestamps parsed from `.zscripts/boot.log` + `.zscripts/explorer.log`; missing logs = empty counters, never an error); `/api/tasks` — the Session Task list parsed from `memory/SESSION-STATE.md` (Active + Sealed tables + checkpoint line; missing file = empty structure, never an error); file serving with a realpath guard (only inside ROOTS) + `?dl=1` attachment mode; PIDFILE + CODE STAMP (md5 of the server's own source written at startup — the content-exact freshness anchor); env `STELLAR_PROJECT` (default /home/z/my-project), port via argv[1] (default 3000) |
| `explorer.sh` | Launcher v1.5 — `--ensure`/`--status`/`--stop`; Next.js guard (package.json wins); double-fork orphan; AUTO-DEPLOY from the install tree (a launcher run at `skills/stellar-trail/assets/explorer/` copies itself + server + UI into `<root>/.zscripts/` and re-execs there — the install tree stays drift-free); sync-fresh vs the canonical copy (md5 drift → re-copy; `explorer.py` changed → server restart); PROCESS-FRESHNESS RESTART (content-exact: md5 of the deployed explorer.py vs the code stamp the server wrote at startup — a live server predating the deployed code restarts on `--ensure`); hardened stop (`kill_wait`: TERM → poll ≤5 s → KILL; pid-identity guard via `/proc/<pid>/cmdline` — a recycled pid is never killed); a live server with a missing pidfile is healed by restart; activated deploy-time by bootstrap-sandbox.sh |
| `explorer-ui/index.html` | UI v3.4 — zero-dependency MD3-style dashboard (no CDN, no web font), fully English, adaptive dark/light theme: sidebar navigation + stat cards + task rail; release-health tile row (Skill Version hero + Boot Resets / Skill Restores / Snapshot Restores — official Google Material Icons classic filled 24 px embedded verbatim); Session Task list (active task cards + sealed rows with one-click artifact preview); 200 ms debounced live search (name/extension/task ID), category filter chips, sort, per-card copy-path + toast, preview dialog with `?dl=1`, chunked lazy render, 10 s polling + refresh-on-focus; STATIC-COPY graceful mode (opened without its server — platform file preview, a downloaded copy — the UI shows an informational banner and suppresses the retry-snackbar loop) + MANUAL live-recovery (1 s after static detection the page probes `/api/files` once; an explorer.py-shaped JSON answer upgrades the banner to "live explorer reachable" with an **Open live view** button — never auto-navigates; a later failed probe removes the button; while static a JSON answer never renders data in-place) |
| `dev.sh.template` | Legacy boot-hook template: tidy download/ → archive/, fullstack guard, ensure watcher + explorer, periodic repo.tar refresh. Superseded by the bootstrap-generated dev.sh (which adds the cache-replay skill restore with the version gate); kept as reference — see the template header note |

## 3. Deploy Steps

### Case A — fresh container (no .zscripts/dev.sh yet)

> **Easiest path: AUTO-DEPLOY.** Run directly from the install tree — `bash
> skills/stellar-trail/assets/explorer/explorer.sh --ensure` — the launcher detects the
> install layout, copies itself + explorer.py + the UI to `<project>/.zscripts/`, then re-execs
> from there. No manual steps, no writes inside the install tree. The manual steps below
> remain valid.

1. Copy the assets to the active location (default project root /home/z/my-project):
   `cp assets/explorer/explorer.py assets/explorer/explorer.sh <project>/.zscripts/`
   `mkdir -p <project>/.zscripts/explorer-ui && cp assets/explorer/explorer-ui/index.html <project>/.zscripts/explorer-ui/`
   `cp assets/explorer/dev.sh.template <project>/.zscripts/dev.sh && chmod +x <project>/.zscripts/dev.sh`
   `cp scripts/watcher.sh <project>/.zscripts/`   # watchdog — referenced by dev.sh §3; installed automatically by bootstrap core
2. Run once: `bash <project>/.zscripts/explorer.sh --ensure`
3. Every subsequent boot, /start.sh runs dev.sh -> explorer + watcher come alive automatically.

   One-command alternative for the whole persistence layer (skill + worklog +
   memory scaffold + explorer): `bash scripts/bootstrap-sandbox.sh --ensure` (the
   explorer module auto-enables when its payload ships in the tree).

### Case B — dev.sh already exists (do NOT overwrite it)
1. Copy explorer.py, explorer.sh, explorer-ui/ as above — plus `scripts/watcher.sh` to `<project>/.zscripts/` (the daemon referenced by dev.sh §3; shipped in the package and installed automatically by bootstrap core).
2. Append an ensure block at the end of dev.sh:
   ```bash
   if [ -f "$PROJECT/.zscripts/explorer.sh" ]; then
       bash "$PROJECT/.zscripts/explorer.sh" --ensure >> "$BOOTLOG" 2>&1 || log "WARN: explorer failed"
   fi
   ```
3. Run `bash .zscripts/explorer.sh --ensure`.

## 4. Port Conflict Rules (MUST be respected)

- A `package.json` in the project root -> Next.js owns :3000 -> explorer STANDS DOWN.
- Port 3000 held by a non-explorer process -> the explorer refuses to start (logs only).
- The explorer binds 127.0.0.1 only — never exposed directly to the outside; external access
  always goes through the platform ingress.

## 5. Persistence Layers

1. **repo.tar pre-stop** — the platform packs the volume before stopping; .zscripts/ is backed up with it.
2. **The /start.sh hook** — every boot runs dev.sh when present.
3. **dev.sh** — ensures explorer.sh + watcher.sh.
4. **The 30-second watchdog** — auto-heal when the explorer dies (verified: kill -9 -> back alive in <=30 s).
5. **The protocol's M0** — every new session ensures the watcher is alive.
6. **Anti-rollback layers** — when the environment resets: see `references/environment-resilience.md`
   + `scripts/snapshot-repo.sh` (one problem, one family of solutions).

## 5a. Recycle vs Rollback Symptoms — Tell Them Apart Before Reasoning

Two environment failures that are easy to confuse:

- **Preview explorer dead** (the :3000 process is gone, "index.html killed") = a **container
  recycle** signature — processes living in the container (the explorer server, the watcher)
  die with the container; THIS IS NOT a skill bug. The built-in asset
  `assets/explorer/explorer-ui/index.html` stays intact inside the installation. Remedy:
  opt-in redeploy — `bash .zscripts/explorer.sh --ensure` (dev.sh/watcher revive it
  automatically at the next boot when the /start.sh hook is active).
- **Installed asset files missing / version regressed** (built-in assets gone, an old body
  version banner, new release components absent) = a **restore-archive rollback** signature —
  the skill installation was overwritten by a stale archive. Remedy: re-run the single install
  command (`npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw -y`), or
  `bash skills/stellar-trail/scripts/update-skill.sh --force`; the M0 version sanity alarm and
  the watcher's integrity check report the degradation (see environment-resilience.md §3c/§4).

Compact rule: **processes dead → recycle (redeploy); files changed/missing → rollback
(re-install)**.

## 6. Control Commands

```
bash .zscripts/explorer.sh --status   # health + log
bash .zscripts/explorer.sh --stop     # stop the explorer
bash .zscripts/explorer.sh --ensure   # start when not running (idempotent)
```

**Ethics & limits:** the explorer only serves the working directories (ROOTS download/ +
archive/), read-only, loopback-bound. It is never used to expose files outside the project,
and its deployment is always announced to the user (never a silent initiative) — consistent
with the consent principle of section 4b and the infrastructure-intervention-only-on-request
principle of section 4c.

## 7. Deployment Freshness — sync-fresh + process freshness

The problem: when the explorer is deployed as a COPY (the maintainer pattern:
`.zscripts/explorer.py` + `.zscripts/explorer-ui/index.html` outside the skill installation),
checking only ALIVENESS (`healthz`) misses FRESHNESS. A stale copy (an old `repo.tar` restore,
or a new UI release that was never copied) keeps running with nobody noticing:
*alive-but-stale*.

The mechanism (in `explorer.sh`):

- `--ensure` calls `sync_fresh()` BEFORE the aliveness check: `explorer.py` and
  `explorer-ui/index.html` are compared (`cmp`) against the canonical copy
  (`$PROJECT/download/stellar-trail/assets/explorer/`); drift -> re-copy + a `sync-fresh`
  log line; `explorer.py` changed -> server restart (the UI is read per-request — a copy
  suffices).
- `--status` shows a `fresh : server=ok ui=ok (vs canonical)` line.
- Alive-but-stale is repaired automatically, not just dead-then-started.
- File freshness alone was not enough: on the first-hop upgrade path bootstrap syncs the
  `.zscripts` files BEFORE `--ensure` ever runs, so `sync_fresh` sees no drift while the
  RUNNING PROCESS still serves the previous release's code. The server therefore writes the
  md5 of its own source to `.zscripts/explorer.code-stamp` at startup, and `--ensure`
  restarts any live server whose stamp no longer matches the deployed file — the process,
  not just the files, follows the release.
- THE TRIGGER MAP is complete — dev.sh covers BOOT, the watcher covers DEATH (health-fail
  only), and bootstrap-sandbox.sh covers DEPLOY-TIME: it runs `explorer.sh --ensure` at the
  end of every invocation (output to boot.log; failure never fails bootstrap), so
  update-skill's step [4/4] — which deploys the files via bootstrap — activates them in the
  same run. The upgrade-path gap (a healthy old server surviving a first-hop untouched) is
  closed on every path that can deploy explorer assets.

Field evidence (controlled drill): the process was killed -> the watcher's auto-heal recovered
it in 20 seconds; drift was injected into the deployed `explorer.py` -> `--ensure` restored the
md5 from the canonical copy + restart + healthz ok; three copies (`.zscripts/`, canonical, live
install) verified identical. The consumer pattern is unaffected: a consumer's explorer runs
DIRECTLY from its install directory — file freshness follows the skill version, guarded by the
watcher's verify-only integrity check and the M0 version sanity alarm.
