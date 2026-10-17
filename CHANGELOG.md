# Changelog

## v5.3.0 — 2026-10-17 · sandbox-evolution alignment + mechanical Seal Ritual & Resume Protocol

**Why — the sandbox evolved, and continuing agents still got confused at two points:** the z.ai GLM platform now ships its own native execution mechanics (task-classification types, a clarification gate with a batched-question tool, outline-before-content, a worklog ledger with Task IDs) that overlap this protocol's execution half — an agent following both needed to know which mandate wins. And field continuation failures concentrated on exactly two pathways: a finished task whose seal never fully happened got re-executed next session, and an unfinished task got restarted from scratch or re-clarified from zero.

**What:**

- **Platform alignment clause (section 0):** where a platform mandate and the protocol demand the same thing, the platform's form is INHERITED — never duplicated or fought; the protocol concentrates on what the platform does not ship (Type 0 handling, N/A discipline, GBK grounding, the entire memory half). Stricter mandate wins. Phase 1 now notes the native-type ↔ GBK-T 1–4 mapping.
- **Clarification range widened 4–6 → 4–8 with platform deference** (Phase 2 + QRC): where the platform's clarification gate mandates a batch range, the platform's range wins; the one-batch single-round core is unchanged.
- **Phase touchpoints inherited:** Phase 3 commits document outlines via the platform outline tool when available; Phase 4 persists generation scripts to files (platform rule); Phase 6 delivers files/preview links via the platform send tool in IM mode.
- **Seal Ritual (S1–S4) — the only exit for a finished task:** verify artifact → one atomic SESSION-STATE rewrite (row → Sealed line) → worklog append with the verdict ON the Task-ID line (`Task ID: <id> (DONE|CANCELLED — SEALED)`) → snapshot + marker. No ritual = not sealed = it WILL be picked up as work next session. Seal detection is now greppable: a tail Task-ID line without a verdict is an open task.
- **Resume Protocol (R1–R5) — the only entry for an unfinished task:** resolve via the Active table only → reconstruct (worklog + row + disk) → verify artifacts exist → continue at the recorded next step (NEVER restart completed steps) → confirm once, execute. A resume is not a re-clarification.
- **WAITING status added to the closed vocabulary** (ACTIVE · WAITING · BLOCKED · STALE flag): protocol-paused tasks (awaiting answers/confirmation/external event) stop masquerading as mid-execution ACTIVE or obstacle BLOCKED — pickup collects the awaited input and continues, never re-asks the batch. Every Active row now records its resume anchor (next step) — the R4 entry point.
- **Two new pickup rows:** WAITING → collect + resume; continuation-directive-with-empty-table → open a NEW Task ID (the newest sealed task is context, never the continuation target).
- **QRC gains SEAL and RESUME blocks;** self-audit item 7 and the violations list extended (restart-instead-of-resume, re-ask-on-WAITING); memory-hygiene gains full pathway procedures (section 5.0), the Next-column template, and the verdict-line worklog template.
- **Version 5.3.0** (banner constants, integrity.version, skill card).

**Verification (all run this release):** task13 46/46 · task11 85/85 (re-pinned) · check-skill 7/7 (description untouched, 877/1024, wording-frozen) · harness-hooks 17/17 · guardtest 14/14 · explorer-gap 8/8 · inner-block single-quote guard · `bash -n` all touched scripts · audit-compliance PASS 0 WARN · manifest 18/18 ×2 · three-tree md5 identical · CLI reinstall byte-identical.

## v5.2.0 — 2026-10-12 · SKILL.md body optimization — trimmed, renumbered, LLM-scannable (10-point owner plan)

**Why — a 10-point owner optimization plan for the protocol body:** the body had drifted wordy (245 lines), carried absolute-rule numbering inherited from a deleted lineage (11–16), formatted its memory lifecycle as dense prose an LLM must re-parse every session, and left task pickup implicit in a 13-rule list.

**What:**

- **Absolute rules renumbered 11–16 → 1–6, every cross-reference aligned** (SKILL.md, memory-hygiene, environment-resilience, update-skill header, README, skill-card).
- **Phase 4 scope corrected:** Phase 4 PROGRESSES the task (run, read, write, edit, delegate) and NEVER reviews or explains results — review belongs to Phase 5, reporting to Phase 6.
- **Memory lifecycle (section 3) opens with an M0–M3 overview table** (stage · fires when · core action · marker) — the restore path is now a scannable map — and states the lifecycle's purpose outright: it defies context pressure and summary loss (everything material is written to files before it can be lost and restored from files, never from recollection or summaries).
- **Task pickup (section 4) gains an explicit decision table:** ACTIVE = resume (confirm the plan first) · BLOCKED = unblock or ask · STALE = user reconfirm-or-seal · SEALED = context only (revision = new Task ID) · summary-only = not work · worklog-DONE-but-still-active = quarantine first. Incomplete / pending / completed are now verdicts with actions, not inferences.
- **Banner + marker examples render as a quoted card** (section 1) — banner, phase marker, and memory marker in one blockquote card.
- **Quick Reference Card redesigned** as a professional LLM quick-reference: labeled blocks (ACTIVATION · LATE LOAD · EXECUTION · MEMORY · PICKUP · HYGIENE · BUDGETS), rule-numbered, carrying the Phase-4 scope guard and the M0–M3 flow inline.
- **English + grammar pass across the body; H1–H13 tightened to one-line cores** (full text remains in memory-hygiene.md); every section 0–10 keeps its full core rule set (body 245 → 268 lines / 5168 → 5352 words — the +23 lines are the two new decision tables).
- **Description: measured-frozen.** Two trimmed variants were built and measured against a same-day v9 control on the reference battery (87 SDK calls, zero final errors): v10 (−16 chars + the defiance claim) tied the control 6/10 overall but lost the mixed greeting+task cell decisively (0/6 vs the control's 5/6); v10b (single-variable: v9 + only the workflow-sentence swap) failed the same cell (1/3) and the PRD cell (0/3). Both REJECTED — v9 is a measured local optimum and stays byte-identical (877/1024). The "defies context pressure and summary loss" claim ships in the body (intro, section 0, section 3, QRC) instead. Side finding: the same-day control measured 6/10 vs its historical 8/10 — the domain-skill cells (PRD/chart/PDF) flipped to distractor capture for BOTH variants (day effect); the mixed-cell comparison is the discriminator that decided.
- **Version 5.2.0** (banner constants, integrity.version, skill card).

**Verification (all run this release):** trigger-eval rejection measurement above (artifacts: task24 workspace — description-v{9-baseline,10,10b}.txt + raw JSONL + analysis) · task13 · task11 · check-skill 7/7 (description untouched, 877/1024) · harness-hooks 17/17 · guardtest 14/14 · explorer-gap 8/8 · inner-block single-quote guard · `bash -n` all touched scripts · audit-compliance PASS 0 WARN · manifest 18/18 ×2 · three-tree md5 identical · CLI reinstall byte-identical.
