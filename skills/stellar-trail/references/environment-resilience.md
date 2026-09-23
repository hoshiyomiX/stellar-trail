# Environment Resilience — Anti-Rollback Playbook (Container Platforms)

> **Kapan membaca file ini:** lingkungan kerja Anda berjalan di container/sandbox yang bisa di-reset
> (contoh: preview container platform, ephemeral CI runner) DAN Anda melihat gejala: file hasil kerja
> "hilang" setelah restart, versi file terdegradasi ke kondisi lama, atau skill/skrip custom lenyap.
> Bila Anda bekerja di mesin lokal/statis yang tidak pernah di-reset, seksi ini tidak berlaku — abaikan.

## 1. Model Ancaman: Bagaimana Container Me-Rollback State Anda

Banyak platform container memulihkan direktori proyek dari sebuah **arsip restore** (contoh nyata:
`/home/sync/repo.tar` yang diekstrak oleh hook `/start.sh` saat boot — `rm -rf <project>` kecuali
mountpoint, lalu `tar xf repo.tar`). Arsip ini idealnya ditulis ulang oleh **pre-stop packer** saat
container berhenti. Masalahnya: **pre-stop tidak selalu jalan** — container bisa di-crash, di-force-kill,
atau pack-nya gagal (cabang kegagalan ini diakui sendiri oleh hook platform). Akibatnya boot berikutnya
me-restore **kondisi lama**: rollback diam-diam yang menghapus jam-jam kerja.

Empat fakta struktural yang bisa dimanfaatkan (diverifikasi empiris pada satu platform container, 2026):

1. **Sumber restore terbaca**: hook boot dan arsip restore biasanya dapat dibaca dari dalam container
   (`cat` hook-nya, `tar -tf` arsipnya) — Anda bisa membedah formatnya tanpa menebak.
2. **Mount object-storage bertahan**: direktori yang di-mounted dari object storage (mis. ossfs) hidup
   DI LUAR container dan tidak ikut ter-rollback — kanal penyelamatan untuk backup dan marker state.
3. **Boot menoleransi arsip korup** (warning + lanjut) — kegagalan refresh tidak membuat container mati.
4. **Packer bisa mengecualikan direktori penting** (forensik nyata: `skills/` tidak pernah masuk arsip
   packer platform) — instalasi skill adalah target rollback yang paling sering kena.

## 2. Lapisan Pertahanan (sejak v3.3.0 — lapis shadow backup dihapus; catatan arsitektur 2026-09-19 di bawah)

| Lapis | Peran | Kapan bekerja |
|---|---|---|
| **L1 — Refresh sumber** (`scripts/snapshot-repo.sh`) | Menimpa arsip restore platform dengan snapshot kondisi TERKINI — kini termasuk `skills/stellar-trail` (append bedah) — sehingga restore boot native = state segar *selama arsip itu bertahan* | `--apply` setelah milestone signifikan; `--apply-auto` berkala (debounce + cooldown 15 mnt) |
| **L2 — Self-heal instalasi** (`scripts/heal-skill.sh`) | Verifikasi manifest SHA-256 instalasi skill; bila drift (file hilang/rusak/ekstra, versi `_meta.json` mundur) → perbaikan dari sumber sehat berikutnya (pemilihan berbasis versi, v3.5.4): kanonik → vault kelas-A → arsip restore → registry; juga melaporkan state pin semua skill di lock + info sehat-tapi-tua (v3.5.3) | `--check` (deteksi + heal) / `--force`; cocok untuk boot hook & jalankan berkala |
| **L3 — Backup original** | Undo: arsip restore asli platform disalin sebelum ditimpa — bisa dikembalikan kapan pun | Selalu, sebelum setiap swap L1 |

L1 mencegah rollback **di sumbernya**; L2 **menyembuhkan instalasi** bila rollback/clobber tetap terjadi
(arsip basi, cache platform, taruhan apa pun); L3 menjamin setiap intervensi terhadap infrastruktur
**bisa di-undo**. Ketiganya saling independen — kegagalan satu lapis tidak melumpuhkan dua lainnya.

