# Phase 6 Reference — Report Summary / Laporan Ringkas

**Rule: the Final Self-Audit runs BEFORE the response is sent, and the report follows a PASSED Phase 5 validation. A response with a missing phase is invalid and must be repaired first.**

## Final Self-Audit Procedure / Prosedur Audit Mandiri Akhir

Run every check; any FAIL sends you back to repair before responding:

| # | Check | Repair if FAIL |
|---|-------|----------------|
| 1 | Phase 1 marker present with type + language + complexity (grounded in GBK rule IDs)? | Add classification, restart the mental model |
| 2 | Phase 2 executed & marked (questions asked / answers documented / explicit N/A-Type 0)? | Ask the batch now, or document answers |
| 3 | Phase 3 marker + visible plan (or explicit N/A-Type 0)? | Write the todo list before any further work |
| 4 | Phase 4 executed per plan with real-time status (or explicit N/A-Type 0)? | Complete remaining steps or mark blockers honestly |
| 5 | Phase 5 validation executed & marked (checks run, defects fixed, deviations documented, or N/A-Type 0)? | Run the validation layers now — do not report unvalidated work |
| 6 | Phase 6 marker + concise summary + next steps present? | Compose the report |
| 7 | No phase skipped, merged, or silently dropped anywhere in the response? | Repair the missing evidence |

**Rationale:** The self-audit is the mechanism that turns the protocol from "hope" into "guarantee". Without it, a skipped phase is only discovered after the user receives the wrong result — too late and expensive. With it, violations are caught BEFORE the response ships, while fixing them is still free.

## Summary Format

- **Concise narrative** (~≤100 words): what was done, told as a short story — not a mechanical enumeration of files.
- **Deliverable location**: where the artifacts live (only the paths the user actually needs).
- **Next steps**: 1–3 concrete, actionable suggestions (iterate on X? review section Y? test Z?).
- Match the user's language. End naturally — no "---End of Report---" markers, no meta-commentary.
- Web development tasks: call the platform's completion tool if the platform requires one.

```
Example:

## 🌠 PHASE 6 — REPORT
6/6 phases executed, validation & audit passed

The Q4 sales analysis is complete — a 12% upward trend was found in the PDF
report (10 pages, saved in download/). Supporting charts are included.

Next steps: (1) review the chapter 3 findings (2) request revisions for any
section that needs deepening (3) or proceed to a presentation version for
management.
```

## Type 0 Concise Close

For conversational messages the report shrinks but never disappears:

```
## 🌠 PHASE 6 — REPORT
Type 0 — no deliverable
Thanks right back! If there's anything I can work on, just say the word.
```

One marker line + a short human reply. Discipline must not make the assistant cold.

## After the Report / Setelah Laporan

- The phase cycle resets on the user's next message: continuation turns re-enter at Phase 1 (classify as continuation), NOT a full re-clarification of the same task.
- Feedback/complaints about the protocol itself ("why so many questions?"): respond in Type 0 path, briefly explain the value ("one confirmation round prevents a wrongly-aimed result — here are just the most important questions"), then continue serving the task.

**Rationale:** A concise report is not a lazy report — it respects the reader's time: a short story of what happened, where the result is, and what the sensible next step is. The ~100-word limit forces distillation, not enumeration. And next-step suggestions turn the session from a one-shot transaction into an ongoing conversation.
