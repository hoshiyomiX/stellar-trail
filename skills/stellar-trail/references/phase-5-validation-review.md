# Phase 5 Reference — Validation & Review / Validasi & Review

**Rule: NO deliverable is reported (Phase 6) before it is validated (Phase 5). "I tested it while implementing" does not replace the review pass — implementation-time testing is drafting; validation is the audit.**

**Penjelasan (ID):** Fase ini lahir dari pola kegagalan yang berulang: implementasi selesai, terasa "kayaknya udah benar", laporan dikirim — dan cacatnya baru ketahuan oleh user. Validasi memisahkan dua peran yang sama pentingnya: saat mengimplementasi Anda adalah pembuat; saat memvalidasi Anda adalah auditor yang curiga terhadap pembuat itu. Review lengkap berarti: bukti nyata, bukan perasaan.

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
| 0 conversational | N/A — no deliverable to validate; mark `## 🌠 FASE 5 — N/A (Type 0)` |
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

**No silent fixes without re-validation — "sudah saya betulkan" is a claim, not evidence.**

## Accepted Deviations / Deviasi yang Diterima

Some defects are consciously accepted (time, scope, platform limits). An accepted deviation MUST be:
- explicit in the validation marker (`1 deviasi diterima: …`),
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
## 🌠 FASE 5 — VALIDASI
L1 PASS · L2 smoke 3/3 · L3 lint 2/2 · L4 diff PASS — 1 defect diperbaiki (font fallback)

## 🌠 FASE 5 — VALIDASI
enforce-gates.sh 7/7 PASS (exit 0) · L4 diff: 1 deviasi diterima (data sumber tidak lengkap — dicatat di laporan)

## 🌠 FASE 5 — N/A (Type 0)
tanpa deliverable

## 🌠 FASE 5 — VALIDASI
regresi: 12/12 audit responsif terdahulu tetap PASS pasca-edit
```

## Memory Hook / Kait Memory

Checkpoint (M1) the validation OUTCOME, not just "done": defects found and fixed, accepted deviations, re-checks pending. The next session inherits open validation debt through SESSION-STATE — that is exactly the kind of context that must never be lost.

**Penjelasan (ID):** Lima lapis ini sengaja berurutan dari murah-objektif ke mahal-subjektif: kalau file saja tidak ada (L1), tidak ada gunanya mendebat apakah isinya memenuhi permintaan (L4). Pemisahan track terminal/non-terminal jujur tentang batas mesin: perintah bisa memutuskan apakah skrip lolos lint, tapi hanya pembaca yang bisa memutuskan apakah laporan menjawab pertanyaan. Mesin menegakkan yang bisa ditegakkan mesin; sisanya tetap tanggung jawab — dan itu justru membuat bagian manusia dari review ini tidak bisa diserahkan begitu saja ke "kayaknya udah oke".