**Temuan arsitektur 2026-09-19 (forensik boot):** pre-stop packer platform ternyata MENIMPA arsip
restore dengan arsipnya sendiri di setiap siklus henti — build L1 kita (termasuk append bedah
`skills/stellar-trail`) **tidak pernah bertahan lintas boot**. Bukti: boot 05:34 menemukan repo.tar
"asing" (0 entri `skills/`) dan direktori `skills/stellar-trail` hilang total, padahal build L1
malam sebelumnya membawa 32 entri skill. Konsekuensinya, peran lapisan bergeser: **rantai lintas-boot
yang benar-benar efektif = kanonik `download/stellar-trail/` (persisten via arsip platform, yang
memang memuat `download/`) + L2 boot-heal** (menyembuhkan instalasi dari kanonik itu, termasuk
membuat ulang `_meta.json`/`origin.json` bila instalasi ter-wipe total — sejak v3.5.2). L1 tetap
bernilai untuk kesegaran intra-boot (repo.tar tidak pernah >15 mnt lebih tua) dan kanal undo L3.

**Dua konvensi lokasi install clawhub (temuan 2026-09-19):** clawhub CLI ≥ 0.23.3 memasang fresh
install **owner-scoped**: `skills/@owner/stellar-trail` dengan lock key `@owner/stellar-trail`;
instalasi era CLI lebih lama bisa flat: `skills/stellar-trail` dengan lock key `stellar-trail`.
Seluruh rantai L2 dan boot-hook (dev.sh / template) sejak v3.5.2 **location-aware**: mencari dan
menyembuhkan KEDUA layout, resolusi sumber walk-up multi-level, dan hint update membaca lock key
aktual dari `.clawhub/lock.json`.

**Mengapa tidak ada lagi lapis shadow backup (pelajaran empiris, dihapus di v3.3.0):** generasi
arsitektur sebelumnya menyertakan shadow backup rolling (snapshot proyek periodik ke mount persistent,
dipulihkan otomatis saat deteksi stale). Empat temuan forensik memvonisnya merugikan: (1) deteksi
stale-nya **false-positive** — aktivitas backupnya sendiri menaikkan heartbeat lalu memicu percobaan
restore yang gagal (insiden 07:38 UTC: dua percobaan restore beruntun gagal ekstrak); (2) **blind spot
yang sama** dengan sumbernya — `skills/` tetap tidak terlindungi justru oleh lapis yang katanya
penyelamat; (3) **failure domain yang sama** — hidup di mount object storage yang sama persis dengan
arsip yang diamankan; (4) biaya tulis 62 MB per 30 menit untuk perlindungan semu. Pelajaran umumnya:
**backup yang jalur restore-nya tidak pernah teruji lebih berbahaya daripada tidak ada backup** — ia
memberi rasa aman sambil menambah mode kegagalan baru. Dua lapis yang tersisa kini keduanya teruji
end-to-end, dan kanal ketiga (registry ClawHub) selalu tersedia sebagai jaring terakhir.

## 3. Memakai Skrip

### 3a. `scripts/snapshot-repo.sh` (L1 — refresh arsip restore)

```
bash scripts/snapshot-repo.sh --status             # diagnosis: usia arsip restore, verdict BASI/SEGAR
bash scripts/snapshot-repo.sh --dry-run            # build + verifikasi penuh TANPA menyentuh arsip
bash scripts/snapshot-repo.sh --apply              # backup asli -> build -> verifikasi -> swap -> verifikasi
bash scripts/snapshot-repo.sh --apply-auto         # --apply dengan gerbang ganda (debounce + cooldown) —
                                                   # aman dipanggil berkala dari boot hook / watcher
bash scripts/snapshot-repo.sh --restore-original   # undo: kembalikan arsip asli terakhir (terverifikasi)
```

Prinsip keamanan yang dipegang skrip (jangan dilanggar saat memodifikasi):

- **Konsen eksplisit untuk aksi manual**: `--apply`/`--restore-original` hanya dijalankan saat diminta;
  `--apply-auto` sengaja berat gerbangnya (debounce + cooldown) agar aman dipicu berkala.
