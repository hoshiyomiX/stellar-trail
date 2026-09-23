# Task Files Explorer (Built-in Asset) — Referensi Deploy & Operasi

> Aset bawaan stellar-trail sejak v3.1.0 (server v1.1; UI v2.2 sejak v3.3.0, UI v3.0 sejak v3.5.4).
> Explorer adalah **alat opsional & opt-in** — bukan bagian dari mandat protokol.
> Ia menggantikan secara fungsional popup "All files in task" platform dengan
> halaman custom di preview URL.

## 0. Kapan Dipakai / When to Use

Gunakan bila user (ID/EN):
- ingin halaman web / index.html custom yang tampil di preview URL platform;
- ingin dashboard file persisten (download/ + archive/) yang hidup otomatis tiap boot;
- bertanya cara membuat skrip/servis bertahan lintas restart container (hook /start.sh).

**Jangan pakai** bila proyeknya aplikasi web interaktif (Next.js dsb.) — server web proyek
selalu lebih berhak atas port 3000; explorer otomatis berdiri down (guard ada di explorer.sh).

## 1. Arsitektur (diverifikasi empiris di platform container Z.ai)

```
preview-<bot-id>.space-z.ai        (frontend platform — popup tinggal diabaikan)
  -> ingress platform :81          (reverse-proxy, env FC_CUSTOM_LISTEN_PORT)
     -> 127.0.0.1:3000             (upstream — SISI KITA)
        -> explorer.py             (server stdlib Python; UI = explorer-ui/index.html, MD3 adaptif)
```

Fakta kunci:
1. Saat upstream :3000 kosong, ingress menjawab 502 placeholder; begitu ada server di 3000,
   seluruh preview URL menampilkan server itu.
2. Popup preview adalah frontend browser platform — tidak bisa dimatikan dari container;
   yang bisa diganti adalah ISI preview URL.
3. Proses biasa mati saat tool call selesai (platform membunuh pohon turunan);
   satu-satunya cara daemon hidup terus = **double-fork orphan** (PPID=1 + setsid).

## 2. Manifes File (assets/explorer/)

| File | Peran |
|------|-------|
| `explorer.py` | Server stdlib Python v1.1 (ThreadingHTTPServer); /api/files walk depth-4, parse task dari worklog.md, **blok skill guardian** (versi stellar-trail + heal terakhir + status watcher), serve file dgn guard path realpath (hanya dalam ROOTS) plus **`?dl=1`** untuk mode attachment (unduhan paksa); PIDFILE; env `STELLAR_PROJECT` (default /home/z/my-project), port via argv[1] (default 3000) |
| `explorer.sh` | Launcher --ensure/--status/--stop; guard Next.js (package.json menang); double-fork orphan; env `STELLAR_PROJECT` |
| `explorer-ui/index.html` | UI MD3 Expressive adaptif v3.0 (compact/medium/expanded/large/XL + landscape; list-detail ≥1240px; tema gelap/terang **adaptif** — ikut `prefers-color-scheme` + toggle persist; zero-dependency) — fitur v3.0: pencarian live (debounce 200 ms), filter tipe dinamis dengan hitungan, sort kolom nama/ukuran/waktu dengan toggle arah, copy-path per item, render bertahap 100 item (IntersectionObserver + tombol Muat lagi), state loading/kosong/error; fitur v2.2: kartu Guardian, quick-download per kartu, waktu relatif, refresh saat fokus |
| `dev.sh.template` | Template hook boot v2: tidy download/ -> archive/, fullstack guard, heal skill stellar-trail, ensure watcher + explorer, refresh repo.tar berkala |

## 3. Langkah Deploy

### Kasus A — container baru (belum ada .zscripts/dev.sh)
1. Salin aset ke lokasi aktif (root proyek default /home/z/my-project):
   `cp assets/explorer/explorer.py assets/explorer/explorer.sh <proyek>/.zscripts/`
   `mkdir -p <proyek>/.zscripts/explorer-ui && cp assets/explorer/explorer-ui/index.html <proyek>/.zscripts/explorer-ui/`
   `cp assets/explorer/dev.sh.template <proyek>/.zscripts/dev.sh && chmod +x <proyek>/.zscripts/dev.sh`
2. Jalankan sekali: `bash <proyek>/.zscripts/explorer.sh --ensure`
3. Setiap boot berikutnya, /start.sh menjalankan dev.sh -> explorer + watcher hidup otomatis.

