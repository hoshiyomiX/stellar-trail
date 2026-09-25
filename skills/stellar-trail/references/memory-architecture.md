# Memory Architecture — Files, Templates, Write Rules
**Arsitektur Memory — File, Template, Aturan Penulisan**

This reference defines the memory file layout, full templates, write semantics, ownership, and recovery. Read this when creating or updating any memory file.

## 1. Layout / Tata Letak

```
/home/z/my-project/
├── memory/
│   ├── MEMORY.md                  # long-term memory (durable facts, promoted via M3)
│   ├── SESSION-STATE.md           # working snapshot (atomic rewrite per checkpoint)
│   └── handoffs/
│       └── YYYY-MM-DD-<slug>.md   # immutable session archives (write once)
├── worklog.md                     # append-only multi-agent audit trail (platform convention)
└── download/                      # user-facing deliverables (platform convention)
```

**Division of labor / Pembagian peran:**
- `SESSION-STATE.md` answers **"what work REMAINS right now?"** — the first file a new session reads; its task table is ACTIVE-only (SKILL.md 4d).
- `MEMORY.md` answers **"what is always true?"** — profile, decisions, inventory, conventions.
- `handoffs/` answer **"what exactly happened in that session?"** — the detailed record.
- `worklog.md` answers **"who did what, in what order?"** — the audit ledger, shared with subagents.

## 2. MEMORY.md Template

```markdown
# MEMORY — Long-Term Memory / Memory Jangka Panjang
> Durable facts only. Promoted from session work via M3. Last updated: YYYY-MM-DD (session N)

## User Profile / Profil User
- Language, register/casual style, timezone, communication preferences

## Locked Decisions / Keputusan Terkunci
- [D1] ... (locked YYYY-MM-DD, session N)
- [D2] ...

## Project Inventory / Inventaris Proyek
| Item | Path | Status |

## Conventions / Konvensi
- ... (marker styles, naming rules, established patterns)

## Environment / Lingkungan
- tooling status, known issues, model info
```

**Promotion criteria (what enters MEMORY.md):** facts that remain true across sessions — a learned user preference, a locked design decision, a delivered artifact path, an established convention, a persistent environment fact. **What never enters:** task progress (→ SESSION-STATE), one-off details (→ handoff), anything that will be stale tomorrow.

## 3. SESSION-STATE.md Template

```markdown
# SESSION-STATE — Working Snapshot / Snapshot Kerja
> Atomic snapshot — rewritten at every checkpoint. Latest write wins.
> Checkpoint at: YYYY-MM-DD HH:mm (session N, tz) — M1/M2/M3

## Active Tasks / Task Aktif
| Task ID | Description | Fase | Status | Updated |
|---------|-------------|------|--------|---------|
| 31 | contoh task berjalan | F4 IMPLEMENTASI | ACTIVE | 2026-09-18 |

(status vocabulary — SKILL.md 4d H1: `ACTIVE · BLOCKED` work-eligible, plus
the `STALE` flag (H5). DONE/CANCELLED tasks NEVER live here — they are
sealed to the list below in the same write that closes them (H3). The table
is populated ONLY from user-confirmed work — never seeded from a
continuation summary, which is quarantined input (H13, H8).)

## Sealed Tasks / Task Tersegel
| Task ID | Outcome (one line) | Artifact | Sealed |
|---------|--------------------|----------|--------|
| 30 | v3.4.0 shipped — banner + marker format | download/stellar-trail/ | 2026-09-17 |

(keep the LAST 5 lines only — older entries age out to worklog.md and
handoffs/, where the full record already lives; sealed = terminal:
revisits open a NEW Task ID with `ref: #oldID` — H4, never a reopen)

## Pending Decisions / Keputusan Tertunda
- ... — owner: user/agent · trigger: what unblocks it (or "none currently")
(resolved items are DELETED at the next checkpoint — the resolution lives in
worklog/MEMORY, not here; idle >7 days = zombie → propose sealing once — H6)

## Recent Artifacts / Artefak Terbaru
- path — what it is

## Next Steps / Langkah Berikutnya
1. ... — owner: (user | agent | session N)
(completed steps are REMOVED, not checked off in place — H6)