- **Backup-first**: arsip asli disalin ke mount persistent SEBELUM swap; bila backup gagal, swap batal.
- **Verify-before-swap**: tar divalidasi (struktur + jumlah entri + entri kunci) dua kali — build dan
  staging — sebelum rename-overwrite; final diverifikasi lagi setelah swap.
- **Audit member anti traversal**: arsip restore diekstrak platform via `tar xf` tanpa validasi
  member, maka skrip sendiri yang menjaga: member absolut atau berkomponen `..` DITOLAK keras,
  symlink ber-target absolut diperingatkan; `--restore-original` pun diaudit sebelum swap
  (undo tetap byte-identical — verifikasi hanya membaca, arsip korup/hostile ditolak agar tidak
  merusak boot berikutnya).
- **Build anti argument-injection**: daftar entri NUL-terpisah via `tar --null -T` — nama file
  tidak pernah di-parse sebagai opsi tar (file `--use-compress-program=...` di project root
  tidak bisa membuat tar mengeksekusi perintah); nama diawali `-` atau ber-newline di-skip.
  Disiplin penyerta: fungsi yang memproduksi data di stdout tidak boleh mencetak diagnostik
  ke stdout (`slog_q` log-only) — diagnostik bocor akan terbaca sebagai entri daftar.
- **Marker fingerprint**: arsip buatan sendiri ditandai (mtime|size) agar tidak dibackup berulang dan
  backup original sejati tidak tertimpa (pelajaran bug kolisi nama resolusi-detik).
- **Format mengikuti packer platform**: entri relatif tanpa prefix `./`, exclude `node_modules/`,
  `db/`, `upload/`, `.venv/`, `.next/` — beda format = restore aneh. Pengecualian `skills/`
  milik packer ditutup dengan append bedah `skills/stellar-trail` (path literal, bukan ekspansi
  nama file — vektor injection tidak berlaku).
- **Atomic sebisanya mount**: build di disk lokal -> salin ke nama staging di mount yang sama ->
  rename-overwrite in-mount (rename didukung umum oleh FUSE object-storage).

### 3b. `scripts/heal-skill.sh` (L2 — self-heal instalasi, sejak v3.3.0)

```
bash scripts/heal-skill.sh --status     # laporan versi + lock + drift + pin (semua skill) + info usia, TANPA aksi
bash scripts/heal-skill.sh --check      # deteksi drift; heal bila ada (default) — pin dilaporkan juga
bash scripts/heal-skill.sh --force      # heal tanpa deteksi
bash scripts/heal-skill.sh --manifest   # regenerasi manifest (SAAT RILIS, di salinan kanonik)
bash scripts/heal-skill.sh --dir <path> <mode>   # target instalasi stellar-trail lain
```

- **Verifikasi tanpa sumber eksternal**: manifest `assets/integrity.sha256` (hash seluruh file
  konten) + `assets/integrity.version` (versi rilis) — file hilang, rusak, ekstra, dan versi
  `_meta.json` yang mundur (signature persis insiden degrade nyata) semuanya terdeteksi.
- **Perbaikan multi-sumber berurut** (location-aware sejak v3.5.2; vault-aware + version-aware
  sejak v3.5.4): `STELLAR_CANONICAL` (env — override absolut) → `<proyek>/download/stellar-trail`
  (deteksi walk-up **2/3/4 level** dari lokasi skill — flat `skills/<slug>` maupun owner-scoped
  `skills/@owner/<slug>`) → **vault kelas-A** (`/home/sync/skill-vault/stellar-trail` — override
  `STELLAR_VAULT` — dan `<proyek>/upload/skill-vault/stellar-trail` ossfs; diisi
  `scripts/vault-sync.sh` saat rilis, lihat 3c) → arsip restore
  (`STELLAR_RESTORE_TAR`, default `/home/sync/repo.tar`, subtree sesuai **layout aktual**
  instalasi) → **saudara konvensi** (`skills/stellar-trail` ↔ `skills/@owner/stellar-trail`,
  v3.5.7 — `clawhub update --force` hanya menyegarkan owner-scoped, maka flat yang dibaca
  platform kini bisa pulih dari saudaranya yang segar) → hint manual `clawhub update
  <lock-key> --force` (butuh login; lock key dibaca dari `.clawhub/lock.json` instalasi,
  bukan hardcoded). Bila semua sumber lokal gagal, skrip **gagal keras**: tanpa manifest
  DAN tanpa sumber, `--check` exit 1 dengan pesan eksplisit (sejak v3.5.2 — sebelumnya
  WARN senyap exit 0) — verifikasi yang mustahil tidak pernah menyamar jadi sukses.
