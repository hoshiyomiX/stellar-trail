# Task Files Explorer (Built-in Asset) — Deploy & Operations Reference

> A stellar-trail built-in asset since v3.1.0 (server v1.2; UI v2.2 since v3.3.0, UI v3.0
> since v3.5.4, UI v4.0 Dashboard since v3.6.6, English UI since v3.6.7).
> The explorer is an **optional & opt-in tool** — not part of the protocol mandate.
> It functionally replaces the platform's "All files in task" popup with a custom page
> on the preview URL.

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
| `explorer.py` | Python stdlib server v1.2 (ThreadingHTTPServer); /api/files walk depth-4, task parsing from worklog.md, **skill guardian block** (stellar-trail version + watcher status — the retired heal marker was dropped in v3.6.7), serves files with a realpath guard (only inside ROOTS) plus **`?dl=1`** for attachment mode (forced download); PIDFILE; env `STELLAR_PROJECT` (default /home/z/my-project), port via argv[1] (default 3000) |
| `explorer.sh` | Launcher --ensure/--status/--stop; Next.js guard (package.json wins); double-fork orphan; env `STELLAR_PROJECT`; **v1.3 (v3.6.2): AUTO-DEPLOY** — when run from the install tree (`skills/stellar-trail/assets/explorer/`), the launcher detects the layout, copies itself to `<root>/.zscripts/`, then re-execs from there (PID/log always in .zscripts/, the install tree stays drift-free; anti-loop via env guard + layout detection) |
| `explorer-ui/index.html` | **Dashboard UI v4.0** (since v3.6.6: category sidebar + stat cards + file table; **adaptive** dark/light theme — follows `prefers-color-scheme` + persistent toggle; zero-dependency; `lang="en"` since v3.6.7; size budget <45 KB from the 69 KB v3.0) — core features: 200 ms debounced live search, dynamic category filter, per-row copy-path + toast; table-header sort (name/size/time) and chunked render kept simple; the Guardian card is integrated into the stat card row; details in section 5d |
| `dev.sh.template` | Legacy v2 boot-hook template: tidy download/ -> archive/, fullstack guard, ensure watcher + explorer, periodic repo.tar refresh. Superseded by the bootstrap-generated dev.sh (which adds the cache-replay skill restore with the version gate); kept as reference — see the template header note |

## 3. Deploy Steps

### Case A — fresh container (no .zscripts/dev.sh yet)

> **Easiest path since v1.3 (v3.6.2): AUTO-DEPLOY.** Run directly from the install
> tree — `bash skills/stellar-trail/assets/explorer/explorer.sh --ensure` — the launcher
> detects the install layout, copies itself + explorer.py + the UI to
> `<project>/.zscripts/`, then re-execs from there. No manual steps, no writes inside
> the install tree. (Before v1.3: a FileNotFoundError crash — PROJECT fell to
> `.../assets`, the PIDFILE at `assets/.zscripts/` was never created; consumer report
> 2026-09-25.) The manual steps below remain valid.

1. Copy the assets to the active location (default project root /home/z/my-project):
   `cp assets/explorer/explorer.py assets/explorer/explorer.sh <project>/.zscripts/`
   `mkdir -p <project>/.zscripts/explorer-ui && cp assets/explorer/explorer-ui/index.html <project>/.zscripts/explorer-ui/`
   `cp assets/explorer/dev.sh.template <project>/.zscripts/dev.sh && chmod +x <project>/.zscripts/dev.sh`
   `cp scripts/watcher.sh <project>/.zscripts/`   # watchdog v2.0 — referenced by dev.sh §3; installed automatically by bootstrap core since v3.6.3
2. Run once: `bash <project>/.zscripts/explorer.sh --ensure`
3. Every subsequent boot, /start.sh runs dev.sh -> explorer + watcher come alive automatically.

   One-command alternative for the whole persistence layer (skill + worklog +
   memory scaffold + explorer): `bash scripts/bootstrap-sandbox.sh --with-explorer`.

### Case B — dev.sh already exists (do NOT overwrite it)
1. Copy explorer.py, explorer.sh, explorer-ui/ as above — plus `scripts/watcher.sh` to `<project>/.zscripts/` (the daemon referenced by dev.sh §3; shipped in the package and installed automatically by bootstrap core since v3.6.3).
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

## 5a. Recycle vs Rollback Symptoms — Tell Them Apart Before Reasoning (v3.5.7)

Two environment failures that are easy to confuse (consumer incident 2026-09-22, report §6.5 —
"index.html killed" turned out not to be a missing file):

- **Preview explorer dead** (the :3000 process is gone, "index.html killed") = a **container
  recycle** signature — processes living in the container (the explorer server, the watcher)
  die with the container; THIS IS NOT a skill bug. The built-in asset
  `assets/explorer/explorer-ui/index.html` stays intact inside the installation. Remedy:
  opt-in redeploy — `bash .zscripts/explorer.sh --ensure` (dev.sh/watcher revive it
  automatically at the next boot when the /start.sh hook is active).
- **Installed asset files missing / version regressed** (built-in assets gone, an old body
  version banner, new release components absent) = a **restore-archive rollback** signature —
  the skill installation was overwritten by a stale archive. Remedy: re-run the single install
  command (`npx skills add hoshiyomiX/stellar-trail`), or `bash
  skills/stellar-trail/scripts/update-skill.sh --force`; the M0 version sanity alarm and the
  watcher's integrity check report the degradation (see environment-resilience.md §3c/§4).

Compact rule: **processes dead → recycle (redeploy); files changed/missing → rollback
(re-install)**.

## 5b. v3.3.0 Features (server v1.1 + UI v2.2)

