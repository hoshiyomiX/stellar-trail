# Changelog

## v5.3.1 — 2026-10-17 · Seal Ritual acceptance gate (Task-26 measured finding, owner-approved)

**Why — the 26-run loop + pressure battery (Task 26) surfaced one residual hole:** agents sealed a task in the same turn they delivered it, on a bare "continue", with no explicit user acceptance — 4/4 occurrences across BOTH bodies (v5.3.0 and the v5.2.0 control) — because the pinned body's seal trigger read only "artifact exists on disk, or the user cancelled", while the acceptance clause ("delivered and accepted") lived only in the memory-hygiene reference, outside the body the agents actually run. Severity was low (the H4 ref-mechanism correction path proved live), but the gate belongs in the body.

**What:**

- **S1 acceptance gate (owner option (b) chosen from the parked proposal):** S1 now verifies the outcome against reality AND the user's acceptance of the report — a bare continuation is not acceptance; an unaccepted delivery keeps the row `WAITING (acceptance)` and seals on the acceptance turn.
- **Pickup routing stays mechanical:** the WAITING row lists report acceptance among its awaited inputs and routes an awaited acceptance to the Seal Ritual instead of the Resume Protocol; the QRC SEAL/PICKUP blocks and the violations list carry the same gate ("sealing a delivery the user never accepted").
- **memory-hygiene synced:** the S1 procedure gains the same clause; H1's WAITING definition now lists report acceptance and plan confirmation; the failure-modes ledger records the measured same-turn seal.
- **skill-card + README** describe the acceptance-gated Seal Ritual; description frontmatter untouched (wording-frozen v9, 877/1024). **Version 5.3.1** (banner constants, integrity.version, skill card).

**Verification (all run this release):** task13 46/46 (A4/C7/C8 re-pinned) · task11 85/85 (L5 x11 re-pinned) · check-skill 7/7 (description untouched, 877/1024, wording-frozen) · harness-hooks 17/17 · guardtest 14/14 · explorer-gap 8/8 · inner-block single-quote guard · `bash -n` all touched scripts · audit-compliance PASS 0 WARN pre- and post-promotion · manifest 18/18 ×2 · three-tree md5 identical · CLI reinstall byte-identical.

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