- **Version-assert anti-timpa-baru (v3.5.4)**: kandidat sumber yang versinya lebih TUA dari
  instalasi (rilis manifest, fallback `_meta`) DILEWATI — heal tidak pernah menurunkan versi
  instalasi secara senyap; pemenang = versi tertinggi (tie-break urutan lama). Skenario yang
  dibuka: kanonik restore-basi basi (Task 36) + vault segar → vault menang; instalasi ter-wipe
  total → versi tertinggi yang tersedia.
- **Cross-check lock clawhub (v3.5.7, §6.1 insiden konsumer 2026-09-22)**: versi skill di
  `.clawhub/lock.json` dibandingkan vs disk — lock > disk = verdict **DOWNGRADED** + hint
  `clawhub update`, dan `--check` exit ≠ 0 sampai tertutup; pasca-heal masih < lock = GAGAL
  exit 1. `lock.json` TIDAK ikut di-restore arsip `skills/` → jangkar out-of-band termurah:
  rollback arsip-restore terdeteksi BAHKAN saat semua sumber lokal mati — jebakan false-CLEAN
  "manifest-vs-diri-sendiri" (sehat-tapi-tua) tertutup. `--status` menampilkan baris `lock:`.
- **Laporan pin & usia (v3.5.3)**: semua mode melaporkan state pin SEMUA skill di `.clawhub/lock.json`
  — `PINNED(reason)` = WARN: pin memblokir `clawhub update`/`install` skill itu dan membuat
  `update --all` melewatkannya SENYAP (exit 0 tanpa perbaikan), maka tiap WARN membawa hint
  `clawhub unpin <key>`; verdict drift & exit code TIDAK berubah (pin tidak menyentuh file
  skill — heal tetap pin-agnostic). Ditambah info sehat-tapi-tua: instalasi BERSIH vs manifest
  sendiri tapi kanonik lebih baru → hint upgrade disengaja `--force` (heal ≠ upgrade by design;
  penangkap edge restore-basi yang lolos `--check`). Sumber perbaikan kini dilaporkan BERLABEL
  (env / walk-up-N / platform default / arsip restore) — urutan & mekanisme tidak berubah.
- **Aman by design**: identitas install clawhub (`_meta.json` ownerId/publishedAt, `.clawhub/`)
  tidak pernah ditimpa — hanya field versi yang dipatch konsisten; bila keduanya absen akibat
  instalasi ter-wipe total saat boot, file minimal dibuat ulang (v3.5.2); hasil heal 0644 tanpa
  exec bit, identik dengan perilaku registry (semua invokasi memang via `bash`/`python3`).
- **Di lingkungan reset-prone**: panggil `--check` dari boot hook (setelah L1) dan/atau berkala
  dari watcher — biayanya lokal dan murah; manifest membuat hasilnya bisa diaudit.
- **Sejak v3.5.8 — source self-verify**: kandidat sumber yang membawa manifest rilis wajib lolos
  verifikasi internal (pohon ≡ manifest-nya sendiri) SEBELUM dipilih. Latar: insiden lapangan
  2026-09-22 (receipt §6) — kanonik bawa manifest basi (edit pasca regen) menang seleksi versi,
  disalin setia oleh heal, sehingga boot-heal GAGAL pasca-reset justru saat paling dibutuhkan.
  Kini sumber racun DILEWATI dan kandidat sehat berikutnya (mis. vault kelas-A) mengambil alih;
  seluruh kandidat eligan racun = GAGAL keras (menyalin kerusakan bukanlah penyembuhan);
  override env tetap dihormati dengan peringatan keras; sumber tanpa manifest tetap eligibel
  (perilaku lama utuh — verifikasi sumber-basi dua arah tetap berlaku di do_heal).

