# Task Files Explorer (Built-in Asset) — Deploy & Operations Reference

> A stellar-trail built-in asset since v3.1.0 (server v1.4; UI v2.2 since v3.3.0, UI v3.0
> since v3.5.4, UI v4.0 Dashboard since v3.6.6, English UI since v3.6.7, UI v5.0 Expressive
> since v3.6.8, UI v5.1 guard duo since v3.6.9, UI v3.0 formatting restored since
> v3.6.10, UI v3.1 English + release-health tiles since v3.6.11, UI v3.2 refined
> tiles/typography/icons since v3.6.12, UI v3.3 static-copy mode since v3.6.13,
> UI v3.4 manual live-recovery since 4.0.0;
> launcher v1.5).
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
| `explorer.py` | Python stdlib server v1.4 (ThreadingHTTPServer); /api/files walk depth-4, task parsing from worklog.md, skill guardian block (kept for v1.3 compat), **`guard` block (v1.4)** — live vs canonical version + in-sync flag, watcher liveness/pid, THIS process's code freshness (content stamp vs the deployed source), Next.js stand-down flag — and **`resets` block (v1.4)** — session resets + restore counters parsed from `.zscripts/boot.log` + `.zscripts/explorer.log` (dev.sh boots, SKILL RESTORE events, repo-snap auto-applies, explorer restarts, freshness/heal restarts, sync-fresh refreshes; count + last timestamp each; missing logs = empty counters); **GET /api/tasks — the Session Task list** parsed from `memory/SESSION-STATE.md` (Active + Sealed tables + the checkpoint line; missing file = empty structure, never an error); serves files with a realpath guard (only inside ROOTS) plus **`?dl=1`** for attachment mode (forced download); PIDFILE + **CODE STAMP** (`.zscripts/explorer.code-stamp`, md5 of the server's own source written at startup — the content-exact freshness anchor explorer.sh v1.5 compares); env `STELLAR_PROJECT` (default /home/z/my-project), port via argv[1] (default 3000) |
| `explorer.sh` | Launcher --ensure/--status/--stop; Next.js guard (package.json wins); double-fork orphan; env `STELLAR_PROJECT`; **v1.3 (v3.6.2): AUTO-DEPLOY** — when run from the install tree (`skills/stellar-trail/assets/explorer/`), the launcher detects the layout, copies itself to `<root>/.zscripts/`, then re-execs from there (PID/log always in .zscripts/, the install tree stays drift-free; anti-loop via env guard + layout detection); **v1.4 (v3.6.8): PROCESS-FRESHNESS RESTART** — `--ensure` also restarts a live server that predates the current deployed code, so new endpoints go live on upgrade instead of 404-ing until a manual restart; **v1.5 (v3.6.9): FRESHNESS DONE RIGHT** — the check is CONTENT-EXACT (md5 of the deployed explorer.py vs the code stamp the server wrote at startup; a missing stamp = a pre-v1.5 server = one migration restart), the restart path is hardened (`kill_wait`: TERM → poll ≤5 s → KILL), `--stop` carries a pid-identity guard (a recycled pid in the pidfile is never killed — `/proc/<pid>/cmdline` must match), a live server with a missing pidfile is healed by restart, and the start health verdict retries once at +2 s; `--status` reports the stamp-based process/code freshness; activated deploy-time by bootstrap-sandbox.sh (§7) |
| `explorer-ui/index.html` | **Expressive UI v3.4** (since 4.0.0: manual live-recovery — 1000 ms after static detection the page probes the origin's /api/files once; an explorer.py JSON answer upgrades the banner with an "Open live view" button that replaces the top window with the absolute live root — never auto-navigates, frame fallback when sandboxed, a later failed probe removes the button; while static a JSON answer never renders data in-place; since v3.6.13: static-copy graceful mode — opened without its server the UI shows an informational "static copy — live data unavailable" banner instead of an error and suppresses the retry-snackbar loop; since v3.6.12: tile row = Skill Version hero + Boot Resets / Skill Restores / Snapshot Restores counters with timestamps — Explorer Restarts tile removed, "Archive Applies" renamed "Snapshot Restores"; tile icons = official Google Material Icons (classic filled 24 px) embedded verbatim; task cards enlarged 310–400 px on the compact type scale 14/12/11 px; compact 40 px search bar; fully English since v3.6.11 — labels, aria strings, toasts, comments, `en-US` locales; fed by the /api/files `guard`/`resets` blocks; built on the v3.6.3-era formatting restored in v3.6.10 — sidebar navigation, stat cards, task rail; the v5.x line — v5.1 guard duo since v3.6.9, v5.0 bento since v3.6.8, v4.0 Dashboard since v3.6.6 — stays retired, preserved in git history); core features: 200 ms debounced live search, dynamic category filter chips, segmented sort (name/size/time), per-card copy-path + toast, preview dialog with `?dl=1`, chunked render; details in sections 5d–5j |
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
   memory scaffold + explorer): `bash scripts/bootstrap-sandbox.sh --ensure` (the
   explorer module auto-enables when its payload ships in the tree).

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

