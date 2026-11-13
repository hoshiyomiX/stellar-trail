# NOT-ARMED — the persistence layer is NOT active yet

This file ships with every stellar-trail install and deletes itself the moment
arming succeeds — **seeing it means: the skill files landed, but the persistence
layer (boot hook, canonical snapshot, watcher, explorer, memory scaffold) was
never armed.**

Why you may be seeing this: the install command only copies files. On harnesses
that gate skill loading by task-match (observed on z.ai: three consecutive
skill-work turns, zero skill-body loads — field evidence 2026-11-13), the
protocol body whose cold boot would arm persistence automatically may never
load in a real session. Until armed, one container recycle can silently erase
the whole installation — `skills/` is not in the platform's preserve list.

## Arm now (10 seconds)

```bash
bash skills/stellar-trail/scripts/bootstrap-sandbox.sh --ensure
```

Idempotent, offline, no force flags. On success this file deletes itself —
its absence is the armed signal (for pre-v5.7.7 installs it never existed).

## Check armed status at any time

```bash
test -f .zscripts/dev.sh && echo ARMED || echo NOT-ARMED
bash skills/stellar-trail/scripts/bootstrap-sandbox.sh --status
```

## The combined install+arm one-liner (recommended for fresh installs)

```bash
npx skills add hoshiyomiX/stellar-trail --skill stellar-trail -a openclaw -y && bash skills/stellar-trail/scripts/bootstrap-sandbox.sh --ensure
```
