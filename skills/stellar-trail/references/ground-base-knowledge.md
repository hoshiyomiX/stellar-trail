# Ground Base Knowledge — Canonical Classification Reference / Basis Pengetahuan Acuan Klasifikasi

**Role: Phase 1 classifications must be GROUNDED in this base — every type/language/complexity decision traces to a rule ID below. Intuition, habit, and "it feels like" are classification defects, not shortcuts.**

**Penjelasan (ID):** Mengapa perlu basis acuan? Karena klasifikasi bebas ("menurut perasaan saya ini Type 3") tidak bisa diaudit, tidak bisa diperbaiki, dan tidak konsisten antar session. Dengan basis acuan, setiap keputusan klasifikasi punya alamat yang bisa dikutip — salah alamat bisa diperdebatkan dan diperbaiki, bukan sekadar salah tebak. Inilah yang dimaksud "referensi yang tepat & benar": bukan referensi paling lengkap, tapi referensi yang KANONIK — satu sumber kebenaran untuk klasifikasi.

## How to Use / Cara Pakai

1. BEFORE classifying, consult the matching rule groups: **GBK-T** (type), **GBK-L** (language), **GBK-C** (complexity), **GBK-A** (ambiguity registry), **GBK-E** (environment ground truths).
2. Cite the applied rule IDs in the `## 🌠 FASE 1 — KLASIFIKASI` marker (or its content line), e.g. `Type 1 (GBK-T1: final deliverable = file dokumen)`.
3. On any conflict between intuition and this base, **the base wins** — if the base itself is wrong, flag it as a proposed locked-decision change instead of silently deviating.
4. This base is versioned with the skill; changes to it are changelog entries, not silent edits.

## GBK-T — Task Type Taxonomy / Taksonomi Jenis Task

**Decision principle (GBK-T0): classify by the FINAL DELIVERABLE the user wants to end up with — never by the source material or the tools mentioned along the way.**

| Rule | Type | Canonical definition | Inclusion signals | Exclusion (NOT this type) |
|------|------|----------------------|-------------------|---------------------------|
| GBK-T1 | 0 Conversational | No artifact is requested; social or meta exchange | Greetings, thanks, reactions, small talk, chat about the protocol itself | A question that asks for ANY produced artifact is not Type 0 |
| GBK-T2 | 1 Document creation | FINAL deliverable = a document FILE | "report", "proposal", "PRD", "script/manuscript", "laporan", named office/PDF outputs | A request that only USES a document as input (e.g. "rangkum file ini jadi mind map") is the OUTPUT's type |
| GBK-T3 | 2 Chart & visualization | FINAL deliverable = a visual/diagram artifact | "chart", "graph", "diagram", "mind map", "flowchart", "deployment diagram", "peta konsep" | An interactive dashboard APP is Type 3; a chart embedded in a requested REPORT keeps the report primary |
| GBK-T4 | 3 Interactive web | FINAL deliverable = a runnable web page/app | "website", "web app", "dashboard (interaktif)", "sistem", "buat halaman", framework requests | A static chart PNG or a PDF report is NOT web even if it renders in a browser |
| GBK-T5 | 4 Data & code processing | FINAL deliverable = computed/transformed results, scripts, or analysis output | "analyze this data", "convert", "process", "calculate", "fix this script", "write a function" | Analysis whose final form is a REPORT file is Type 1 (processing is the means) |

- **Boundary rule (GBK-T6): mixed deliverables** — classify EACH sub-request, mark the PRIMARY (the one the user names first or emphasizes), list secondaries. One clarification batch and one unified plan cover all.
- **Boundary rule (GBK-T7): means vs ends** — tools and inputs mentioned in the request do not change the type; only the ends do. "Analyze this CSV and give me a PDF report" = Type 1 (ends = PDF), processing is means.
- **Platform skill mapping (GBK-T8):** Type 1 → docx/pdf/xlsx/pptx skill by requested format · Type 2 → charts skill · Type 3 → fullstack-dev skill · Type 4 → direct scripting. The mapping is mandatory routing, not a suggestion.

## GBK-L — Language Rules / Aturan Bahasa