## 5e. UI v5.0 Features — MD3 Expressive Bento (explorer-ui/index.html, since v3.6.8)

A full visual refactor to Material Design 3 **Expressive**: the dashboard becomes a bento of
expressive tiles, a multi-column card grid, and a Session Task column. Client-side features
carry over from v4.0 (search debounce, filter, sort, copy-path, preview, chunked render,
adaptive theme, 10 s polling, focus refresh); the API contract grows ONE endpoint
(`/api/tasks` — explorer.py v1.3).

- **Bento layout**: a stat-TILE row (Files, Aggregate size, Active tasks, Sealed tasks,
  Guardian) with per-tile tonal color pairs and 34 px display numerals · the file inventory as
  a responsive multi-column CARD grid (badge, task chip, name, breadcrumb, size · time;
  copy-path + preview buttons revealed on hover/focus) · a sticky **Session Task column** fed
  by `/api/tasks`: checkpoint line, ACTIVE task cards (ID, status chip, phase, description,
  updated), SEALED history rows (outcome, date, artifact — one-click preview when the
  artifact resolves to a served file).
- **Expressive styling**: 20–28 dp corner radii with radius-morph tile hover, springy
  hover/press motion (overshoot easing), staggered card entrances (capped), a bold display
  type scale, and a `prefers-reduced-motion` opt-out.
- **Adaptive theme kept**: follows `prefers-color-scheme` until a manual choice persists in
  localStorage; both tonal palettes (light + dark) are MD3 Expressive tonal pairs.
- **Data loop**: `/api/files` + `/api/tasks` fetched in parallel; re-render is hashed on the
  data-bearing fields only (the volatile `generated`/`server` fields no longer force a
  re-render every poll — a v4.0 inefficiency fixed here).

## 5f. UI v5.1 Features — Guard Duo + Content-Summary Task List (v3.6.9 — RETIRED from the deployed asset in v3.6.10; kept here as the historical record of the v5.x line)

The page opens with a HERO of two large tonal tiles instead of the v5.0 stat-tile row, the
Session Task list moves from a sticky side column to a full-width section with content
summaries, and the file inventory gains a compact stats header. Everything else carries
over from v5.0 (search debounce, filter chips, sort, copy-path, preview dialog, chunked
render, adaptive theme, 10 s polling, focus refresh, reduced-motion opt-out).

- **Guard Status tile (blue tonal)**: the live stellar-trail version as the display value,
  a watcher liveness dot (alive/down · verify-only), a canonical in-sync line (drift names
  both versions), and the explorer's own CODE FRESHNESS — `code current` vs
  `restart pending — bootstrap/update --ensure` (from the v1.4 content stamp). A Next.js
  stand-down notice appears when `package.json` owns the port. A missing `guard` block
  (server predates v1.4) renders a one-line hint instead of wrong data.
- **Session Reset & Restore tile (teal tonal)**: the LAST session reset (the most recent
  dev.sh boot) as a relative display value, with counters beneath — dev.sh boots (session
  resets), skill restores from the canonical snapshot, explorer restarts · archive
  refreshes — and the absolute last-reset timestamp as a footer. All parsed by explorer.py
  v1.4 from `.zscripts/boot.log` + `.zscripts/explorer.log` (the `resets` block).
