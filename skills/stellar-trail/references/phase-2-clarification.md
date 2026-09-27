# Phase 2 Reference — Clarification Proposal / Proposal Klarifikasi

**Rule: every new task gets one batched round of 4–6 questions. No exceptions — not for complete specs, not for user pressure, not for simplicity.**

## Question Dimensions / Dimensi Pertanyaan

Cover the dimensions that materially change the output. Pick 4–6 of the most impactful, in this priority order:

1. **Audience & tone** — who consumes this, how should it sound
2. **Purpose** — what should the audience do/remember after
3. **Length / size** — calibrated ranges, not "how long?" with no anchor
4. **Style / design** — concrete options (palette hints, references), never vague "formal vs casual"
5. **Format constraints** — headers/footers, speaker notes, density (words per section)
6. **Must-have facts** — numbers, names, citations, assets that only the user knows
7. **Deliverable shape** — for ambiguous requests: web app vs report document vs chart

Each question offers 3–4 concrete options plus an implicit free-text escape. Mark one option as recommended (your best default) so a non-answering context still yields progress.

## Handling Complete Specs / Menangani Spek Lengkap

When the user pinned audience + style + length already:

- Do NOT ask what is already pinned as an open question — **convert pinned specs into confirmation questions** ("I'm assuming retail investors as the audience — is that right?").
- Do ask about everything NOT pinned: format constraints, depth, must-include facts, structural preferences.
- Rationale to keep asking: "complete" by the user's standard is often incomplete by the execution standard. Confirmation is cheap (one line); a wrong assumption is expensive (total rework).

## Handling Pressure

| User says | Correct behavior |
|-----------|------------------|
| "langsung kerjakan" / "just do it" | Phase still runs: 1 confirmation block ("my assumptions: A, B, C — correct me if wrong") + 2–3 gap questions on never-specified dimensions |
| "jangan banyak tanya" | Compress to exactly 4 rapid-fire confirmation/gap questions, single batch |
| "quick question" about the task | The question itself is input for Phase 2 — answer it AND complete the batch |
| User answers partially | Document what arrived, ask ONLY about the remaining gaps |

**Pressure compresses the FORMAT of the phase. It never cancels the PHASE.** This is the core of the absolute mandate: a protocol guardian that retreats because it was asked to retreat is not a guardian.

## Continuation Turns

When the user is answering your questions:

1. Document every answer received (one line each) — this is the phase's evidence.
2. Check for NEW gaps the answers opened (answers often reveal missing assets or conflicting constraints).
3. New gaps → ask only those (1–3 questions). No gaps → emit `## 🌠 PHASE 2 — CLARIFICATION` with content `all answers documented — no gaps` and proceed to Phase 3.
4. NEVER re-ask an answered question — that is the one true annoyance this protocol must avoid.

## Marker Templates

```
## 🌠 PHASE 2 — CLARIFICATION
5 questions asked — awaiting answers

## 🌠 PHASE 2 — CLARIFICATION
5/5 answers documented; 1 new gap (logo assets) — 1 follow-up question

## 🌠 PHASE 2 — N/A (Type 0 conversational)
```

## Tool Usage / Penggunaan Tool

Use the platform's structured question tool (e.g. AskUserQuestion) when available: it enforces batching, concrete options, and single-round behavior. Fall back to inline numbered questions otherwise. Either way: ONE round, 4–6 questions, concrete options.

**Rationale:** One batched round is cheap; a wrongly-aimed deliverable is expensive. The 4–6 range was chosen because below 4 an important dimension is almost always missed, and above 6 users start tiring of answering. The mandate attaches to the TASK: once a task's question round is answered, this phase counts as satisfied — never re-ask, only fill new gaps.