### 3c. `scripts/vault-sync.sh` (v3.5.4 — vault kelas-A, adopsi Task 35/41)

```
bash scripts/vault-sync.sh --status   # laporan state kedua vault (ada? versi?)
bash scripts/vault-sync.sh --check    # verifikasi manifest tanpa menulis — drill berkala
bash scripts/vault-sync.sh --apply    # salin kanonik → kedua vault + verifikasi (SAAT RILIS)
```

Vault = salinan penuh kanonik yang hidup DI LUAR siklus wipe/restore
(`/home/sync/skill-vault/` + `<proyek>/upload/skill-vault/` ossfs — keduanya kelas-A
persisten). Heal membacanya otomatis sebagai kandidat sumber (3b). Disiplin: `--apply`
pada write yang SAMA dengan publish; `--check` pada drill bulanan; assert simetris
menolak `--apply` yang akan menimpa vault lebih baru dengan kanonik lebih tua.
Sejak v3.5.7: `--apply` menstempel **versi + tanggal** di `README.md` root vault
(jangkar out-of-band yang mudah dibaca), dan **konsumer dapat menjalankan `--apply`
langsung dari direktori instalasi** (`bash skills/stellar-trail/scripts/vault-sync.sh
--apply` — kanonik = parent dari `scripts/`) — self-arm agar vault terisi sejak menit
pertama, sebelum recycle container pertama; heal menampilkan hint ini saat kedua vault kosong.

### 3d. `scripts/audit-compliance.sh` (v3.5.5 — audit kepatuhan dari LUAR model, R3)

Lahir dari laporan insiden 2026-09-21: tiga session proyek lain berjalan ZERO-compliance (tanpa banner/checkpoint/handoff) dan hanya terdeteksi lewat audit manual user — pelanggaran senyap karena respons tanpa marker tidak menimbulkan error apa pun. Skrip ini TIDAK mempercayai disiplin model: ia membaca artefak di disk dan memberi verdict PASS/WARN/FAIL + exit code (0 = tidak ada FAIL).

```
bash scripts/audit-compliance.sh [--root <project-root>] [--quiet]
```

Checks: **C1** memory/SESSION-STATE.md ada · **C2** hygiene Active-table (H2 — baris terminal di tabel aktif = FAIL) · **C3** staleness worklog-vs-SESSION-STATE (worklog aktif tapi tidak ada checkpoint M1 >30 mnt = WARN — persis signature insiden) · **C4** version sanity instalasi-vs-lock (4c) · **C5** hook R1 ada di tail worklog. Pola pendampingnya (**R2**, infra per-project — bukan bundled): **watcher sentinel** — daemon polling (pola `.zscripts/watcher.sh` v1.6) mendeteksi signature yang sama tiap ~2 mnt dan meng-append COMPLIANCE-ALARM ke tail worklog, anchor yang pasti dibaca session berikutnya. Keduanya menutup celah "non-compliance tak terlihat" dari luar model.

## 4. Prosedur Pasca-Reset (Decision Tree Saat Boot Segar)

1. **Deteksi apakah rollback/degrade terjadi**: gejala cepat — file termutakhir hilang, atau
   `bash scripts/heal-skill.sh --status` melaporkan DRIFT / versi `_meta` mundur.
2. **Drift terdeteksi** ⇒ `bash scripts/heal-skill.sh --check` — heal otomatis dari kanonik atau
   arsip restore; lalu jalankan L1 `--apply` agar sumber ikut segar; `git status` untuk file ekstra
   sisa restore (rsync-heal menghapus ekstra di dalam skill dir, bukan seluruh proyek).