- **Session Task list, full width**: active tasks render as a responsive card grid
  (min 310 px) with CONTENT SUMMARIES — the description clamped to 4 lines with a
  show more / show less toggle (`aria-expanded` wired), phase, status pill, updated date.
  Sealed rows keep their one-line outcome + artifact preview button. This also fixes a
  v5.0 regression: those preview buttons had no click delegation and did nothing.
- **Files section**: a compact header (Files · N files · size · roots) replaces the four
  retired stat tiles; the card grid widens (min 240 px) now that the sticky task column
  is gone; the checkpoint banner stays on the task section.
- **Data loop**: the hash adds the `guard` + `resets` blocks — a version bump, a watcher
  death, a drift, or a new boot/restart re-renders the hero within one poll.

## 5g. UI v3.1 Features — English UI + Release-Health Tiles + Larger Task Cards (since v3.6.11)

The v3.0-formatting layout restored in v3.6.10 stays; this release translates and
re-targets it. Three changes, all in `explorer-ui/index.html` (server and launcher
untouched):

- **English everywhere**: every user-facing label, aria string, title, toast, empty
  state, and code comment is translated (lang="en"; en-US locales for dates, relative
  times, durations, and the clock). The LARGE-layout CSS selector
  (`section[aria-label="Filter and search"]`) is updated in step with the translated
  aria-label so the list-detail grid assignment keeps working.
- **Stat tiles rebuilt around release health** (all five old inventory tiles removed):
  a **Skill Version** hero tile — live version as the display value, canonical
  in-sync/drift verdict + watcher liveness dot as the sub-line — plus four reset
  counters, each showing count and last-occurrence timestamp: **Boot Resets**, **Skill
  Restores**, **Explorer Restarts**, **Archive Applies**. Data source: the `/api/files`
  `guard` and `resets` blocks explorer.py v1.4 already serves; the reads are null-safe
  (missing blocks render zero/never, an old server cannot break the page).
- **Task cards enlarged**: rail cards grow from 225–280 px to 310–400 px wide, titles
  from 14 px/2-line to 16 px/3-line (4-line on the ≥1240 px sticky sidebar), body text
  12→14 px, padding 14×16→18×22 px, check indicator 16→18 px; the mobile rail minimum
  rises to 260 px.

## 5h. UI v3.2 Refinements — Tile Row, Type Scale, Search, Official Icons (since v3.6.12)

Five user-directed adjustments on the v3.1 UI, all in `explorer-ui/index.html`
(server and launcher untouched):

- **Explorer Restarts tile removed** — the row is now Skill Version + Boot Resets,
  Skill Restores, Snapshot Restores; the `resets.explorer` block stays served by
  explorer.py v1.4, the UI simply no longer renders a tile for it.
- **"Archive Applies" → "Snapshot Restores"** — label-only rename matching the
  snapshot-repo feature the counter tallies (`resets.boot.archive_applies` unchanged).
- **Task-card type scale restored to compact** — the 310–400 px enlarged footprint
  stays, typography returns to 14 px titles / 12 px body / 11 px task id / 16 px check
  (the v3.6.11 16/14/12/18 px scale read too large on screen).
- **Search bar compacted** — 40 px pill (was 48), 12 px input (was 14), 18 px leading
  icon (was 20), 32 px clear button scoped to fit; the compact-width iOS anti-zoom
  16 px rule stays.
- **Tile icons = official Google Material Icons** (classic filled 24 px): new_releases
  (Skill Version), restart_alt (Boot Resets), restore (Skill Restores), backup
  (Snapshot Restores) — fetched verbatim from google/material-design-icons (Apache 2.0)
  and embedded as inline SVG symbols with a provenance comment; the upstream
  `fill="none"` bounding-box filler paths are dropped on embed so the CSS
  `fill:currentColor` cannot paint them.

## 5i. UI v3.3 — Static-Copy Mode (since v3.6.13)

The UI detects when it is opened WITHOUT its server and degrades gracefully
instead of freezing at a misleading error (platform file preview of index.html,
a downloaded copy, any static host):

- **Detection at load** — `file:` protocol, or a pathname other than `/` and
  `/index.html` (the only paths explorer.py serves the UI at, same origin),
  marks the page static before the first fetch.