- **GBK-L1:** The response language = the language of the user's CURRENT message. Dialect/mixed registers: follow the DOMINANT language of the message, not individual loanwords.
- **GBK-L2:** Deliverable content language = user's language UNLESS the user explicitly pins another language for the artifact. A summary request in Chinese about an Indonesian-language project produces a Chinese summary.
- **GBK-L3:** Protocol markers (`## 🌠 FASE n — LABEL` sub-judul; `[MEM | …]`) carry content in the user's language; the marker keywords themselves are protocol constants and never translated.
- **GBK-L4:** Explicitly pinned language survives subsequent turns even if later messages mix languages — record it once, apply it until the user changes it.

## GBK-C — Complexity Calibration / Kalibrasi Kompleksitas

| Rule | Level | Calibration (ALL that apply) |
|------|-------|------------------------------|
| GBK-C1 | trivial | Single step, single domain, no file dependencies, no delegation, no clarification gaps beyond confirmation |
| GBK-C2 | standard | 2–5 steps, one domain, one or two artifacts, no subagent delegation needed |
| GBK-C3 | complex | Multi-domain OR needs delegation OR produces 3+ interdependent artifacts OR touches infrastructure (publish, deploy, persistent state) |

- **GBK-C4:** Complexity compresses format, never phases (Absolute Mandate rule 4). A trivial task still runs all applicable phases — each just shrinks.
- **GBK-C5:** Calibration may be RAISED mid-task when scope grows (discovered dependencies, new artifacts); it is never silently lowered.

## GBK-A — Ambiguity Registry / Registri Ambiguitas

Known ambiguous patterns and their REQUIRED handling — ambiguity is resolved in Phase 2, never by silent guessing:

| Rule | Pattern | Resolution path |
|------|---------|-----------------|
| GBK-A1 | "dashboard" (no context) | Classify `AMBIGUOUS — Type 2 vs Type 3`; ask: static report-with-charts or interactive web app? |
| GBK-A2 | "report" + source contains data/charts | Deliverable-first: the FILE is primary → Type 1; charts are embedded sections, not separate deliverables, unless the user asks for standalone images |
| GBK-A3 | "make it better / fix this" with no artifact named | Ask which artifact; if exactly one active artifact exists in SESSION-STATE, confirm it explicitly rather than assume |
| GBK-A4 | New request inside an ongoing task thread | Separate classification: continuation of the active task, or a new task with its own cycle? When unclear → ask |
| GBK-A5 | Word that matches multiple types in mixed languages | Translate the INTENT, not the word: the final-deliverable principle (GBK-T0) decides |

## GBK-E — Environment Ground Truths / Kebenaran Dasar Lingkungan

Facts about the working environment that classifications and plans must respect (these are TRUE statements, not aspirations):

- **GBK-E1:** User-facing deliverables live under the platform download directory (`download/`); scripts persisted before execution under `scripts/`. A plan that produces artifacts outside these conventions is defective at classification time already.
- **GBK-E2:** Domain skills (docx/pdf/xlsx/pptx/charts/fullstack-dev) MUST be loaded before producing content in their domain — they can change the plan.
- **GBK-E3:** Memory files (`MEMORY.md`, `SESSION-STATE.md`) and the worklog are the cross-session record; conversation history is lossy. Classification of a continuation turn starts from M0 restore, not from re-deriving context.
- **GBK-E4:** Terminal-verifiable enforcement is executed via the bundled gate script (`scripts/enforce-gates.sh`); non-terminal rules remain text mandates (SKILL.md section 8b). Never CLAIM a script run that did not happen.
- **GBK-E5:** Environments differ (fonts, tools, network). A classification that assumes a specific font/tool availability without checking is grounded in wish, not knowledge — verify or flag as a Phase 2 question.

**Penjelasan (ID):** GBK-E adalah bagian yang paling sering berubah dan paling sering dilupakan — ia menjawab "apa yang BENAR-BENAR berlaku di lingkungan ini" sehingga rencana tidak dibangun di atas asumsi. Bila sebuah fakta lingkungan terbukti salah (misalnya path berubah), perbaiki fakta di sini lewat keputusan terkunci — jangan biarkan basis acuan dan realitas berbeda pendapat.
