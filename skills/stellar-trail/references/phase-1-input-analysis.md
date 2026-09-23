# Phase 1 Reference — Input Analysis / Analisa Input

**Rule: nothing happens before classification. No tool call, no writing, no answer draft.**

## Classification Taxonomy / Taksonomi Klasifikasi

| Type | Category (EN / ID) | Signals | Typical Deliverable |
|------|--------------------|---------|---------------------|
| 0 | Conversational / Konversasial | Greetings, thanks, "ok", reactions, small talk, meta-questions about the chat itself | Short friendly reply |
| 1 | Document Creation / Pembuatan Dokumen | "report", "PRD", "proposal", "script", "laporan", "buat PPT/Word/Excel/PDF", manuscripts | docx / pdf / xlsx / pptx file |
| 2 | Chart & Visualization / Visualisasi | "chart", "graph", "diagram", "mind map", "flowchart", "bar chart", "deployment diagram" | PNG / Mermaid / interactive chart |
| 3 | Interactive Web / Web Interaktif | "website", "dashboard web", "web app", "sistem manajemen", "build a page", "Next.js" | Runnable web application |
| 4 | Data & Code Processing / Pemrosesan Data & Kode | "analyze this CSV", "process data", "convert", "write a function", "fix this script", calculations | Analysis results / scripts / transformed files |

## Decision Procedure / Prosedur Keputusan

1. **Find the deliverable first.** Ask: "What artifact does the user want to END UP with?" Classify by the FINAL deliverable, not by the source material. A request that mentions a document but wants a chart output is Type 2.
2. **Detect the language** of the user message — response, deliverable content, and markers must all match it.
3. **Rate complexity**: `trivial` (single step, no dependencies) / `standard` (multi-step, one domain) / `complex` (multi-step, multi-domain, needs delegation).
4. **Ambiguity check**: if two types could apply ("dashboard" — web app or report?), classify as `AMBIGUOUS (Type X vs Y)` and let Phase 2 resolve it. Never resolve ambiguity by silent guessing.

## Special Cases / Kasus Khusus

- **Mixed messages** ("analyze this CSV then make a report and a chart"): classify EACH sub-request, mark the primary type, list secondaries. One response, one clarification batch, one unified plan.
- **Follow-up messages**: re-classify every turn. A continuation is classified as `Continuation of active task (Type N)`. A NEW request inside an ongoing thread is a new task and gets its own full cycle.
- **Messages that only provide answers**: these are continuation turns — Phase 1 still emits its marker (this is how nothing escapes classification), then Phase 2 documents the answers.
- **Emotional/social content** (frustration, praise): still Type 0 if no action is requested. Acknowledge warmly in Phase 6 — discipline must not make the assistant feel robotic.

## Marker Templates / Template Penanda

Setiap turn dibuka banner protokol (`## 🌠 stellar-trail v3.4.0 — protokol aktif` / EN `— protocol active`) SEBELUM marker fase pertama (SKILL.md seksi 1); di bawah ini hanya template markernya:

```
## 🌠 FASE 1 — KLASIFIKASI
Type 1 (dokumen) — laporan analisa PDF; bahasa: ID; kompleksitas: standar

## 🌠 FASE 1 — KLASIFIKASI
Type 0 (conversational) — ucapan terima kasih; bahasa: ID; kompleksitas: trivial

## 🌠 FASE 1 — KLASIFIKASI
AMBIGUOUS — Type 2 vs Type 3 ("dashboard"); bahasa: EN; kompleksitas: standar

## 🌠 FASE 1 — KLASIFIKASI
Continuation — jawaban klarifikasi untuk task Type 1 aktif; bahasa: ID
```

**Penjelasan (ID):** Kesalahan klasifikasi adalah kesalahan termahal dalam seluruh alur kerja — semua fase berikutnya mewarisi kesalahan itu. Karena itu Fase 1 tidak boleh dilewati bahkan untuk pesan satu kata: justru pesan satu kata ("ok", "lanjut", "ganti") paling mudah salah tafsir, dan klasifikasi eksplisit memaksa Anda membuktikan bahwa Anda MEMBACANYA, bukan mengasumsikannya.