## Open Questions / Pertanyaan Terbuka
- ... (or "none blocking")

## Context Pressure / Tekanan Konteks
- low / normal / elevated — one line why
```

**Atomic rewrite semantics:** write the COMPLETE file each time, never append. Rationale: the file must always be small, current, and self-contained — the next session's M0 reads ONLY this + MEMORY.md as its mandatory minimum. A stale entry left behind by lazy appending is worse than a missing entry: it misleads. And a sealed entry left in the Active table is the worst case of all — it gets PICKED UP as work by a later session (the exact failure SKILL.md 4d exists to kill): H2 keeps the table ACTIVE-only, H3 seals in the same write, and H7 quarantines legacy pollution at the first checkpoint of every session. A continuation summary sits OUTSIDE the restore read order entirely — quarantined input whose claims are version-grounded against these files before any part is believed (H8–H13).

## 4. Handoff Archive Template

Filename: `handoffs/YYYY-MM-DD-<short-slug>.md` — date = when the handoff is WRITTEN, slug = session topic.

```markdown
# Handoff — <topic> (YYYY-MM-DD, session N)
> Written at session end via M3. Immutable record.

## 1. Task Identity / Identitas Task
Task IDs, what each was, final status.

## 2. User Decisions / Keputusan User
Locked + still-pending decisions, with dates.

## 3. Artifacts / Artefak
Every deliverable/script path + one-line description.

## 4. User Profile Notes / Catatan Profil User
New preferences or communication signals learned this session.

## 5. Trajectory / Trayektori
Compressed: what was asked → what was done → what was learned.

## 6. Pending / Tertunda
Next steps, blockers, open questions for the next session.

## 7. Environment / Lingkungan
Tooling status, known issues, anything the next session must know.
```

All 7 sections are mandatory — write "none" explicitly rather than omitting a section. A section that is silently missing is indistinguishable from a section that was forgotten (the same doctrine as the phase N/A markers in Part I of the main protocol).

## 5. Write Rules Summary / Ringkasan Aturan Penulisan

| File | Mode | Who may write | When |
|------|------|---------------|------|
| SESSION-STATE.md | atomic rewrite | main session agent ONLY | every M1/M2/M3 |
| MEMORY.md | merge/promote | main session agent ONLY | M3 (and M0 when recovering lost facts) |
| handoffs/*.md | write once | main session agent ONLY | M3 |
| worklog.md | append only | main agent AND subagents | major milestones, with Task ID |

**Penjelasan (ID):** Single-writer untuk memory/ mencegah race antar agent: subagent bisa menimpa snapshot milik main agent dan menghancurkan state. Subagent melapor lewat worklog (append-only, aman dari race) dan mengembalikan hasil ke main agent, yang kemudian melakukan checkpoint. Aturan sederhana: memory/ adalah milik satu penulis, worklog adalah milik bersama.

## 6. Recovery Matrix / Matriks Pemulihan

| Situation | Recovery procedure |
|-----------|-------------------|
| `memory/` missing entirely | Initialize structure; rebuild MEMORY.md + SESSION-STATE.md from worklog.md entries; confirm reconstruction with the user before trusting it. If worklog.md is also absent (total cold start, e.g. a brand-new container), initialize an empty structure and treat it as session 1 — still confirm with the user |
| SESSION-STATE.md stale/contradictory | Newest write wins for state; cross-check worklog tail; if still ambiguous, ask the user ONE clarifying question |
| Active table contains DONE/CANCELLED rows (legacy write by an older protocol version) | Quarantine, do not execute: the first M1 moves them to the Sealed list (SKILL.md 4d H7); if the user explicitly wants that work again, open a NEW Task ID with `ref: #oldID` |
| MEMORY.md conflicts with newer SESSION-STATE | SESSION-STATE wins for current state; MEMORY wins for durable facts; if genuinely contradictory, worklog arbitrates history |
| Handoff archive contains an error | Never edit it — write a correcting note in the NEXT handoff |
| User references work not in any memory file | Search worklog.md and the filesystem (download/, scripts/, skills/) BEFORE claiming ignorance; then record what you found |
| Session summary conflicts with memory files | Memory files win; promote anything the summary has that memory lacks |
