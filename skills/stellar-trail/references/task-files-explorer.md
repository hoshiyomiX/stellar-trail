# Task Files Explorer (Built-in Asset) — Deploy & Operations Reference

> A stellar-trail built-in asset: server v1.11 · launcher v1.5 · UI v5.0.2 (miuix-vue). The explorer is an
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
        -> explorer.py             (Python stdlib server; UI = explorer-ui/index.html, adaptive miuix-vue v5.0)
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
| `explorer.py` | Python stdlib server v1.11 (ThreadingHTTPServer): `/api/files` walk (depth-4, task parsing from the merged worklog ledger) with the `guard` block (live vs canonical version + in-sync flag, watcher liveness/pid, THIS process's code freshness via its content stamp, Next.js stand-down flag) and `resets` block (boot/skill/snapshot/explorer counters + last timestamps parsed from `.zscripts/boot.log` + `.zscripts/explorer.log`; missing logs = empty counters, never an error); `/api/tasks` — the Session Task list parsed from `memory/SESSION-STATE.md`; file serving with a realpath guard (only inside ROOTS) + the **v1.10 platform-preview-kill serving contract (Task 67, owner order "popup preview platform mati permanent")**: `/file/` responses default to `Content-Disposition: attachment` (a direct URL hit downloads — the browser inline viewer and every foreign preview popup die at the source), `?inline=1` is the sole inline path (reserved for the preview modal's own img/pdf srcs), `?dl=1` keeps its explicit-download meaning (dl wins when both) — the modal's text branches read via `fetch()` which never sees Content-Disposition, so the task file manager's own preview is fully intact; html/svg/pdf as attachments cannot execute as standalone documents via URL; PIDFILE + CODE STAMP; env `STELLAR_PROJECT` (default /home/z/my-project), port via argv[1] (default 3000). **v1.5 scalability contract:** ONE cached inventory shared by `/api/files` + `/api/list` (single-builder lock, 3 s TTL); `parse_tasks` uses a token index (measured 132 ms → 24 ms at 22k files); `/api/files` caps per-root arrays at `?max=` (default 1000; `?max=0` = slim poll mode + `files_total`/`files_truncated` + `stats.type_counts`); `/api/list` — server-side filter (q/type/task) + sort (mtime/name/size × asc/desc) + location + pagination (`page`, `per_page` ≤ 500); `/healthz` and `/file/` never touch the inventory (O(1)). **v1.6 startup-freeze contract:** `content_sig` = md5 over key|mtime|size|type|task per file + the task digest — changes ONLY when the served data changes; CACHE_TTL 12 s; skill/guard/resets folded into the cached build; task titles carry 600 chars; `ExplorerServer` listens with backlog 64 (socketserver's default 5 dropped SYNs under a 20-request burst). **v1.7 scan-exclusion contract:** `ROOT_EXCLUDES` prunes named TOP-LEVEL directories per root — the `download`-root `stellar-trail` entry (the skill's own canonical copy until v5.7.4, ordered hidden by the owner 2026-10-25; the canonical itself relocated to `.zscripts/stellar-trail-canonical/` at v5.7.4, and the entry stays as a legacy-resurrection guard) is never walked, listed, or task-mapped; direct `/file/download/stellar-trail/…` links still serve it (`safe_path` never consults the exclusion list); the prune is scoped to the root's own children (deeper same-named directories and prefix-similar names untouched). **v1.9 task-history source contract (Task 63, owner order #2):** `parse_tasks` reads worklog-archive.md + worklog.md MERGED (archive first, live worklog last — the later section wins on Task-ID overlap); the worklog family is the authoritative append-only ledger (D11) and the ONLY source with per-task section bodies for the rail's related-files mapping — memory/SESSION-STATE.md stays the /api/tasks lens only (volatile snapshot, no file mapping); rotation's last-3 window had starved the 14-slot rail to 3 cards; the merge restores depth (54 unique Task IDs from 88 sections, ~21 ms, cached per the 12 s TTL). **v1.11 canonical-relocation contract (Task 77, v5.7.4):** the `guard` block reads the canonical version at `.zscripts/stellar-trail-canonical/assets/integrity.version` (the pre-v5.7.4 `download/stellar-trail/` read retired with the relocation) |
| `explorer.sh` | Launcher v1.5 — `--ensure`/`--status`/`--stop`; Next.js guard (package.json wins); double-fork orphan; AUTO-DEPLOY from the install tree (a launcher run at `skills/stellar-trail/assets/explorer/` copies itself + server + UI into `<root>/.zscripts/` and re-execs there — the install tree stays drift-free); sync-fresh vs the canonical copy (md5 drift → re-copy; `explorer.py` changed → server restart); PROCESS-FRESHNESS RESTART (md5 of the deployed explorer.py vs the code stamp the server wrote at startup — a live server predating the deployed code restarts on `--ensure`); hardened stop (`kill_wait`: TERM → poll ≤5 s → KILL; pid-identity guard via `/proc/<pid>/cmdline` — a recycled pid is never killed); a live server with a missing pidfile is healed by restart; activated deploy-time by bootstrap-sandbox.sh |
| `explorer-ui/index.html` | UI v5.0.2 — **miuix-vue (HyperOS)** single-file build (Vue 3 + the real miuix-vue component layer, built by Vite at release time; no CDN, no web font), fully English, adaptive dark/light theme (color roles verbatim from compose-miuix-ui/miuix `Colors.kt`; theme key `miuix-theme`, legacy `md3-theme` honored). **Structure (Task 62, owner clarification "'below" means the contents of the top bar (clock/version chip/Rescan/Theme)" + order "Revert back dashboard card tiles that you had removed", correcting the over-broad Task-61 retirement):** the dashboard card tiles are REVERTED — the stat tiles + the Task History rail are BACK (Task 63 owner order #1: the tiles section is RENAMED 'Release Health' → 'Dashboard' — title + aria-label + section icon trophy→GridView, the HyperOS dashboard-grid metaphor; the rail's click-to-filter reloads the list immediately — the v4.4 refresh the Task-53 port had dropped) and the APPBAR is identity-only — no version chip, no clock, no Rescan, no theme toggle (the theme follows the system; recovery = the steady 10 s poll + the error card's Retry); the search/filter/sort/view toolbar, footer, FAB and listhead rootline stay retired (Task 61, stands — not card tiles); page deepened for card-vs-page separation — dark #17171A / light #EFEFEF under the untouched #2c2c2c/#FFFFFF cards. **Icons:** the official miuix-vue set, `miuix-vue/icons` extended pack regular weight, imported at build time and embedded as the sprite's glyph data (Task 57 owner order 'full use miuix' — the Google Material set fully replaced; Task 59 — every symbol path carries the official MiuixIcon flip transform `matrix(1 0 0 -1 0 vh)` (glyph data authored font-style y-up — an unflipped render is upside-down) and the logo is the miuix FolderFill glyph — 33/33 symbols miuix, zero hand-drawn; Task 63 order #3 — official MiuixIcon ratios: 24 px glyphs in the 40 px tiles, 22 px in the 38 px preview micon, 32 px in the 56 px empty-state, chevron 15 px). **Features:** preview dialog with a 200 KB input cap + truncation notice on md/json/text (Task 58 hang fix); per-card copy-path + preview with `?dl=1` download anchors (markdown/JSON rendered; img/pdf srcs carry `?inline=1` — the modal-only inline path under the v1.10 attachment default); server-side pagination (paged `/api/list`, 100/page with a pager — the client never fetches the full inventory; q/type/sort stay server-only, the task parameter re-exposed via the rail's click-to-filter); 10 s slim polling (`/api/files?max=0`, ~2 KB); **v4.1:** the poll tracks `content_sig` and re-renders ONLY on a real change — silently (`.filegrid.noanim`); `visibilitychange` no longer fires an unconditional load; the v4.1 scrollable rail (retired at Task 61) is RESTORED at Task 62. **Static-copy graceful mode + the Task-67 AUTO-BREAKOUT** (1 s after static detection the page probes the api once; an explorer.py-shaped JSON answer sets staticLive and the page REPLACES the top-level window with the live root "`/`" — the platform file-preview chrome that wrapped the static copy dies, once per page (loop-guarded); when top-level navigation is sandbox-blocked the banner + **Open live view** button remain as the fallback; a later failed probe downgrades the banner; while static a JSON answer never renders data in-place — supersedes the v4.2 manual-only recovery note per the Task-67 owner order). **v4.2 boot render diet:** the FIRST load renders silently (the entrance burst fires only on explicit user actions); cards declare content-visibility:auto + contain-intrinsic-size so offscreen cards skip layout + paint. **v4.3/v4.3.1 fetch resilience:** every fetch carries an engine-independent deadline (AbortController when available + a Promise.race backstop at ms+250; an 8 s boot watchdog guarantees the honest error state; engines that cannot abort stop auto-polling after 3 consecutive failures — each unabortable poll holds a socket and the ~6-slot per-origin pool must survive for the error card's Retry); the poll loop is a self-scheduling in-flight-guarded loop (polls never stack); a suspended sandbox surfaces as an honest error-card state instead of a silent hang (stacked no-timeout polls exhausted the ~6-connection per-origin pool — the popup-freeze root cause, reproduced in-container at v5.4.5); previews time out with an explanatory message; the error card's Retry forces a probe + list reload (the appbar Rescan left with the Task-62 strip — Retry is the manual path). **v4.4 (v5.4.9, owner order — the reconnect machinery is REMOVED):** no failure backoff, no reconnecting chip, no visibility/focus/online wake probes — one steady 10 s loop retries win or lose, so recovery is simply the next successful poll; on no-abort engines the 3-failure breaker pauses auto-polling and Retry is the recovery path; the app bar is a single identity row at ≤640 px (logo + truncating title; Task 65: the row's padding-top:8px pairs with the miuix inline subtitle paddingBottom so the logo sits at 8/8 in the 50 px row — was flush at y=0 — and the logo→title gap is 14 px = the desktop fence). **Task 66 (render-optimization order):** the per-card action row (copy/download) is right-aligned at the card's bottom edge — a card-CENTER click must reach the preview (the old row-start placement put the @click.stop download anchor exactly on the center band of stretched grid rows and the click never opened the modal; probe A/B: never → 70 ms desktop / 291 ms mobile), the corner type badge floats inside the card body so long filenames wrap clear of it, and the dead pre-Task-53 `.topappbar` frosted-bar CSS is removed (it never applied — the live bar is `m-top-app-bar`, solid). **Task 69 (sandbox-popup-kill order, ref #67 lineage):** the miuix snackbar platform is GONE — MiuixSnackbarHost + snack.js + all six call sites removed, the dead onScan() toast path pruned, so the UI renders zero popups beyond the task file manager's own preview modal; copy + connection-loss feedback speak through an sr-only aria-live announcer (`.sr-live` + `ui.announce`, clear-then-set), the error card keeps the dead-first-load state with its Retry; the no-popup invariant is pinned by `scripts/task69-verify.sh` (zero popup APIs in src+dist, zero snackbar DOM live, Task-66 center-click + Task-67 attachment contracts intact). **Build markers:** the Dashboard 'Skill Version' tile reads the live skill version once explorer.py answers (the retired app-bar chip's role) and the error card carries the build — a stale cached copy is identifiable at a glance |
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
1. Copy explorer.py, explorer.sh, explorer-ui/ as above — plus `scripts/watcher.sh` to `<project>/.zscripts/` (the daemon referenced by dev.sh §3; installed automatically by bootstrap core).
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
4. **The 30-second watchdog** — auto-heal when the explorer dies (verified: kill -9 → back alive in ≤30 s).
5. **The protocol's M0** — every new session ensures the watcher is alive.
6. **Anti-rollback layers** — when the environment resets: see `references/environment-resilience.md`
   + `scripts/snapshot-repo.sh` (one problem, one family of solutions).

## 5a. Recycle vs Rollback Symptoms — Tell Them Apart Before Reasoning

Two environment failures that are easy to confuse:

- **Preview explorer dead** (the :3000 process is gone, "index.html killed") = a **container recycle** signature — container-living processes (explorer, watcher) die with the container; THIS IS NOT a skill bug; the built-in asset stays intact inside the installation. Remedy: opt-in redeploy — `bash .zscripts/explorer.sh --ensure` (dev.sh/watcher revive it at the next boot when the /start.sh hook is active).
- **Installed asset files missing / version regressed** (built-in assets gone, an old banner, new release components absent) = a **restore-archive rollback** signature — the installation was overwritten by a stale archive. Remedy: re-run the single install command (`npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw -y`) or `bash skills/stellar-trail/scripts/update-skill.sh --force`; the M0 version sanity alarm and the watcher's integrity check report the degradation (environment-resilience.md §3c/§4).

Compact rule: **processes dead → recycle (redeploy); files changed/missing → rollback (re-install)**.

## 6. Control Commands

```
bash .zscripts/explorer.sh --status   # health + log
bash .zscripts/explorer.sh --stop     # stop the explorer
bash .zscripts/explorer.sh --ensure   # start when not running (idempotent)
```

**Ethics & limits:** the explorer only serves the working directories (ROOTS download/ + archive/), read-only, loopback-bound. It never exposes files outside the project, and its deployment is always announced to the user (never a silent initiative) — consistent with the consent principle (SKILL §5) and the infrastructure-intervention-only-on-request principle (environment-resilience §5).

## 7. Deployment Freshness — sync-fresh + process freshness

The problem: when the explorer is deployed as a COPY (the maintainer pattern: `.zscripts/explorer.py` + `.zscripts/explorer-ui/index.html` outside the skill installation), checking only ALIVENESS (`healthz`) misses FRESHNESS — a stale copy (an old `repo.tar` restore, or a new UI release never copied) keeps running with nobody noticing: *alive-but-stale*.

The mechanism (in `explorer.sh`):

- `--ensure` calls `sync_fresh()` BEFORE the aliveness check: `explorer.py` and `explorer-ui/index.html` are compared (`cmp`) against the canonical copy (`$PROJECT/.zscripts/stellar-trail-canonical/assets/explorer/`); drift → re-copy + a `sync-fresh` log line; `explorer.py` changed → server restart (the UI is read per-request — a copy suffices).
- `--status` shows a `fresh : server=ok ui=ok (vs canonical)` line; alive-but-stale is repaired automatically, not just dead-then-started.
- File freshness alone was not enough: on the first-hop upgrade path bootstrap syncs the `.zscripts` files BEFORE `--ensure` ever runs, so `sync_fresh` sees no drift while the RUNNING PROCESS still serves the previous release's code. The server therefore writes the md5 of its own source to `.zscripts/explorer.code-stamp` at startup, and `--ensure` restarts any live server whose stamp no longer matches the deployed file — the process, not just the files, follows the release.
- THE TRIGGER MAP is complete — dev.sh covers BOOT, the watcher covers DEATH (health-fail only), and bootstrap-sandbox.sh covers DEPLOY-TIME: it runs `explorer.sh --ensure` at the end of every invocation (failure never fails bootstrap), so update-skill's step [4/4] — which deploys the files via bootstrap — activates them in the same run.

Field evidence (controlled drill): kill -9 → the watcher's auto-heal recovered it in 20 seconds; drift injected into the deployed `explorer.py` → `--ensure` restored the md5 from the canonical copy + restart + healthz ok; three copies (`.zscripts/`, canonical, live install) verified identical. The consumer pattern is unaffected: a consumer's explorer runs DIRECTLY from its install directory — file freshness follows the skill version, guarded by the watcher's verify-only integrity check and the M0 version sanity alarm.