### Kasus B — dev.sh sudah ada (JANGAN ditimpa)
1. Salin explorer.py, explorer.sh, explorer-ui/ seperti di atas.
2. Tambahkan blok ensure di akhir dev.sh:
   ```bash
   if [ -f "$PROJECT/.zscripts/explorer.sh" ]; then
       bash "$PROJECT/.zscripts/explorer.sh" --ensure >> "$BOOTLOG" 2>&1 || log "WARN: explorer gagal"
   fi
   ```
3. Jalankan `bash .zscripts/explorer.sh --ensure`.

## 4. Aturan Konflik Port (WAJIB dihormati)

- `package.json` ada di root proyek -> Next.js pemilik :3000 -> explorer STAND-DOWN.
- Port 3000 dipakai proses lain yang bukan explorer -> explorer menolak start (log saja).
- Explorer bind 127.0.0.1 saja — tidak pernah expose langsung ke luar; akses luar selalu
  lewat ingress platform.

## 5. Lapisan Persistensi

1. **repo.tar pre-stop** — platform mem-pack volume sebelum stop; .zscripts/ ikut ter-backup.
2. **Hook /start.sh** — tiap boot menjalankan dev.sh bila ada.
3. **dev.sh** — ensure explorer.sh + watcher.sh.
4. **watcher 30 dtk** — auto-heal bila explorer mati (terverifikasi: kill -9 -> hidup <=30 dtk).
5. **M0 protokol memory** — tiap sesi baru memastikan watcher hidup.
6. **Lapis anti-rollback** — bila lingkungan ter-reset: lihat `references/environment-resilience.md`
   + `scripts/snapshot-repo.sh` (satu masalah, satu keluarga solusi).

## 5a. Gejala Recycle vs Rollback — Bedakan Sebelum Menalar (v3.5.7)

Dua kegagalan lingkungan yang mudah tertukar (insiden konsumer 2026-09-22, §6.5 laporan —
"index.html killed" ternyata bukan file yang hilang):

- **Preview explorer mati** (proses :3000 hilang, "index.html killed") = tanda **container
  recycle** — proses hidup di container (server explorer, watcher) mati bersama container;
  INI BUKAN bug skill. Aset bawaan `assets/explorer/explorer-ui/index.html` tetap utuh di
  dalam instalasi. Remedy: deploy ulang opt-in — `bash .zscripts/explorer.sh --ensure`
  (dev.sh/watcher menghidupkannya lagi otomatis di boot berikutnya bila hook /start.sh aktif).
- **File aset instalasi hilang / versi mundur** (aset bawaan lenyap, banner versi body tua,
  komponen rilis baru absen) = tanda **rollback arsip-restore** — instalasi skill ditimpa
  arsip basi. Remedy: `bash scripts/heal-skill.sh --check` — cross-check lock melaporkan
  `DOWNGRADED` bila lock lebih baru dari disk (lihat environment-resilience.md §3b/§4).

Aturan ringkas: **proses mati → recycle (deploy ulang); file berubah/hilang → rollback (heal)**.

## 5b. Fitur v3.3.0 (server v1.1 + UI v2.2)

- **Kartu Guardian** (statistik ke-5): versi stellar-trail terinstal, indikator
  watcher hidup/mati, dan waktu heal terakhir — dibaca dari `_meta.json`,
  `watcher.pid`, dan marker `.skill-heal.last` (best-effort; kartu disembunyikan
  bila skill tidak terinstal).
- **Quick-download per kartu**: tombol unduh muncul saat hover/fokus pada tiap
  kartu file — memakai endpoint `?dl=1` (Content-Disposition: attachment) sehingga
  browser selalu mengunduh, bukan membuka. Tombol Unduh di dialog pratinjau kini
  juga memakai `?dl=1`.
- **Copy path**: tombol salin di dialog pratinjau menyalin path file lengkap di
  server (root + rel) ke clipboard — berguna untuk bekerja di terminal.
- **Waktu relatif** pada kartu ("baru saja", "5 mnt lalu", "3 jam lalu") dengan
  timestamp lengkap sebagai tooltip; dialog pratinjau tetap pakai timestamp penuh.
- **Refresh saat fokus**: data dimuat ulang seketika saat tab kembali aktif
  (visibilitychange) — di luar polling 10 detik reguler.
