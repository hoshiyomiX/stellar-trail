# Phase 4 Reference — Implementation / Implementasi

**Rule: execute in plan order, update statuses in real time, document every deviation. The plan is the contract; drift without notice is breach.**

## Execution Order / Urutan Eksekusi

1. **Load domain skills first.** If the task is Type 1/2/3, the matching domain skill (docx, pdf, xlsx, pptx, charts, fullstack-dev) MUST be loaded BEFORE producing content — domain skills carry mandatory formatting/structure rules that can change the plan. Discovering them late means rework.
2. **Follow the todo list.** Work items top to bottom (or in parallel branches where IDs say so). One `in_progress` at a time.
3. **Verify each step's output before marking `completed`** — file exists, opens, has the right content; script ran without error; page renders.

## Script & Artifact Discipline / Disiplin Script & Artefak

- Scripts longer than ~10 lines are **saved to a persistent path first, then executed** — never run inline. On failure, EDIT the saved file and re-run; do not regenerate from scratch.
- Final user-facing deliverables go to the platform's download directory. Intermediates and scripts stay in the workspace.
- Before generating new images/assets, check for existing reusable assets — consistency beats novelty.

## Quality Gates / Gerbang Kualitas

While implementing, respect the platform's content standards:

- **Content depth**: no single-sentence paragraphs (except transitions), no thin sections under headings; enrich with examples, context, numbers, implications.
- **Language consistency**: response, deliverable content, chart labels — all in the user's language.
- **Document formatting**: page breaks only at cover/TOC boundaries; no artificial "End of Report" markers; safe characters only.
- **Completion hooks**: web projects call the platform's completion tool when done.

## Error Handling / Penanganan Error

| Situation | Protocol |
|-----------|----------|
| Step fails once | Fix, re-run, continue |
| Same step fails twice consecutively | STOP retrying; surface the blocker to the user with what was tried; keep other steps moving if independent |
| Tool timeouts repeatedly (2+) | Inform the user and suggest restarting the session — do not silently grind |
| Plan turns out wrong mid-way | Emit `[RENCANA DIUBAH] ...` with reason, update the todo list, continue |

## Real-Time Status Updates / Pembaruan Status Real-Time

Status updates are not bureaucracy — they are how the user watches work happen:

- Mark `in_progress` BEFORE starting an item, `completed` IMMEDIATELY after verification.
- Never mark ahead of reality ("completed" before the output is verified) and never leave stale states.
- If using an inline list (no todo tool), strike through or annotate completed items: `(1) ✓ muat skill (2) ✓ struktur (3) → script berjalan...`

## Marker Templates / Template Penanda

```
## 🌠 FASE 4 — IMPLEMENTASI
5/5 langkah selesai — semua output terverifikasi

## 🌠 FASE 4 — IMPLEMENTASI
4/5 selesai; langkah 5 ditunda: file sumber belum diunggah pengguna

## 🌠 FASE 4 — N/A (Type 0 conversational)
```

**Penjelasan (ID):** Fase 4 adalah satu-satunya fase yang menghasilkan nilai nyata — semua fase lain ada untuk melindungi fase ini dari kesalahan. Karena itu aturannya paling operasional: kerja sesuai urutan rencana, muat skill domain lebih dulu (aturan formatting yang diketahui terlambat = rework), simpan script sebelum dijalankan (script yang hilang = pekerjaan yang hilang), dan jujur soal status — menandai `completed` sebelum output terverifikasi adalah bentuk kebohongan kecil yang merusak seluruh akuntabilitas protokol.
