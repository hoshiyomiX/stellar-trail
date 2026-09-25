# The 95% Integrity Standard — Manifest, Formula, Recall Check
**Standar Integritas 95% — Manifest, Formula, Recall Check**

This reference defines exactly what "memory utuh ~95%" means, how it is measured, and how losses are prevented. Read it when running a Recall Check, writing a handoff, or compressing under pressure.

## 1. The Memory Manifest / Manifest Memory

Seven categories. Every session boundary (summary compaction, session end, context exhaustion) must preserve them.

| # | Category | Must Survive | Priority | Why |
|---|----------|--------------|----------|-----|
| 1 | Task identity | ACTIVE/BLOCKED Task IDs, descriptions, current phase, status (sealed tasks are trajectory, not active identity — SKILL.md 4d) | **CRITICAL** | Without it the next session doesn't know what it is continuing |
| 2 | User decisions | Locked decisions + pending/unconfirmed ones | **CRITICAL** | Re-asking a settled question destroys user trust; silently reversing a decision destroys the work |
| 3 | Artifacts | Paths of deliverables, scripts, key files | **CRITICAL** | A deliverable whose path is forgotten effectively does not exist |
| 4 | User profile | Language, preferences, communication style, timezone | **CRITICAL** | The next session must feel like the same assistant, not a stranger |
| 5 | Trajectory | What was asked → what was done (compressed) | HIGH | The narrative that makes context coherent, not just recoverable |
| 6 | Pending | Next steps, blockers, open questions | HIGH | Forgetting pending items silently drops work the user expects |
| 7 | Environment | Tooling status, known issues, conventions | NORMAL | Prevents re-discovering known limitations |

## 2. The Formula / Formula

```
integrity = restorable manifest items / total manifest items
target:    >= 95%
hard rule: categories 1-4 (CRITICAL) = zero loss — losing ANY one breaches
           the standard even if the arithmetic still reads >= 95%
```

The 95% number is a design contract, not a vibe: it forces near-complete recall while explicitly budgeting ~5% for lossy narrative detail (verbose explanations, redundant examples, dead-end exploration branches that led nowhere).

## 3. Recall Check / Pemeriksaan Ingatan

Run at EVERY M0 (session start / continuation). Procedure:

1. From the memory files read, attempt to answer these canonical questions:
   - Q1. What task(s) are ACTIVE or BLOCKED right now, at what phase, with what status? (DONE/CANCELLED rows do not count — answering with a sealed task is a triage failure per 4d H6, not recall)
   - Q2. What decisions has the user locked? Which are still pending?
   - Q3. What artifacts exist and where (paths)?
   - Q4. Who is the user — language, preferences, style, timezone?
   - Q5. What was asked → what was done, in the recent trajectory?
   - Q6. What is next up / blocked / unresolved?
   - Q7. What environment facts matter (tools, known issues, conventions)?
2. Count categories fully answerable from files = restored.
3. **restored / 7 ≥ 95%** → in practice: 7/7, or 6/7 with the missing category being NORMAL-priority and non-blocking. Anything less → gap-fill loop.
4. Gap-fill loop: handoff archives → worklog tail (last ~3 entries) → actual files on disk → (last resort) ask the user. Re-verify after filling.
5. Never fabricate an answer to make the count pass — a fabricated recall is worse than a lost one: it is confidently wrong.
6. Recall answers come from FILES only — a continuation summary is never a recall source (4d H8); it may at most suggest what to go VERIFY in the files. An answer quotable only from the summary is not restored, it is contaminated.

## 4. Loss Budget / Anggaran Kehilangan

**MAY drop (the intended ~5%):**
- Verbose narrative explanations (keep the conclusion, drop the elaboration)
- Redundant examples that repeat the same point
- Dead-end exploration details (keep the lesson learned, drop the wandering)
- Exact wording of user messages (keep the meaning and the decisions)

**NEVER drop:**
- Task IDs, phases, statuses
- Locked or pending decisions
- Artifact and script paths
- User language, preferences, timezone
- Next steps, blockers, open questions
- Known issues that will bite the next session

## 5. Loss Scenarios & Prevention / Skenario Kehilangan & Pencegahan

| # | Scenario | How context dies | Prevention |
|---|----------|------------------|------------|
| 1 | Auto-summary compression | Session exceeds context; platform replaces it with a lossy summary | M1 checkpoints DURING the session — by the time compaction hits, disk already holds the state |
| 2 | Abrupt session end | User leaves without ceremony; nothing was written | M3 triggers on ANY farewell signal, however short; M1 frequency means at most one phase of drift |
| 3 | Mid-task context exhaustion | Long implementation stretch with no writes | M1 pre-emptive checkpoint BEFORE long stretches; M2 on pressure signals |
| 4 | Multi-session gap | Work spans many days; early sessions blur together | Handoff archives per session + MEMORY.md promotion of durable facts |
| 5 | Multi-agent clobber | Subagents overwrite shared state concurrently | memory/ is single-writer (main agent); subagents report via append-only worklog |
| 6 | Silent drift | SESSION-STATE edited incrementally until stale entries mislead | Atomic full rewrite — the snapshot is always complete and current |
| 7 | Stale-task pickup | A sealed (DONE/CANCELLED) task left in the Active table reads like pending work — the next session resumes finished work, re-does it, re-reports it | SKILL.md 4d: ACTIVE-only table (H2) + same-write seal (H3) + anti-resurrect — revisits open a NEW Task ID (H4) + stale-guard with user reconfirmation (H5) + M0 triage (H6) + legacy quarantine (H7) |
| 8 | Stale continuation summary | The platform's continuation summary is frozen far behind reality (founding-era incident: four releases); it narrates sealed tasks as pending and embeds "continue with the last task" — trusted blindly it re-executes a finished chain | SKILL.md 4d H8–H13: quarantine the summary (H8) — version-ground its claims (H10), resolve work via the Active table only (H9), cross-check "pending" claims against the Sealed list (H11), report the conflict in the first response (H12), never seed the Active table from it (H13) |

## 6. Worked Example / Contoh Kasus

Session ends after building a skill. Handoff written with: task ID + status (✓ cat.1), 7 locked decisions (✓ cat.2), 8 artifact paths (✓ cat.3), user profile notes (✓ cat.4), compressed trajectory (✓ cat.5), 3 next steps (✓ cat.6), tooling notes (✓ cat.7). Next session M0: all 7 questions answerable → 7/7 = 100% ≥ 95% → proceed after confirming the plan.

Contrast: same session ends with NO handoff, and the platform's auto-summary keeps only a vague task description. Next session M0: Q1 partially answerable, Q2–Q3 unanswerable → ≤ 3/7 → integrity breached → gap-fill loop must reconstruct from worklog and filesystem before ANY work resumes.

**Penjelasan (ID):** Perhatikan contoh kedua — itu bukan skenario hipotetis. Itu persis yang terjadi pada session ini sendiri sebelum protokol dibuat: ringkasan otomatis kehilangan fakta bahwa optimizer sudah selesai dieksekusi, dan fakta itu hanya selamat karena worklog ditulis dengan disiplin. Standar 95% ada untuk memastikan pemulihan tidak lagi bergantung pada keberuntungan.