- **Urut Terlama** (mtime naik) + pencarian kini juga mencocokkan ID task
  (mis. query "27" menemukan file terkait Task 27).

## 5c. Fitur UI v3.0 (explorer-ui/index.html, sejak v3.5.4)

Semua murni sisi klien — kontrak API `explorer.py` tidak berubah sama sekali.

- **Pencarian live** dengan debounce 200 ms (nama / ekstensi / ID task).
- **Filter tipe dinamis**: chip per kategori (Dokumen, Gambar, Data, Arsip/zip,
  Kode, Office, Lainnya) dengan hitungan file; kategori kosong disembunyikan
  otomatis dari data `/api/files`.
- **Sort kolom** nama / ukuran / waktu — klik untuk aktif, klik lagi untuk toggle
  naik/turun dengan indikator panah (menggantikan dropdown urut v2.2).
- **Copy path per item**: tombol salin di tiap kartu/brs (navigator.clipboard +
  fallback `execCommand`) dengan toast "Path disalin" — tombol di dialog pratinjau
  tetap ada.
- **Render bertahap**: direktori besar dirender 100 item per chunk; chunk
  berikutnya dimuat otomatis saat tombol mendekati viewport
  (IntersectionObserver, fallback: tombol "Muat lagi" diklik manual).
- **Tema adaptif**: mengikuti `prefers-color-scheme` selama user belum memilih
  manual; pilihan manual tersimpan di localStorage.
- **Breadcrumb** direktori pada nama file (segmen folder diredupkan) + state
  loading/kosong/error yang jelas, termasuk tombol "Coba lagi".

## 6. Perintah Kontrol

```
bash .zscripts/explorer.sh --status   # kesehatan + log
bash .zscripts/explorer.sh --stop     # matikan explorer
bash .zscripts/explorer.sh --ensure   # hidupkan bila belum (idempoten)
```

**Etika & batasan:** explorer hanya melayani direktori kerja (ROOTS download/ + archive/),
read-only, bind loopback. Ia tidak pernah dipakai untuk mengekspos file di luar proyek,
dan deploy-nya selalu diberitahukan ke user (bukan inisiatif diam-diam) — konsisten dengan
prinsip consent seksi 4b dan intervensi-infrastruktur-hanya-atas-permintaan seksi 4c.

## 7. Kesegaran Deployment — sync-fresh v1.2 (sejak v3.5.7)

Masalah: saat explorer di-deploy sebagai SALINAN (pola maintainer: `.zscripts/explorer.py`
+ `.zscripts/explorer-ui/index.html` di luar instalasi skill), auto-heal lama hanya
mengecek KEHIDUPAN (`healthz`) — bukan KESEGARAN. Salinan basi (mis. hasil restore
`repo.tar` lama, atau rilis UI baru yang tak pernah tersalin) tetap hidup tanpa ada
yang menyadarinya: *alive-but-stale*.

Mekanisme v1.2 (di `explorer.sh`, berlaku juga untuk varian portabel — no-op bila
path kanonik tidak ada di lingkungan tersebut):

- `--ensure` kini memanggil `sync_fresh()` SEBELUM cek hidup: `explorer.py` dan
  `explorer-ui/index.html` dibandingkan (`cmp`) dengan kanonik
  (`$PROJECT/download/stellar-trail/assets/explorer/`); drift → salin ulang +
  catat `sync-fresh` di log; `explorer.py` berubah → restart server (UI dibaca
  per-request — cukup disalin).
- `--status` menampilkan baris `fresh : server=ok ui=ok (vs kanonik)`.
- Hidup-tapi-basi kini diperbaiki otomatis, bukan hanya mati-dihidupkan.

**Bukti lapangan (drill Task 43, 2026-09-22):** (A) proses di-kill → auto-heal
watcher pulih dalam 20 detik; (C) drift disuntikkan ke `explorer.py` deployment →
`--ensure` memulihkan md5 dari kanonik + restart + healthz ok; tiga salinan
(`.zscripts/`, kanonik, instalasi live) terverisi identik. Pola konsumen tidak
terdampak: explorer konsumen berjalan LANGSUNG dari direktori instalasinya —
kesegaran file mengikuti versi skill, dijaga oleh heal-skill (verdict DOWNGRADED
bila lock > disk, sejak v3.5.7).