3. **Kanonik ikut hilang** ⇒ heal dari arsip restore (repo.tar membawa `skills/stellar-trail`);
   bila arsip pun basi ⇒ `clawhub update <lock-key> --force` setelah re-login — lock key dilihat
   dari `.clawhub/lock.json` (instalasi flat: `stellar-trail`; owner-scoped:
   `@hoshiyomix/stellar-trail`; hint akurat juga tercetak otomatis oleh heal-skill). Ingat:
   `~/.config` tidak persisten lintas restart — token login harus di-set ulang.
3b. **`clawhub update --force` hanya menyegarkan lokasi owner-scoped** (`skills/@owner/stellar-trail`)
   — instalasi flat yang dibaca platform TIDAK tersentuh (temuan empiris insiden konsumer
   2026-09-22). Setelah update, jalankan `bash skills/stellar-trail/scripts/heal-skill.sh --check`
   — flat sembuh otomatis dari **saudara konvensi**. **Re-arm satu baris pasca-insiden rollback**:
   `clawhub update <lock-key> --force && bash skills/stellar-trail/scripts/heal-skill.sh --check &&
   bash skills/stellar-trail/scripts/vault-sync.sh --apply` (update registry → heal flat dari
   saudara → isi ulang vault). Bila banner versi di respons agent masih tua setelah semua ini,
   lihat Known Risks skill-card: failure mode aktivasi continuation (rule 11).
4. **Tidak terjadi** ⇒ cukup pastikan L1 segar bila hendak berhenti/istirahat.
5. **memory/ ikut hilang** (reset total) ⇒ pulihkan dari handoff terbaru di mount persistent;
   bila tidak ada, jalankan cold-start protocol (Part II seksi 2) — jangan pernah mengklaim
   "tidak ada riwayat" sebelum memeriksa semua kanal.

## 5. Batasan & Etika

- Jangan pernah menjalankan L1 pada lingkungan yang bukan milik user Anda — menimpa arsip restore
  adalah intervensi terhadap infrastruktur; hanya sah bila user yang memiliki environment memintanya.
- `skills/` dulunya konvensi pengecualian packer platform; sejak v3.3.0 arsip L1 menyertakan
  `skills/stellar-trail` via append bedah, dan kanal pemulihannya berlapis: arsip itu (L1) →
  `heal-skill.sh` dari kanonik/arsip (L2) → paket `.skill` + `clawhub update --force` (registry).
- Skrip ini menangani ARSIP RESTORE dan INSTALASI SKILL, bukan menggantikan `git`: commit tetap
  sumber kebenaran untuk diff/status; snapshot hanya untuk pemulihan bencana.

## 6. Bukti Lapangan / Receipts (forensik Task 36–38, 2026-09-19/20)

Temuan terverifikasi yang mendasari arsitektur seksi ini — dicatat sebagai receipt agar
desainnya bisa diaudit, bukan diterima dengan iman:

