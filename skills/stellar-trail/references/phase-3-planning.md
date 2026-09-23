# Phase 3 Reference — Planning / Perencanaan

**Rule: no implementation action before a visible plan exists. A plan you didn't write down is a plan you will silently abandon.**

## Todo Discipline / Disiplin Todo

1. **Create the full list first** — every step from current state to delivered artifact, mapped to the Phase 1 classification.
2. **States**: `pending` → `in_progress` → `completed`. Only ONE item `in_progress` at any moment.
3. **Update immediately**: mark `completed` the moment an item finishes — never batch updates at the end (batched updates hide stalls and failures).
4. **Remove, don't abandon**: tasks that became irrelevant get removed from the list entirely, with a one-line reason in the response if material.
5. **Blocked items stay `in_progress`** with a note — never flip to `completed` to "clean up" the list. If blocked after 2 consecutive failures, surface the blocker to the user instead of looping.

## Step Granularity / Granularitas Langkah

- Each step = one verifiable outcome ("generate chart PNG and save to download/"), not one tool call, not one vague phase ("do the work").
- Steps map to the classified type: Type 1 → load document skill → outline → generate → verify → deliver. Type 3 → init project → build UI → wire API → test → deliver link.
- 3–7 steps for standard tasks; more only when genuinely needed; fewer than 3 means the task is trivial — a 2-item list is still a list and still required.

## Task IDs & Delegation / Task ID & Delegasi

- Number steps globally: `1`, `2`, `3`. When steps can run in parallel, give them grouped IDs: `2-a`, `2-b` (both children of step 2).
- Delegated work (subagents) receives: the Task ID, a self-contained task description (the subagent cannot see your context), the worklog protocol, and explicit output expectations.
- You remain accountable for delegated steps — verify their output before marking `completed`.

## Worklog / Log Kerja Bersama

In multi-agent or long tasks, append a structured record per completed Task ID to the shared worklog (append-only, never overwrite):

```
---
Task ID: <id>
Agent: <agent>
Task: <what was asked>

Work Log:
- <concrete step>

Stage Summary:
- <key results / decisions / artifacts>
```

## Plan Changes / Perubahan Rencana

Deviations happen. The rule is **explicit, never silent**:

```
[RENCANA DIUBAH] Langkah 3 dipecah menjadi 3a (generate) + 3b (verify) karena output script melebihi 2000 baris
```

An undocumented deviation is indistinguishable from chaos; a documented one is engineering.

## Marker Templates / Template Penanda

```
## 🌠 FASE 3 — RENCANA
5 langkah: (1) muat skill xlsx (2) susun struktur (3) tulis & jalankan script (4) verifikasi output (5) laporkan

## 🌠 FASE 3 — N/A (Type 0 conversational)
```

**Penjelasan (ID):** Rencana yang tertulis punya tiga fungsi: (1) membuat urutan eksekusi bisa diaudit pengguna, (2) memaksa Anda membayangkan SELURUH pekerjaan sebelum terjebak di tengahnya, dan (3) menjadi dasar objektif untuk menandai selesai — "selesai" hanya sah jika ada langkah yang dicoret, bukan perasaan bahwa pekerjaan sudah beres. Bahkan task trivial wajib punya daftar 1-2 langkah: daftar itu murah, dan kebiasaan itu yang menjaga protokol tetap hidup.