- **Promotion on first failure** — an origin that answers `/api/files` with a
  non-JSON body (a JSON `SyntaxError` — e.g. a platform 404/500 HTML page) is
  not explorer.py: the page is promoted to static mode. A live server that
  dies after a successful load throws a network error instead and keeps the
  original error card — the two failure modes stay distinguishable.
- **Static banner** — an informational state (primary-container tone, official
  `info` glyph): "Static copy — live data unavailable", why the feed is
  unreachable, and where the live explorer is served (the preview URL root
  while a session runs). No retry button — the 10 s auto-refresh loop keeps
  checking silently.
- **Snackbar suppressed** — the periodic "Connection to explorer.py lost —
  retrying…" toast no longer fires in static mode (it was pure noise in a
  file preview); a genuine outage at the live path keeps it.

## 5j. UI v3.4 — Manual Live-Recovery Button (since 4.0.0)

Built after the user confirmed the platform file preview no longer interferes
(cause unknown, platform-side) — the defensive path ships anyway, as a MANUAL
control (never auto-navigation, per explicit user choice):

- **Late probe** — 1000 ms (`RECOVER_MS`) after static-copy detection the page
  fetches `/api/files` on the same origin once; the existing 10 s loop keeps
  probing afterwards. The `file:` protocol never probes (no origin to recover
  to — a downloaded copy keeps the informational banner only).
- **Probe-gated button** — an explorer.py-shaped JSON answer (`d.server.pid`)
  upgrades the banner to "Static copy — live explorer reachable" with an
  **Open live view** button (official `open_in_new` glyph, classic filled
  24 px, embedded verbatim from google/material-design-icons, Apache 2.0).
  The probe gate means the button is never offered when the origin answers
  404/500 HTML — no dead button, no bounce into a platform error page.
- **Click = cover the top window** — `top.location.replace(<absolute live
  root>)` recovers the whole window (the platform file preview at top level);
  cross-origin or sandboxed frames fall back to replacing the frame itself.
  `replace()` keeps the browser Back button out of the recovery loop.
- **Never dead** — if a later probe fails after the button appeared, the
  banner reverts to the informational state and the button is removed.
- **Behavior change while static** — a JSON answer no longer renders live
  data in-place (v3.3 did); the banner is the interface, the button is the
  recovery. The live path ("/" and "/index.html" served by explorer.py) is
  untouched.

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
check and the M0 version sanity alarm (since v3.6.7; the era mechanism was retired with the
repair chain).

**v1.4 addition — process freshness (v3.6.8):** file freshness alone was not enough. On the
first-hop upgrade path bootstrap syncs the `.zscripts` files BEFORE `--ensure` ever runs, so
`sync_fresh` sees no drift while the RUNNING PROCESS still serves the previous release's code
(observed live: the explorer survived the v3.6.7 first-hop untouched, pid unchanged). Since
v1.4, `--ensure` also restarts a live server whose deployed `explorer.py` is newer than the
pidfile written at server start — the process, not just the files, now follows the release.

**v1.5 addition — freshness done right + deploy-time activation (v3.6.9):** the v1.4 check
was an mtime heuristic (`explorer.py` newer than the pidfile) — ambiguous at same-second
writes and dependent on `cp -p` semantics through the deploy chain. v1.5 is content-exact:
the server writes the md5 of its own source to `.zscripts/explorer.code-stamp` at startup,
and `--ensure` restarts any live server whose stamp no longer matches the deployed file
(no stamp = pre-v1.5 server = one migration restart). The restart is hardened
(`kill_wait`: TERM → poll ≤ 5 s → KILL — a TERM-ignoring process can no longer answer
healthz on its dying socket and silently skip the restart), `--stop` guards against pid
recycling (`/proc/<pid>/cmdline` must match), and a live server with a missing pidfile is
healed by restart. THE TRIGGER MAP is now complete — dev.sh covers BOOT, the watcher covers
DEATH (health-fail only), and bootstrap-sandbox.sh covers DEPLOY-TIME: it runs
`explorer.sh --ensure` at the end of every invocation (output to boot.log; failure never
fails bootstrap), so update-skill's step [4/4] — which deploys the files via bootstrap — now
activates them in the same run. The upgrade-path gap (a healthy old server surviving a
first-hop untouched) is closed on every path that can deploy explorer assets.