- **Guardian card** (5th statistic): installed stellar-trail version, a watcher alive/dead
  indicator, and (era) the last heal time — read from `_meta.json`, `watcher.pid`, and the
  `.skill-heal.last` marker (best-effort; the card hides when the skill is not installed).
  Since v3.6.7 the card shows version + watcher status + "integrity verify-only" — the heal
  marker is retired with the repair chain.
- **Per-card quick-download**: a download button appeared on hover/focus of each file card —
  using the `?dl=1` endpoint (Content-Disposition: attachment) so the browser always
  downloads instead of opening. The Download button in the preview dialog also uses `?dl=1`.
- **Copy path**: the copy button in the preview dialog copies the file's full server path
  (root + rel) to the clipboard — useful for terminal work.
- **Relative times** on cards ("just now", "5 min ago", "3 h ago" — English since v3.6.7) with
  the full timestamp as a tooltip; the preview dialog keeps full timestamps.
- **Refresh on focus**: data reloads instantly when the tab becomes active again
  (visibilitychange) — on top of the regular 10-second polling.
- **Oldest-first sort** (mtime ascending) + search now also matches task IDs
  (e.g. the query "27" finds files related to Task 27).

## 5c. UI v3.0 Features (explorer-ui/index.html, since v3.5.4)

All purely client-side — the `explorer.py` API contract did not change at all.

- **Live search** with a 200 ms debounce (name / extension / task ID).
- **Dynamic type filter**: a chip per category (Documents, Images, Data, Archive/zip, Code,
  Office, Other) with file counts; empty categories hidden automatically from the
  `/api/files` data.
- **Column sort** name / size / time — click to activate, click again to toggle
  ascending/descending with an arrow indicator (replacing the v2.2 sort dropdown).
- **Per-item copy path**: a copy button on every card/row (navigator.clipboard + an
  `execCommand` fallback) with a "Path copied" toast — the preview-dialog button remains.
- **Chunked render**: large directories render 100 items per chunk; the next chunk loads
  automatically as the button approaches the viewport (IntersectionObserver, fallback:
  a manually clicked "Load more" button).
- **Adaptive theme**: follows `prefers-color-scheme` until the user chooses manually;
  the manual choice persists in localStorage.
- **Directory breadcrumbs** on file names (folder segments collapsed) + clear
  loading/empty/error states, including a "Retry" button.

## 5d. UI v4.0 Features — Dashboard (explorer-ui/index.html, since v3.6.6, Task 67)

A full concept + layout refactor (user mandate Task 67 #2): from the v3.0 MD3 card grid
(69 KB) to a compact **Dashboard** with a **file size budget <45 KB** and core features
only. Everything stays purely client-side — the `explorer.py` API contract did not change
at all; zero-dependency and the adaptive theme remain.

- **Dashboard layout**: category sidebar (nav with per-category counts, collapsing into a
  horizontally scrolling chip row on narrow screens) · a stat card row (total files,
  aggregate size, active category, Guardian) · the main file table (name+breadcrumb,
  category, size, time, actions columns).
- **The Guardian card** integrated into the stat card row (skill version, watcher indicator —
  best-effort, hidden when the skill is not installed; replacing the separate v2.2 card;
  since v3.6.7 it reads "integrity verify-only" instead of the retired heal time).
- **Core features kept**: 200 ms debounced live search (name / extension / task ID) · dynamic
  category filter · per-row copy-path + "Path copied" toast (clipboard API + fallback) ·
  download via the preview dialog `?dl=1` · relative times + timestamp tooltips · refresh on
  focus (visibilitychange) · loading/empty/error states + the "Retry" button.
- **Simplified**: sort = table-header click (name/size/time) with a simple direction
  indicator; chunked render = an initial 200 rows + a "Load more" button (the v3.0
  IntersectionObserver retired); per-card quick-download retired (download remains in the
  preview dialog).
- **Double size win**: visual (a calmer viewport — the table hierarchy replaces the dense
  card grid) and file size (<45 KB via the complexity trims above).

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

## 7. Deployment Freshness — sync-fresh v1.2 (since v3.5.7)

The problem: when the explorer is deployed as a COPY (the maintainer pattern:
`.zscripts/explorer.py` + `.zscripts/explorer-ui/index.html` outside the skill installation),
the old auto-heal only checked ALIVENESS (`healthz`) — not FRESHNESS. A stale copy (e.g. from
an old `repo.tar` restore, or a new UI release that was never copied) kept running with
nobody noticing: *alive-but-stale*.

The v1.2 mechanism (in `explorer.sh`, also applies to the portable variant — a no-op when
the canonical path does not exist in that environment):

- `--ensure` now calls `sync_fresh()` BEFORE the aliveness check: `explorer.py` and
  `explorer-ui/index.html` are compared (`cmp`) against the canonical copy
  (`$PROJECT/download/stellar-trail/assets/explorer/`); drift -> re-copy + a `sync-fresh`
  log line; `explorer.py` changed -> server restart (the UI is read per-request — a copy
  suffices).
- `--status` shows a `fresh : server=ok ui=ok (vs canonical)` line.
- Alive-but-stale is now repaired automatically, not just dead-then-started.

**Field evidence (Task 43 drill, 2026-09-22):** (A) the process was killed -> the watcher's
auto-heal recovered it in 20 seconds; (C) drift was injected into the deployed
`explorer.py` -> `--ensure` restored the md5 from the canonical copy + restart + healthz ok;
three copies (`.zscripts/`, canonical, live install) verified identical. The consumer
pattern is unaffected: a consumer's explorer runs DIRECTLY from its install directory —
file freshness follows the skill version, guarded by the watcher's verify-only integrity
check and the M0 version sanity alarm (since v3.6.7; the era mechanism was the retired
heal-skill lock cross-check).