| Receipt | Bukti terverifikasi | Implikasi desain |
|---|---|---|
| **Task 36 — mekanisme boot** | Klaim "zip menimpa instalasi" GUGUR (`stellar-trail.zip` tak pernah ada di disk/arsip); non-persistensi `skills/` BENAR (boot = wipe + packer mengecualikan `skills/`); heal 2/2 boot nyata + sandbox A/B LOLOS (kontrol tanpa heal tetap rusak, dengan heal pulih) | Boot-heal wajib di hook; kanonik `download/` = jangkar lintas-boot |
| **Task 37 — pin = kunci versi** | `clawhub pin` memblokir `update --force --version` tepat saat dibutuhkan restore/upgrade; `upload/` TERNYATA ossfs kelas-A (bukan kelas-C sebagaimana sempat dikira) | Pin tidak dipakai untuk persistensi; `upload/` sah sebagai lokasi vault |
| **Task 38 — pin = anti-restore (0/6)** | Skill ter-pin + direktori hilang: `update`/`install` = error exit 1; `update --all` = "Skipped … pinned" SENYAP exit 0 (paling berbahaya — tampak sukses); `list` menampilkan zombie "pinned" untuk skill yang tak ada di disk; pin sticky melewati heal. TANPA pin: `update`/`install` = re-download sehat dari registry (jalur restore registry TERBUKTI ADA). Heal kanonik lokal = 0,112 detik offline | Larangan `clawhub pin stellar-trail`; laporan pin semua skill (v3.5.3); registry = fallback jaring terakhir |
| **Task 39 → produk** | Temuan 37–38 dibawa ke produk: `pin_report()` semua skill + `age_info()` sehat-tapi-tua + sumber berlabel — suite 32/32, 5 lapis selaras | Receipt menjadi fitur, bukan sekadar catatan |
| **Task 40 → v3.5.4** | Boot-heal men-deland 3.5.4 di install live saat sesi restart TANPA lock sync (sumber walk-up kanonik bekerja di lapangan); verdict registry "suspicious" (kelas 3.0.0 — disclosed-but-overbroad) TIDAK memblokir promosi latest maupun `update --force` | Rantai multi-sumber tervalidasi produksi; verdict Review-level = sifat protokol yang diungkap jujur, bukan defect |
| **Insiden 2026-09-21 → v3.5.5** | 3 session proyek lain ZERO-compliance — hanya terdeteksi audit manual user; akar: description di system prompt ≠ body termuat (konfirmasi produksi ke-2 failure mode Activation rule 11) + continuation summary tidak membawa pemicu aktivasi (RC2) + pelanggaran tak terlihat (RC3) | R1 hook worklog + R2 sentinel + R3 audit script + R4 description imperatif (v3.5.5) — pertahanan berlapis DI LUAR disiplin model |
| **Insiden konsumer 2026-09-22 → v3.5.7** | Recycle container memulihkan `skills/` dari arsip basi: flat 3.5.5→3.5.4 SENYAP, direktori `@owner` hilang, kedua vault kosong (tak pernah diisi konsumer), `heal --check` BERSIH (manifest-vs-diri-sendiri; lock 3.5.5 tak pernah dibandingkan); `clawhub update --force` sukses tapi HANYA menyegarkan owner-scoped; aktivasi continuation gagal (konfirmasi produksi ke-3 rule 11) — laporan: upload/stellar-trail-feedback-issue.md §6.1–6.8 | Cross-check lock → verdict DOWNGRADED + exit ≠ 0 (jangkar out-of-band); saudara konvensi jadi kandidat sumber heal; hint self-arm vault + versi di README vault; Known Risks aktivasi + re-arm satu baris (§4 3b); gate konsistensi versi packaging |
| **Drill terkontrol 2026-09-22 → v3.5.7 (Task 43)** | Insiden direplikasi end-to-end via `scripts/drill_v357_restore.sh` (sandbox terisolasi, env hermetik): **Drill A** kill `explorer.py` → watcher auto-heal memulihkan dalam **20 detik** (target <60 dtk); **Drill B** restore arsip basi (disk 3.5.4) + lock terkini + SEMUA sumber mati → verdict `DOWNGRADED` + **GAGAL keras exit 1** + nol klaim BERSIH palsu (false-CLEAN insiden TERTUTUP), lalu + saudara owner-scoped segar → heal dari saudara BERLABEL → BERSIH drift nol — **14/14 asersi PASS**; **Drill C** drift disuntikkan ke `explorer.py` deployment → `--ensure` memulihkan md5 dari kanonik + restart server + healthz ok (receipt: explorer.log `sync-fresh`). Temuan sampingan: `pgrep -f watcher.sh` = **false negative** (watcher berjalan sebagai orphan `bash -c` inline, tak tertangkap pola) — cek status watcher WAJIB via `watcher.sh --status` (PIDFILE), bukan pgrep | Mekanisme v3.5.7 kini berstatus TERBUKTI-LAPANGAN-TERKONTROL (bukan lagi teruji-suite saja): tripwire lock + sumber saudara + auto-heal proses + sync kesegaran deployment — masing-masing dengan receipt yang dapat direproduksi |
| **Defek alur rilis 3.5.7 (ditemukan pasca-submit, diperbaiki kanonik)** | 1) `vault-sync.sh`: backtick markdown dalam string `README_BODY` berkutip-ganda dieksekusi bash (noise stderr + placeholder `<direktori-instalasi>` termakan) — fix: escape backtick; 2) disiplin urutan: ubah file kanonik WAJIB disusul `--manifest` sebelum `--apply`/paket (pelanggaran kecil tertangkap verifikasi vault); 3) sed bump versi TIDAK menyentuh pola regex ter-escape (`3\.5\.6`) di suite — 18 FAIL semuanya bug fixture; 4) asersi suite yang bergantung state lingkungan nyata (T6: vault kelas-A masih tua) harus hermetik sejak awal | Suite +2 asersi regresi (109/109); T6 hermetik; paket final SHA cc9dbd38… — pelajaran: verifikasi pasca-setiap-edit, bukan hanya pasca-batch |
| **Audit pasca-reset platform 2026-09-22 22:28 UTC (Task 43, sesi 26)** | Container mati ~16 jam (sejak ~06:29 UTC) → boot 22:27:57; restore arsip platform membawa kondisi final kemarin secara UTUH (mtime terawetkan tar). Audit jendela 6 jam: **NOL rollback versi** — 3.5.7 selamat di live flat + kanonik + kedua vault; lock 3.5.5 (out-of-band; disk ≥ lock = sehat, bukan DOWNGRADED); watcher + explorer bangkit otomatis (pid baru, healthz ok, `fresh` vs kanonik ok); repo.tar disegarkan boot (2773 entri). Satu-satunya temuan: boot-heal force melapor **GAGAL — 1 rusak** (`environment-resilience.md` vs manifest) — **bukan kerusakan reset**: edit receipt pamungkas kemarin (05:50:06) mendarat SETELAH manifest final (05:47:12) + paket (05:47:35) + vault-sync, meninggalkan kanonik inkonsisten-manifest; reset hanya mengungkapnya. Remediasi: receipt ini → `--manifest` → propagate live → `vault-sync --apply` → rebuild paket | Dua pelajaran: (1) verifikasi wajib PASCA setiap edit **termasuk edit terakhir** — klaim "semua selaras" di checkpoint kemarin berasal dari verifikasi pra-edit-pamungkas; (2) boot-heal force-mode terbukti di lapangan (tak terencana) sebagai penangkap manifest-lag — GAGAL kerasnya adalah deteksi yang BENAR, bukan false alarm |
| **Hardening v3.5.8 dari temuan audit pasca-reset (Task 44, 2026-09-23)** | Dua lapis lahir dari insiden manifest-lag 2026-09-22: (1) **source self-verify** di `heal-skill.sh` — kandidat sumber bermanifest wajib lolos pohon ≡ manifest-nya sendiri sebelum dipilih (sumber racun dilewati → failover vault kelas-A; semua kandidat eligan racun = GAGAL keras; env override dihormati + peringatan keras; sumber tanpa manifest tetap eligibel); (2) **gate pohon ≡ manifest** di packaging — build GAGAL exit 1 sebelum zip ditulis bila kanonik ≠ manifest dua arah (kunci kelas jebakan "edit tanpa regen") | Failover menggantikan kegagalan: pertahanan terakhir harus kebal terhadap keracunan SUMBERNYA sendiri; gerbang build = titik cek otomatis terakhir sebelum kerusakan menyebar ke konsumer |

**Penjelasan (ID):** Mengapa ada seksi ini di skill memory? Karena protokol memory hanya sekuat
lingkungannya: SESSION-STATE dan MEMORY tidak berarti bila direktorinya sendiri di-rollback ke masa
lalu oleh platform. Pengalaman empiris menunjukkan rollback diam-diam adalah mode kegagalan nyata —
dan solusinya tidak butuh alat canggih, cukup disiplin berlapis yang murah dan teruji: segarkan
sumbernya, sembuhkan instalasinya, simpan aslinya untuk undo. Lapis shadow backup yang pernah ada
justru membuktikan prinsipnya dari arah sebaliknya — backup yang restore-nya tidak pernah teruji
menambah mode kegagalan alih-alih menguranginya, dan akhirnya dihapus. Semua intervensi infrastruktur
harus eksplisit dan bisa di-undo; penjaga yang diam-diam mengubah platform adalah penjaga yang
berubah jadi risiko.
