# Phase 5 Reference — Validation & Review / Validasi & Review

**Rule: NO deliverable is reported (Phase 6) before it is validated (Phase 5). "I tested it while implementing" does not replace the review pass — implementation-time testing is drafting; validation is the audit.**

**Rationale:** This phase was born from a repeating failure pattern: implementation finishes, it feels "probably correct", the report ships — and the user discovers the defect. Validation separates two equally vital roles: while implementing you are the maker; while validating you are an auditor suspicious of that maker. A complete review means: real evidence, not feelings.

## The Five Review Layers / Lima Lapis Review

Run layers in order; each layer has a track — **terminal** (verifiable by command, enforce via `scripts/enforce-gates.sh`) or **non-terminal** (judgment, enforce via text mandate):

| # | Layer | Checks | Track |
|---|-------|--------|-------|
| L1 | Artifact verification | Deliverable exists at the expected path, non-empty, sane size for its type (e.g. a "10-page report" of 3 KB is suspicious) | **terminal** |
| L2 | Smoke test | The artifact WORKS: renders / opens / executes without error. Web → page loads + zero console errors + key interactions; script → runs on a test input; document → opens & parses; chart → renders with correct labels | **terminal** (where a command exists) |
| L3 | Lint & structural | Syntax/structure validity: `bash -n`, `python3 -m py_compile`, `node --check`, JSON parse, HTML structure. Documents: depth rules, language consistency, page-break rules, character safety | **terminal** |
| L4 | Request-vs-deliverable diff | Re-read the ORIGINAL request (and clarification answers). Does the artifact satisfy every stated requirement? Missing sections? Wrong language? Wrong audience? This is a semantic audit only a reader can do | **non-terminal** |
| L5 | Regression check | When EDITING an existing artifact: did the change break what already worked? Re-run prior critical checks (the previous audit's PASS items) | mixed — terminal for scripted checks |

## Type-Specific Minimum Checklists / Daftar Periksa Minimum per Jenis

| Type | Minimum validation |
|------|--------------------|
| 0 conversational | N/A — no deliverable to validate; mark `## 🌠 PHASE 5 — N/A (Type 0)` |
| 1 document | L1 exists+size · L2 opens/parses programmatically (e.g. python-docx/openpyxl/pypdf read-back; page count sane) · L3 structural rules (fonts embedded, no forbidden escapes, page-break placement) · L4 diff vs request (sections, depth, language, audience) |
| 2 chart | L1 file exists / mermaid code block complete · L2 renders (PNG opens; Mermaid parse if code) · L3 label language consistency + contrast · L4 chart answers the actual question asked |
| 3 web | L1 dev server/artifact present · L2 loads + zero console errors + 2–3 key interactions exercised (headless browser when available) · L3 lint (js/ts compile) + responsive smoke at 2 viewports · L4 features match request |
| 4 code/data | L1 output file exists · L2 script exit code 0 on real input · L3 syntax lint all touched files · L4 result sanity (numbers plausible, spot-check 2–3 values manually) |
| mixed | Union of the primaries' checklists; run every sub-deliverable's L1–L3, then one combined L4 |

## Fix Loop / Loop Perbaikan

1. Log every defect found (layer, description, severity).
2. Fix, then **re-run the full layer that caught it** — a fix for a lint defect re-runs lint; a fix for a smoke defect re-runs smoke.
3. A fix that touches another layer's surface re-runs that layer too (a rendering fix re-triggers L3+L2).
4. Loop until PASS, or until the defect is explicitly downgraded to an accepted deviation (below).

**No silent fixes without re-validation — "I already fixed it" is a claim, not evidence.**

## Accepted Deviations

Some defects are consciously accepted (time, scope, platform limits). An accepted deviation MUST be:
- explicit in the validation marker (`1 accepted deviation: …`),
- justified (why accepting is cheaper/correct vs fixing),
- listed again in the Phase 6 report under next steps.

Anything else fails the gate. An undocumented defect discovered later was never "accepted" — it was missed.

## Terminal Enforcement / Penegakan Terminal

- Applicable terminal checks (L1–L3) run through the bundled gate script when available:
  `bash scripts/enforce-gates.sh --task <type> --artifact <path> [--lint f1 f2 …]`
- If the script is unavailable (not installed, different environment), run the equivalent checks manually AND state the fallback in the marker — never claim a script run that did not happen (GBK-E4).
- The script's exit code is the gate: 0 = pass, non-zero = at least one check failed; the fix loop applies before proceeding.

## Marker Templates / Template Penanda

```
## 🌠 PHASE 5 — VALIDATION
L1 PASS · L2 smoke 3/3 · L3 lint 2/2 · L4 diff PASS — 1 defect fixed (font fallback)

## 🌠 PHASE 5 — VALIDATION
enforce-gates.sh 7/7 PASS (exit 0) · L4 diff: 1 accepted deviation (source data incomplete — noted in the report)

## 🌠 PHASE 5 — N/A (Type 0)
no deliverable

## 🌠 PHASE 5 — VALIDATION
regression: 12/12 previously-passing responsive audits still PASS post-edit
```

## Memory Hook / Kait Memory

Checkpoint (M1) the validation OUTCOME, not just "done": defects found and fixed, accepted deviations, re-checks pending. The next session inherits open validation debt through SESSION-STATE — that is exactly the kind of context that must never be lost.

**Rationale:** The five layers are deliberately ordered from cheap-objective to expensive-subjective: if the file does not even exist (L1), there is no point debating whether its content satisfies the request (L4). The terminal/non-terminal track split is honest about the machine's limits: a command can decide whether a script passes lint, but only a reader can decide whether a report answers the question. The machine enforces what machines can enforce; the rest stays human responsibility — which is exactly what keeps the human part of this review from being handed over to "looks fine to me".
