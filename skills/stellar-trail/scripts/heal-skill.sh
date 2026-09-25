#!/usr/bin/env bash
# ============================================================================
# heal-skill.sh — SELF-HEAL INSTALASI stellar-trail (bundled sejak v3.3.0)
# v3.6.2 (Task 60, 2026-09-25 — laporan konsumer sandbox lain, v3.6.1
#        fresh-install + explorer): FALLBACK MANUAL TERAKHIR = GITHUB.
#        Rute lama `clawhub update --force` adalah dead route sejak registry
#        menyuspend akun publisher (Task 58, 2026-09-24 — appeal pending):
#        konsumer yang kehabisan semua sumber lokal mendapat instruksi yang
#        mustahil dijalankan. Kini hint manual = pasang ulang git-clone +
#        verify (rute terbukgi Task 59: 25/25, tanpa login, nol eksekusi
#        remote); clawhub update tetap dicetak sebagai ALTERNATIF KONDISIONAL
#        bila registry pulih. Vault self-arm hint (v3.5.7) tidak berubah.
# v3.5.8: SOURCE SELF-VERIFY (temuan audit pasca-reset 2026-09-22, sesi 26):
#        kandidat sumber yang membawa manifest rilis WAJIB lolos verifikasi
#        internal (pohon ≡ manifest-nya sendiri) sebelum dipilih — sumber
#        racun (insiden lapangan: kanonik bawa manifest basi akibat edit
#        TANPA regen manifest menang seleksi versi, disalin setia, heal
#        GAGAL pasca-reset justru saat paling dibutuhkan) kini DILEWATI dan
#        kandidat sehat berikutnya (mis. vault kelas-A) mengambil alih;
#        seluruh kandidat eligan racun = GAGAL keras (bukan menyalin
#        kerusakan); override env STELLAR_CANONICAL tetap dihormati tapi
#        diberi peringatan keras; sumber TANPA manifest tetap eligibel
#        (perilaku v3.5.7 utuh — verifikasi sumber-basi tetap menunggu).
# v3.5.7: LOCK-AWARE + SAUDARA KONVENSI + HINT SELF-ARM (jawaban insiden
#        konsumer 2026-09-22 — upload/stellar-trail-feedback-issue.md §6.1/§6.3/§6.8):
#        (1) CROSS-CHECK LOCK: versi skill INI di .clawhub/lock.json
#            dibandingkan vs disk (rilis manifest, fallback _meta) —
#            lock > disk = DOWNGRADED (signature rollback arsip-restore:
#            lock.json TIDAK ikut di-restore arsip skills/, jangkar
#            out-of-band termurah) → verdict DRIFT + hint clawhub update;
#            pasca-heal masih < lock = GAGAL exit 1 — jebakan false-CLEAN
#            "sehat-tapi-tua" (manifest-vs-diri-sendiri) tertutup;
#        (2) KANDIDAT SUMBER SAUDARA KONVENSI: skills/stellar-trail ↔
#            skills/@owner/stellar-trail saling menjadi kandidat (kasus
#            nyata: clawhub update --force hanya menyegarkan owner-scoped,
#            instalasi flat yang dibaca platform tetap tua) — tunduk pada
#            anti-timpa-baru + pemilihan berbasis versi yang sama;
#        (3) HINT SELF-ARM VAULT: kedua vault kelas-A kosong → satu baris
#            hint vault-sync.sh --apply (skrip itu dapat dijalankan
#            LANGSUNG dari direktori instalasi — kanonik = parent scripts/).
# v3.5.4: VAULT-AWARE + VERSION-AWARE (adopsi skill-vault, Task 35/41):
#        (1) kandidat sumber kini mencakup VAULT kelas-A —
#            /home/sync/skill-vault/stellar-trail (override: STELLAR_VAULT)
#            dan <proyek>/upload/skill-vault/stellar-trail (ossfs) — diisi
#            oleh scripts/vault-sync.sh pada write yang sama dengan publish;
#        (2) VERSION-ASSERT anti-timpa-baru: sumber yang versinya LEBIH
#            TUA dari instalasi DILEWATI — heal tidak pernah menurunkan
#            versi instalasi secara senyap (menutup celah downgrade-basi);
#        (3) pemilihan sumber BERBASIS VERSI (tertinggi menang; tie-break
#            urutan lama: walk-up 2/3/4 → vault → platform) — kanonik segar
#            tetap menang sederajat versinya; env STELLAR_CANONICAL tetap
#            override absolut tanpa assert (intensi eksplisit operator);
#        (4) vault pemenang dilaporkan BERLABEL + --status menampilkan
#            baris vault; verdict drift & exit code TIDAK berubah saat
#            vault absen (graceful — perilaku v3.5.3 utuh).
# v3.5.3: PIN-AWARE + info usia (audit Task 37/38/39):
#        (1) LAPORAN PIN SEMUA skill di .clawhub/lock.json — unpinned atau
#            PINNED(reason); pinned = WARN (memblokir clawhub update/install
#            skill itu, dan di-skip SENYAP oleh update --all) + hint unpin;
#            verdict drift & exit code TIDAK berubah (heal pin-agnostic);
#        (2) info "sehat-tapi-tua": instalasi BERSIH vs manifest sendiri
#            tapi kanonik lebih baru → hint upgrade disengaja --force
#            (penangkap edge restore-basi Task 36; heal ≠ upgrade by design);
#        (3) sumber heal BERLABEL (env / walk-up-N / platform / arsip) +
#            helper find_root() dipakai bersama hint & laporan pin —
#            mekanisme multi-sumber, urutan & prioritas TIDAK berubah.
# v3.5.2: LOCATION-AWARE — dua konvensi lokasi install clawhub:
#        (a) legacy flat    : skills/stellar-trail          (lock key "stellar-trail")
#        (b) owner-scoped   : skills/@owner/stellar-trail   (lock key "@owner/stellar-trail",
#                            clawhub CLI >= 0.23.3) — walk-up sumber kini multi-level
#                            (2/3/4 level), hint clawhub memakai lock key AKTUAL,
#                            sourceless check GAGAL KERAS (exit 1, dulu WARN senyap),
#                            _meta.json/origin.json dibuat ulang bila absen (boot-wipe),
#                            sumber tar memakai relpath layout aktual.
# v3.3.1: fallback deteksi drift BERBASIS SUMBER saat manifest ikut hancur
#        (insiden nyata: assets/ dihapus → integrity.sha256 lenyap → --check
#        dulunya no-op; kini --check membandingkan instalasi dua arah terhadap
#        sumber sehat bila manifest tidak tersedia)
#
# MASALAH YANG DISEMBUHKAN (bukti empiris 2026-09-17, insiden 07:37 UTC):
#   Lingkungan container yang bisa di-reset dapat memulihkan skills/ dari
#   arsip restore / salinan cache LAMA — instalasi skill terdegradasi
#   diam-diam: versi _meta.json mundur, file hilang, aset lenyap.
#   Memulihkannya: heal multi-sumber dari lokal (kanonik → vault kelas-A →
#   arsip restore → saudara konvensi); bila SEMUA sumber lokal habis →
#   pasang ulang via GitHub git-clone + verify (v3.6.2 — rute terbukgi
#   Task 59; clawhub update --force hanya bila registry pulih).
#
# SOLUSI — empat kemampuan dalam satu skrip (opt-in, 100% lokal bila mungkin):
#   1. VERIFIKASI: manifest SHA-256 (assets/integrity.sha256 + integrity.version,
#      dibangun saat rilis via --manifest) membuktikan file mana yang
#      hilang/rusak/ekstra — tanpa sumber eksternal; plus cross-check versi
#      _meta.json vs versi rilis (persis signature degrade insiden asli)
#      dan cross-check LOCK clawhub (v3.5.7: lock > disk = DOWNGRADED —
#      lock.json tak ikut di-restore arsip skills/, jangkar out-of-band).
#   2. PERBAIKAN multi-sumber berurut (kandidat pemenang dilaporkan BERLABEL
#      sejak v3.5.3 — urutan tidak berubah):
#        a. STELLAR_CANONICAL (env)
#        b. <proyek>/download/stellar-trail (deteksi walk-up 2/3/4 level dari
#           lokasi skill — mendukung layout flat DAN owner-scoped, v3.5.2)
#        c. /home/z/my-project/download/stellar-trail (default platform)
#        c2. lokasi SAUDARA KONVENSI (skills/<slug> ↔ skills/@owner/<slug>,
#           v3.5.7 — clawhub update hanya menyegarkan owner-scoped)
#        d. subtree instalasi di arsip restore sesuai layout aktual
#           (STELLAR_RESTORE_TAR, default /home/sync/repo.tar)
#        e. hint terakhir (v3.6.2, Task 60): pasang ulang via GitHub
#           git-clone + verify (rute terbukgi Task 59; clawhub update
#           <lock-key> --force hanya dicatat sbg alternatif BILA registry
#           pulih — suspended 2026-09-24, appeal pending)
#   3. NORMALISASI metadata: _meta.json & .clawhub/origin.json dipatch
#      versinya agar konsisten dgn konten hasil heal — identitas install
#      clawhub (ownerId, installedAt, fingerprint) tidak pernah ditimpa;
#      bila keduanya ABSEN (kasus skills/ ter-wipe total saat boot), file
#      minimal dibuat ulang (v3.5.2) agar instalasi tetap dikenali clawhub.
#   4. LAPORAN PIN & USIA (v3.5.3): state pin SEMUA skill di lock clawhub —
#      pin = kunci versi kanal update (memblokir update/install skill itu,
#      update --all melewatkannya SENYAP tanpa error) maka PINNED dilaporkan
#      sbg WARN + hint unpin; TANPA mempengaruhi verdict drift / exit code
#      (pin tidak menyentuh file skill — heal tetap pin-agnostic). Plus
#      info sehat-tapi-tua bila kanonik lebih baru dari rilis terinstal.
#
# LOKASI TARGET: default = direktori skill tempat skrip ini berada
#   (self-locating — skrip menyembuhkan paketnya sendiri, flat ataupun
#   owner-scoped). Override dengan --dir <path> untuk menyembuhkan
#   instalasi stellar-trail lain.
#
# EXEC BIT: hasil heal TIDAK diberi +x (0644) — identik dengan perilaku
#   clawhub install/update dari registry. Seluruh invokasi protokol memang
#   via `bash`/`python3` (exec-bit-independent by design — SKILL.md seksi
#   Bundled scripts).
#
# PERINTAH:
#   bash scripts/heal-skill.sh --status     # laporan versi + layout + drift
#                                           # + pin (SEMUA skill) + info usia,
#                                           # TANPA aksi
#   bash scripts/heal-skill.sh --check      # deteksi drift; heal bila ada
#                                           # (default) — pin dilaporkan juga
#   bash scripts/heal-skill.sh --force      # heal tanpa deteksi
#   bash scripts/heal-skill.sh --manifest   # regenerasi manifest (SAAT RILIS,
#                                           # dijalankan di salinan kanonik)
#   bash scripts/heal-skill.sh --dir <path> <mode>   # target instalasi lain
#
# Override env: STELLAR_CANONICAL, STELLAR_RESTORE_TAR, STELLAR_PLATFORM_PROJECT
#              (default /home/z/my-project), HEAL_TMP
# Kebutuhan: bash, coreutils (sha256sum, find, sed, awk), tar; rsync untuk heal;
#            python3 OPSIONAL (hanya laporan pin — dilewati anggun bila absen).
# Exit: 0 = bersih / berhasil di-heal · 1 = drift bertahan / gagal heal /
#       VERIFIKASI MUSTAHIL (tanpa manifest & tanpa sumber — v3.5.2) ·
#       2 = salah pakai
# ============================================================================

say() { echo "[heal-skill] $*"; }

# ---------------------------------------------------------------------------
# Parse argumen dulu — --dir boleh di mana saja; mode default --check
# ---------------------------------------------------------------------------
MODE="check"
SKILL_DIR=""
while [ $# -gt 0 ]; do case "$1" in
    --status|--check|--force|--manifest) MODE="${1#--}"; shift;;
    --dir) SKILL_DIR="${2:-}"; shift 2;;
    -h|--help) cat <<'HELP'
heal-skill.sh — self-heal instalasi stellar-trail

pakai: bash scripts/heal-skill.sh --status | --check | --force | --manifest [--dir <path>]

  --status     laporan versi + layout + drift + pin (SEMUA skill di lock) + info usia, TANPA aksi
  --check      deteksi drift; heal bila ada (default) — laporan pin ikut tercetak
  --force      heal tanpa deteksi
  --manifest   regenerasi manifest (SAAT RILIS, di salinan kanonik)
  --dir <path> target instalasi stellar-trail lain

sumber perbaikan (v3.5.7 — pemilihan berbasis versi, berlabel): env STELLAR_CANONICAL
(override absolut) → kanonik walk-up download/stellar-trail → vault kelas-A
(/home/sync/skill-vault · upload/skill-vault — diisi scripts/vault-sync.sh) →
platform default → saudara konvensi (skills/stellar-trail ↔ skills/@owner/
stellar-trail, v3.5.7) → arsip restore (STELLAR_RESTORE_TAR) → hint manual
pasang ulang via GitHub git-clone + verify (v3.6.2, Task 60 — rute terbukgi
Task 59; clawhub update --force hanya bila registry pulih: suspended
2026-09-24). Sumber lebih tua dari instalasi DILEWATI
(anti-timpa-baru). Cross-check lock clawhub: lock > disk = DOWNGRADED + hint
pasang ulang; pasca-heal masih < lock = GAGAL exit 1. Vault kelas-A kosong → hint
self-arm vault-sync --apply. pin TIDAK mempengaruhi verdict drift / exit code.
HELP
    exit 0;;
    *) echo "argumen tidak dikenal: $1 (pakai --help)" >&2; exit 2;;
esac; done

# Self-locate: direktori skill = parent dari scripts/ tempat skrip ini hidup
if [ -z "$SKILL_DIR" ]; then
    SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
else
    # --dir boleh menunjuk path yang BELUM ADA (kasus rebuild boot-wipe:
    # instalasi ter-wipe total, dev.sh/delegate memanggil --force --dir).
    # Mode penyembuhan (check/force) membuat parent chain-nya sendiri;
    # mode laporan (status/manifest) tetap strict tanpa menyentuh FS.
    _dp="$(dirname "$SKILL_DIR")"
    case "$MODE" in
        check|force)
            mkdir -p "$_dp" 2>/dev/null \
                || { echo "[heal-skill] --dir tidak valid: tidak bisa membuat $_dp" >&2; exit 2; }
            ;;
    esac
    [ -d "$_dp" ] || { echo "[heal-skill] --dir tidak valid: parent $_dp tidak ada" >&2; exit 2; }
    SKILL_DIR="$(cd "$_dp" && pwd)/$(basename "$SKILL_DIR")"
fi
MANIFEST="$SKILL_DIR/assets/integrity.sha256"
VERSIONF="$SKILL_DIR/assets/integrity.version"
TAR_PATH="${STELLAR_RESTORE_TAR:-/home/sync/repo.tar}"
PLATFORM_PROJECT="${STELLAR_PLATFORM_PROJECT:-/home/z/my-project}"
REAL_SRC=""; TAR_TMP=""; SRC_LABEL=""

meta_version() {  # versi dari _meta.json (layout terinstal clawhub)
    grep -oE '"version": *"[0-9]+\.[0-9]+\.[0-9]+"' "$1/_meta.json" 2>/dev/null \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}
card_version() {  # versi dari skill-card.md (salinan kanonik/paket rilis)
    # anchor '^## Skill Version': frasa "skill version" bisa muncul di paragraf
    # naratif deskripsi (mis. fitur guardian card) — jangan biarkan menipu
    grep -A3 -i '^## *Skill Version' "$1/skill-card.md" 2>/dev/null \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}
release_version() { [ -f "$VERSIONF" ] && tr -d '[:space:]' < "$VERSIONF"; }

# ---------------------------------------------------------------------------
# Layout helpers (v3.5.2): dua konvensi lokasi install clawhub —
#   flat         : <root>/skills/stellar-trail        (lock key "stellar-trail")
#   owner-scoped : <root>/skills/@owner/stellar-trail (lock key "@owner/stellar-trail",
#                 clawhub CLI >= 0.23.3 memasang fresh install di sini)
# ---------------------------------------------------------------------------
install_rel() {  # relpath instalasi thd root proyek (parent dir "skills/");
                  # kosong bila dijalankan dari salinan sumber (bukan instalasi)
    local d="$SKILL_DIR" base
    while [ "$d" != "/" ] && [ "$(basename "$d")" != "skills" ]; do
        d="$(dirname "$d")"
    done
    [ "$(basename "$d")" = "skills" ] || return 0
    base="$(dirname "$d")"
    case "$SKILL_DIR" in
        "$base"/*) echo "${SKILL_DIR#"$base"/}";;
        *)         return 0;;
    esac
}

find_root() {  # v3.5.3: ancestor terdekat dari SKILL_DIR yang punya
               # .clawhub/lock.json — dipakai bersama oleh hint & laporan pin
    local d="$SKILL_DIR"
    while [ "$d" != "/" ]; do
        d="$(dirname "$d")"
        if [ -f "$d/.clawhub/lock.json" ]; then echo "$d"; return 0; fi
    done
    return 1
}

heal_hint() {  # v3.6.2 (Task 60): fallback manual terakhir = pasang ulang via
               # GitHub git-clone + verify — rute terbukgi Task 59 (25/25,
               # tanpa login, nol eksekusi remote). clawhub update --force
               # hanya dicetak sbg alternatif BILA registry pulih (suspended
               # 2026-09-24, appeal pending), memakai lock key AKTUAL
               # instalasi ini (dibaca dari .clawhub/lock.json).
    local root rel key claw="clawhub update @hoshiyomix/stellar-trail --force"
    local target="${SKILL_DIR:-skills/stellar-trail}"
    if root="$(find_root)"; then
        case "$SKILL_DIR" in
            "$root"/skills/*)
                rel="${SKILL_DIR#"$root"/skills/}"
                for key in "$rel" "stellar-trail" "@hoshiyomix/stellar-trail"; do
                    grep -Fq "\"$key\"" "$root/.clawhub/lock.json" 2>/dev/null || continue
                    claw="clawhub update $key --force"; break
                done
                ;;
        esac
    fi
    echo "git clone --depth 1 https://github.com/hoshiyomiX/stellar-trail.git /tmp/st-src && rm -rf '$target' && cp -r /tmp/st-src/skills/stellar-trail '$target' && cd '$target' && sha256sum -c assets/integrity.sha256 [rute GitHub terbukgi · $claw hanya bila registry pulih]"
}

lock_version() {  # v3.5.7 §6.1: versi skill INI di .clawhub/lock.json
                  # (kosong bila untracked / key tak ada / tak terbaca)
    local root rel key v
    root="$(find_root)" || return 0
    case "$SKILL_DIR" in
        "$root"/skills/*) rel="${SKILL_DIR#"$root"/skills/}";;
        *) return 0;;
    esac
    for key in "$rel" "stellar-trail" "@hoshiyomix/stellar-trail"; do
        grep -Fq "\"$key\"" "$root/.clawhub/lock.json" 2>/dev/null || continue
        if command -v python3 >/dev/null 2>&1; then
            v="$(python3 - "$root/.clawhub/lock.json" "$key" <<'PY' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1]) as fh:
        meta = (json.load(fh).get("skills") or {}).get(sys.argv[2]) or {}
    print(meta.get("version", ""))
except Exception:
    print("")
PY
)"
        else
            # fallback grep (JSON satu-baris/pretty): versi pertama dlm jendela
            # kecil setelah key — false-positive terburuk = alarm benign
            v="$(grep -A8 -F "\"$key\"" "$root/.clawhub/lock.json" 2>/dev/null \
                | grep -oE '"version": *"[0-9]+\.[0-9]+\.[0-9]+"' | head -1 \
                | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
        fi
        [ -n "$v" ] && { echo "$v"; return 0; }
    done
    return 0
}

# ---------------------------------------------------------------------------
# Laporan pin (v3.5.3, audit Task 38): state pin SEMUA skill di lock.
# Pin = kunci versi pada kanal update clawhub: memblokir update/install skill
# itu DAN membuat `update --all` melewatkannya SENYAP (exit 0 tanpa error).
# Pin TIDAK menyentuh file skill → verdict drift & exit code TIDAK berubah.
# $1 = status (blok "pin :" di --status) | check (baris say ringkas/WARN)
# ---------------------------------------------------------------------------
pin_report() {
    local root lock
    if ! root="$(find_root)"; then
        [ "$1" = "status" ] && echo "pin       : (tanpa .clawhub/lock.json — instalasi untracked)"
        return 0
    fi
    lock="$root/.clawhub/lock.json"
    if ! command -v python3 >/dev/null 2>&1; then
        [ "$1" = "status" ] && echo "pin       : (python3 tidak tersedia — cek pin dilewati; lock: $lock)"
        return 0
    fi
    python3 - "$lock" "$1" <<'PY' || true
import json, sys
mode = sys.argv[2]
try:
    with open(sys.argv[1]) as fh:
        skills = json.load(fh).get("skills") or {}
except Exception as exc:
    if mode == "status":
        print("pin       : (lock tidak terbaca: %s)" % exc)
    sys.exit(0)
if not skills:
    if mode == "status":
        print("pin       : (lock kosong — tidak ada skill tracked)")
    sys.exit(0)
if mode == "status":
    for key in sorted(skills):
        meta = skills[key]
        ver = meta.get("version", "?")
        if meta.get("pinned"):
            reason = meta.get("pinReason") or "tanpa reason"
            print("pin       : \u26a0 %s v%s — PINNED (%s) · blokir update/install & --all skip senyap · unpin: clawhub unpin %s"
                  % (key, ver, reason, key))
        else:
            print("pin       : %s v%s — unpinned" % (key, ver))
else:
    pinned = [k for k in sorted(skills) if skills[k].get("pinned")]
    if pinned:
        for key in pinned:
            reason = skills[key].get("pinReason") or "tanpa reason"
            print("[heal-skill] pin: \u26a0 %s PINNED (%s) — clawhub update/install %s DIBLOKIR & update --all skip senyap; unpin dulu: clawhub unpin %s"
                  % (key, reason, key, key))
    else:
        print("[heal-skill] pin: %d skill unpinned (%s)"
              % (len(skills), ", ".join(sorted(skills))))
PY
}

# ---------------------------------------------------------------------------
# Info usia (v3.5.3, edge Task 36): instalasi BERSIH vs manifest sendiri
# tapi kanonik lebih baru → penangkap restore-basi yang lolos --check.
# Remedy tetap disengaja (--force) — disiplin heal ≠ upgrade (D22).
# ---------------------------------------------------------------------------
version_lt() {  # $1 < $2 pada pola x.y.z (semver longgar)
    local a1=0 a2=0 a3=0 b1=0 b2=0 b3=0
    IFS=. read -r a1 a2 a3 <<< "${1:-0}"
    IFS=. read -r b1 b2 b3 <<< "${2:-0}"
    [ "${a1:-0}" -lt "${b1:-0}" ] && return 0
    [ "${a1:-0}" -gt "${b1:-0}" ] && return 1
    [ "${a2:-0}" -lt "${b2:-0}" ] && return 0
    [ "${a2:-0}" -gt "${b2:-0}" ] && return 1
    [ "${a3:-0}" -lt "${b3:-0}" ]
}

canonical_version() {  # versi kanonik terdekat — probe RINGAN, tanpa ekstraksi tar
    local c p2 p3 p4 v
    p2="$(dirname "$SKILL_DIR")"
    p3="$(dirname "$p2")"
    p4="$(dirname "$p3")"
    for c in "${STELLAR_CANONICAL:-}" \
             "$p2/../download/stellar-trail" \
             "$p3/../download/stellar-trail" \
             "$p4/../download/stellar-trail" \
             "$PLATFORM_PROJECT/download/stellar-trail"; do
        [ -n "$c" ] || continue
        [ -f "$c/skill-card.md" ] || continue
        v="$(card_version "$c")"
        [ -n "$v" ] && { echo "$v"; return 0; }
    done
    return 0
}

age_info() {  # $1 = status (echo berlabel) | say (baris [heal-skill])
    local iv cv
    iv="$(release_version)"; [ -n "$iv" ] || return 0
    cv="$(canonical_version)"; [ -n "$cv" ] || return 0
    version_lt "$iv" "$cv" || return 0
    if [ "$1" = "status" ]; then
        echo "info      : instalasi sehat tapi LEBIH TUA dari kanonik (rilis $iv < kanonik $cv) — upgrade disengaja: bash scripts/heal-skill.sh --force (heal ≠ upgrade by design)"
    else
        say "info: instalasi sehat tapi LEBIH TUA dari kanonik (rilis $iv < kanonik $cv) — upgrade disengaja: --force (heal ≠ upgrade by design)"
    fi
}

vault_hint() {  # v3.5.7 §6.3: kedua vault kelas-A kosong → hint self-arm konsumer
    local c any=""
    for c in "${STELLAR_VAULT:-/home/sync/skill-vault/stellar-trail}" "$PLATFORM_PROJECT/upload/skill-vault/stellar-trail"; do
        [ -f "$c/skill-card.md" ] && any=1
    done
    [ -z "$any" ] || return 0
    if [ "$1" = "status" ]; then
        echo "hint      : vault kelas-A kosong — self-arm: bash scripts/vault-sync.sh --apply (dijalankan dari instalasi ini)"
    else
        say "hint: vault kelas-A kosong — self-arm: bash scripts/vault-sync.sh --apply (dari instalasi ini)"
    fi
}

# ---------------------------------------------------------------------------
# Deteksi drift (set: DRIFT 0|1, DRIFT_DESC, MISSING/DAMAGED/EXTRA/VDRIFT,
# MMISS=1 bila manifest tak ada). Sumber kebenaran = manifest rilis.
# ---------------------------------------------------------------------------
detect_drift() {
    DRIFT=0; DRIFT_DESC=""; MISSING=0; DAMAGED=0; EXTRA=0; VDRIFT=0; MMISS=0; SRC_BASED=0; DOWNGRADED=0
    if [ ! -f "$MANIFEST" ]; then
        MMISS=1
        # fallback (v3.3.1): manifest bisa ikut hancur bersama degrade (insiden
        # nyata: assets/ dihapus). Bila ada sumber sehat, bandingkan DUA ARAH
        # terhadap sumber — tetap terdeteksi tanpa manifest.
        resolve_source || return 0
        SRC_BASED=1
        local f rel n=0 diffs="" e erel m=0 ex=""
        while IFS= read -r f; do
            rel="${f#"$REAL_SRC"/}"
            [ "$rel" = "skill-card.md" ] && continue
            if [ ! -f "$SKILL_DIR/$rel" ] || ! cmp -s "$f" "$SKILL_DIR/$rel"; then
                n=$((n+1)); [ $n -le 5 ] && diffs="$diffs$rel, "
            fi
        done < <(find "$REAL_SRC" -type f | sort)
        while IFS= read -r e; do
            erel="${e#"$SKILL_DIR"/}"
            case "$erel" in
                _meta.json|.clawhub/*|skill-card.md|assets/integrity.sha256|assets/integrity.version) continue;;
            esac
            if [ ! -f "$REAL_SRC/$erel" ]; then
                m=$((m+1)); [ $m -le 3 ] && ex="$ex$erel, "
            fi
        done < <(find "$SKILL_DIR" -type f 2>/dev/null | sort)
        [ -n "$TAR_TMP" ] && { rm -rf "$TAR_TMP"; TAR_TMP=""; }
        local vm vw
        vm="$(meta_version "$SKILL_DIR")"; vw="$(card_version "$REAL_SRC")"
        if [ $((n+m)) -gt 0 ]; then DRIFT=1; DRIFT_DESC="${n} beda/hilang, ${m} ekstra (vs sumber)${diffs:+ — ${diffs%, }}${ex:+ · ekstra: ${ex%, }}"; fi
        if [ -n "$vm" ] && [ -n "$vw" ] && [ "$vm" != "$vw" ]; then
            DRIFT=1; DRIFT_DESC="${DRIFT_DESC:+$DRIFT_DESC; }versi _meta $vm != sumber $vw"
        fi
        # v3.5.7: cross-check lock berlaku juga tanpa manifest (§6.1)
        local lv iv
        lv="$(lock_version)"; iv="$vm"; [ -z "$iv" ] && iv="$(release_version)"
        if [ -n "$lv" ] && [ -n "$iv" ] && version_lt "$iv" "$lv"; then
            DOWNGRADED=1; DRIFT=1
            DRIFT_DESC="${DRIFT_DESC:+$DRIFT_DESC; }DOWNGRADED (lock $lv > disk $iv) — jalankan: $(heal_hint)"
        fi
        return 0
    fi

    # 1) verifikasi checksum seluruh file terdaftar.
    #    File hilang memancarkan DUA baris ("No such file" + "FAILED open or
    #    read") — maka hitung HILANG langsung dari daftar manifest (pasti satu
    #    per file), dan RUSAK hanya dari baris FAILED yang bukan open-or-read.
    local out line p
    out="$(cd "$SKILL_DIR" && LC_ALL=C sha256sum -c assets/integrity.sha256 2>&1)" || true
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        [ -f "$SKILL_DIR/$p" ] || MISSING=$((MISSING+1))
    done < <(awk '{print $2}' "$MANIFEST")
    while IFS= read -r line; do
        case "$line" in
            *"No such file"*|*"FAILED open or read"*) ;;
            *": FAILED"*) DAMAGED=$((DAMAGED+1));;
        esac
    done <<< "$out"

    # 2) file ekstra di instalasi yang tak dikenal manifest (kecuali allowlist
    #    metadata clawhub + artefak python)
    local listed rel
    listed="$(awk '{print $2}' "$MANIFEST")"
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        case "$rel" in
            assets/integrity.sha256|skill-card.md|_meta.json|.clawhub/*) continue;;
            *__pycache__/*|*.pyc) continue;;
        esac
        printf '%s\n' "$listed" | grep -qx -- "$rel" || EXTRA=$((EXTRA+1))
    done < <(cd "$SKILL_DIR" && find . -type f | sed 's|^\./||')

    # 3) cross-check versi: _meta.json (install) vs versi rilis (manifest)
    #    — signature persis insiden degrade: _meta mundur, konten tertukar
    local vm rv
    vm="$(meta_version "$SKILL_DIR")"; rv="$(release_version)"
    if [ -n "$vm" ] && [ -n "$rv" ] && [ "$vm" != "$rv" ]; then VDRIFT=1; fi

    # 4) v3.5.7 cross-check LOCK (§6.1, insiden konsumer 2026-09-22):
    #    lock.json TIDAK ikut di-restore arsip skills/ → lock > disk =
    #    signature rollback arsip-restore; menutup jebakan false-CLEAN
    #    sehat-tapi-tua (manifest-vs-diri-sendiri) saat semua sumber mati.
    local lv iv
    lv="$(lock_version)"; iv="$rv"; [ -z "$iv" ] && iv="$vm"
    if [ -n "$lv" ] && [ -n "$iv" ] && version_lt "$iv" "$lv"; then
        DOWNGRADED=1
    fi

    local parts=""
    [ "$MISSING"  -gt 0 ] && parts="$parts ${MISSING} hilang ·"
    [ "$DAMAGED"  -gt 0 ] && parts="$parts ${DAMAGED} rusak ·"
    [ "$EXTRA"    -gt 0 ] && parts="$parts ${EXTRA} ekstra ·"
    [ "$VDRIFT"   -eq 1 ] && parts="$parts versi _meta ${vm} != rilis ${rv} ·"
    [ "$DOWNGRADED" -eq 1 ] && parts="$parts DOWNGRADED (lock ${lv} > disk ${iv}) — jalankan: $(heal_hint) ·"
    if [ -n "$parts" ]; then DRIFT=1; DRIFT_DESC="${parts% ·}"; fi
}

# ---------------------------------------------------------------------------
# Resolusi sumber sehat — sejak v3.5.4: VAULT-AWARE + pemilihan BERBASIS
# VERSI dengan anti-timpa-baru (detail di blok komentar fungsi); kandidat
# pemenang tetap dilaporkan BERLABEL. env = override absolut; e = hint saja.
# ---------------------------------------------------------------------------
# Verifikasi kesehatan internal sumber (v3.5.8) — kandidat yang membawa
# manifest rilis harus cocok pohon ≡ manifest-nya SENDIRI sebelum dipakai.
# Insiden lapangan 2026-09-22: kanonik bawa manifest basi (edit receipt
# 05:50 pasca manifest final 05:47) lolos seleksi versi lalu disalin setia
# → boot-heal GAGAL pasca-reset. Sumber racun kini dilewati → failover ke
# kandidat sehat berikutnya. Sumber TANPA manifest tetap eligibel (return 0
# — perilaku lama utuh; verifikasi sumber-basi dua arah tetap di do_heal).
# ---------------------------------------------------------------------------
source_self_ok() {
    local d="$1" h f
    [ -f "$d/assets/integrity.sha256" ] || return 0
    while IFS=' ' read -r h f; do
        [ -n "$h" ] || continue
        if [ ! -f "$d/$f" ] || \
           [ "$(sha256sum "$d/$f" 2>/dev/null | cut -d' ' -f1)" != "$h" ]; then
            return 1
        fi
    done < "$d/assets/integrity.sha256"
    return 0
}

resolve_source() {
    local c i v iv best_v="" best_c="" best_l="" p2 p3 p4
    POISONED=""   # v3.5.8: jejak kandidat racun yang dilewati (pelaporan)
    # walk-up multi-level (v3.5.2): 2/3/4 level dari lokasi skill — flat
    # (skills/<slug>) maupun owner-scoped (skills/@owner/<slug>); v3.5.1 hanya
    # mem-probe 2 level dan patah persis di layout owner-scoped.
    # Kandidat dibangun dari ancestor yang DIJAMIN ada (parent SKILL_DIR sudah
    # divalidasi/dibuat saat parse --dir) — komponen ".." yang menempel pada
    # path yang belum ada di FS tidak ter-resolve, maka JANGAN pernah
    # menempelkan "../.." pada SKILL_DIR mentah (kasus rebuild boot-wipe:
    # target instalasi belum dibuat).
    p2="$(dirname "$SKILL_DIR")"   # .../skills/@owner | .../skills
    p3="$(dirname "$p2")"          # .../skills        | .../<root>
    p4="$(dirname "$p3")"
    # (a) env override — prioritas absolut TANPA assert (intensi eksplisit
    #     operator; perilaku v3.5.3 dipertahankan demi kompatibilitas).
    if [ -n "${STELLAR_CANONICAL:-}" ] && [ -f "${STELLAR_CANONICAL}/SKILL.md" ]; then
        REAL_SRC="$(cd "${STELLAR_CANONICAL}" && pwd)"
        SRC_LABEL="kanonik (env STELLAR_CANONICAL)"
        # v3.5.8: override eksplisit tetap dihormati tanpa assert (perilaku
        # lama), tapi sumber racun diberitahukan KERAS — operator berhak tahu.
        source_self_ok "$REAL_SRC" \
            || say "PERINGATAN: sumber env STELLAR_CANONICAL tidak lolos verifikasi manifest internal (pohon ≠ manifest) — tetap dipakai karena override eksplisit"
        return 0
    fi
    # (b) v3.5.4 VAULT-AWARE + VERSION-AWARE: kandidat direktori kini mencakup
    #     vault kelas-A (syarat (1)+(4) adopsi: placement di luar area wipe,
    #     wired ke rantai heal otomatis) dan dipilih BERBASIS VERSI:
    #       - anti-timpa-baru (syarat (2)): kandidat yang versinya LEBIH TUA
    #         dari instalasi (rilis manifest, fallback _meta) DILEWATI —
    #         versi tak terbaca juga dilewati bila versi instalasi terbaca
    #         (tak terbukti bukan lebih tua = fail-safe);
    #       - pemenang = versi tertinggi; tie-break urutan lama (walk-up
    #         2/3/4 → vault sync → vault upload → platform default) — kanonik
    #         segar tetap menang sederajat versinya, perilaku normal tak
    #         berubah. Skenario baru: kanonik restore-basi basi + vault segar
    #         → vault menang; instalasi ter-wipe → versi tertinggi dipakai.
    iv="$(release_version)"; [ -z "$iv" ] && iv="$(meta_version "$SKILL_DIR")"
    local cands labels vlabel
    vlabel="vault sync (/home/sync)"
    [ -n "${STELLAR_VAULT:-}" ] && vlabel="vault env STELLAR_VAULT"
    cands=("$p2/../download/stellar-trail" \
           "$p3/../download/stellar-trail" \
           "$p4/../download/stellar-trail" \
           "${STELLAR_VAULT:-/home/sync/skill-vault/stellar-trail}" \
           "$PLATFORM_PROJECT/upload/skill-vault/stellar-trail" \
           "$PLATFORM_PROJECT/download/stellar-trail")
    labels=("walk-up 2-level" "walk-up 3-level" "walk-up 4-level" \
            "$vlabel" "vault upload/ (ossfs)" "platform default")
    i=0
    for c in "${cands[@]}"; do
        if [ -n "$c" ] && [ -f "$c/SKILL.md" ]; then
            v="$(card_version "$c")"
            if [ -n "$iv" ]; then
                if [ -z "$v" ] || version_lt "$v" "$iv"; then
                    i=$((i+1)); continue  # anti-timpa-baru / fail-safe
                fi
            fi
            # v3.5.8: sumber bermanifest wajib sehat internal — racun dilewati
            if ! source_self_ok "$c"; then
                POISONED="${POISONED}${labels[$i]} v${v:-?}; "
                i=$((i+1)); continue
            fi
            [ -z "$v" ] && v="0.0.0"
            if [ -z "$best_v" ] || version_lt "$best_v" "$v"; then
                best_v="$v"; best_c="$c"; best_l="${labels[$i]}"
            fi
        fi
        i=$((i+1))
    done
    # (b2) v3.5.7 SAUDARA KONVENSI (§6.8, insiden konsumer 2026-09-22):
    #     clawhub update --force menyegarkan HANYA lokasi owner-scoped —
    #     instalasi flat yang dibaca platform tetap tua. Lokasi konvensi
    #     satunya (flat skills/<slug> ↔ owner-scoped skills/@owner/<slug>)
    #     kini kandidat sumber, tunduk pada anti-timpa-baru + pemilihan
    #     berbasis versi yang sama (tie-break: saudara paling belakang —
    #     hidup di area wipe, paling tidak dipercaya di versi sederajat).
    local sib sibv sibl
    for sib in "$p2/stellar-trail" "$p2"/@*/stellar-trail "$p3/stellar-trail"; do
        [ -f "$sib/SKILL.md" ] || continue
        [ "$(cd "$sib" 2>/dev/null && pwd)" = "$(cd "$SKILL_DIR" && pwd)" ] && continue
        sibv="$(card_version "$sib")"
        if [ -n "$iv" ]; then
            if [ -z "$sibv" ] || version_lt "$sibv" "$iv" ]; then continue; fi
        fi
        # v3.5.8: saudara bermanifest wajib sehat internal — racun dilewati
        if ! source_self_ok "$sib"; then
            POISONED="${POISONED}saudara konvensi v${sibv:-?}; "
            continue
        fi
        [ -z "$sibv" ] && sibv="0.0.0"
        case "$sib" in
            */@*/*) sibl="saudara konvensi (owner-scoped)";;
            *)      sibl="saudara konvensi (flat)";;
        esac
        if [ -z "$best_v" ] || version_lt "$best_v" "$sibv" ]; then
            best_v="$sibv"; best_c="$sib"; best_l="$sibl"
        fi
    done
    if [ -n "$best_c" ]; then
        REAL_SRC="$(cd "$best_c" && pwd)"
        case "$best_l" in
            vault*)   SRC_LABEL="vault kelas-A ${best_l#vault } — v${best_v}";;
            saudara*) SRC_LABEL="${best_l} — v${best_v}";;
            *)        SRC_LABEL="kanonik (${best_l})";;
        esac
        return 0
    fi
    # arsip restore: ekstrak subtree sesuai layout aktual, lalu layout standar
    local rel tried=""
    for rel in "$(install_rel)" "skills/stellar-trail"; do
        [ -n "$rel" ] || continue
        case " $tried " in *" $rel "*) continue;; esac
        tried="$tried $rel"
        if [ -f "$TAR_PATH" ] && tar -tf "$TAR_PATH" 2>/dev/null | grep -q "^$rel/SKILL.md"; then
            local tmp
            tmp="$(mktemp -d "${HEAL_TMP:-/tmp}/heal-src-XXXXXX")" || return 1
            if tar -xf "$TAR_PATH" -C "$tmp" "$rel" 2>/dev/null; then
                # v3.5.8: subtree arsip bermanifest wajib sehat internal
                if source_self_ok "$tmp/$rel"; then
                    REAL_SRC="$tmp/$rel"; TAR_TMP="$tmp"
                    SRC_LABEL="arsip restore (${TAR_PATH} · subtree ${rel})"
                    return 0
                fi
                POISONED="${POISONED}arsip restore (${rel}); "
            fi
            rm -rf "$tmp"
        fi
    done
    return 1
}

source_desc() {
    if [ -n "$REAL_SRC" ]; then
        echo "${SRC_LABEL:-kanonik} — $REAL_SRC"
    else
        echo "(tidak ditemukan — fallback manual: $(heal_hint))"
    fi
}

# ---------------------------------------------------------------------------
# Heal: rsync sumber -> target (hapus ekstra, lindungi metadata clawhub),
# lalu patch/buat versi metadata, lalu verifikasi ulang.
# ---------------------------------------------------------------------------
do_heal() {
    command -v rsync >/dev/null 2>&1 \
        || { say "GAGAL: rsync tidak tersedia — fallback manual: $(heal_hint)"; return 1; }
    resolve_source
    if [ "$?" -ne 0 ]; then
        local pnote=""
        [ -n "$POISONED" ] && pnote=" — sumber racun (pohon ≠ manifest) dilewati: ${POISONED%; }"
        say "GAGAL: tidak ada sumber sehat yang lolos version-assert (kanonik/vault/arsip restore tidak ada atau lebih tua dari instalasi)${pnote} — fallback manual: $(heal_hint)"
        return 1
    fi
    mkdir -p "$SKILL_DIR" 2>/dev/null || { say "GAGAL: tidak bisa menulis ke $SKILL_DIR"; return 1; }

    say "sumber sehat: $(source_desc)"
    # v3.5.8: transparansi failover — sumber racun yang dilewati dilaporkan
    [ -n "$POISONED" ] && say "sumber racun (pohon ≠ manifest internal) dilewati: ${POISONED%; }"
    # --ignore-times (v3.5.7): file hasil rollback bisa berukuran SAMA dengan
    # sumber tapi mtime lebih baru (waktu ekstraksi arsip) — quick-check rsync
    # akan MELEWATKANNYA dan heal mengklami sukses tanpa mentransfer. Heal
    # harus deterministik: transfer diputuskan oleh konten, bukan keberuntungan mtime.
    if ! rsync -a --delete --ignore-times \
            --exclude='skill-card.md' \
            --exclude='_meta.json' \
            --exclude='.clawhub/' \
            "$REAL_SRC/" "$SKILL_DIR/" 2>&1; then
        say "GAGAL: rsync sumber -> target error"
        [ -n "$TAR_TMP" ] && rm -rf "$TAR_TMP"
        return 1
    fi

    # patch/buat versi metadata (identitas install dipertahankan, hanya versi;
    # bila absen akibat skills/ ter-wipe total saat boot — dibuat minimal,
    # v3.5.2 — agar instalasi tetap dikenali clawhub list)
    local V vm
    V="$(card_version "$REAL_SRC")"
    [ -z "$V" ] && V="$(release_version)"
    if [ -n "$V" ]; then
        if [ ! -f "$SKILL_DIR/_meta.json" ]; then
            printf '{\n  "ownerId": "kn72f4bd9jhdjy2p3r3yk5mjan8924cq",\n  "slug": "stellar-trail",\n  "version": "%s",\n  "publishedAt": %s\n}\n' \
                "$V" "$(date +%s000)" > "$SKILL_DIR/_meta.json"
            say "_meta.json dibuat ulang (v$V)"
        else
            sed -i "s/\"version\": *\"[^\"]*\"/\"version\": \"$V\"/" "$SKILL_DIR/_meta.json"
        fi
        if [ ! -f "$SKILL_DIR/.clawhub/origin.json" ]; then
            mkdir -p "$SKILL_DIR/.clawhub"
            printf '{\n  "version": 1,\n  "registry": "https://clawhub.ai",\n  "slug": "stellar-trail",\n  "ownerHandle": "hoshiyomix",\n  "installedVersion": "%s",\n  "installedAt": %s\n}\n' \
                "$V" "$(date +%s000)" > "$SKILL_DIR/.clawhub/origin.json"
            say "origin.json dibuat ulang (v$V)"
        else
            sed -i "s/\"installedVersion\": *\"[^\"]*\"/\"installedVersion\": \"$V\"/" "$SKILL_DIR/.clawhub/origin.json"
        fi
    fi
    [ -n "$TAR_TMP" ] && rm -rf "$TAR_TMP"

    # verifikasi pasca-heal: wajib drift nol (bila manifest tersedia)
    detect_drift
    if [ "$MMISS" -eq 1 ]; then
        if [ "$DOWNGRADED" -eq 1 ]; then
            # v3.5.7 §6.1: sumber tanpa manifest tapi disk masih < lock →
            # rollback belum tuntas — GAGAL keras, bukan "HEAL SELESAI"
            say "GAGAL: pasca-heal masih DOWNGRADED — $DRIFT_DESC"
            return 1
        fi
        if [ "$DRIFT" -eq 0 ] && [ "$SRC_BASED" -eq 1 ]; then
            say "HEAL OK dari $(source_desc) — verifikasi vs sumber: drift nol (sumber tanpa manifest rilis)"
        else
            say "HEAL SELESAI dari sumber tanpa manifest — verifikasi otomatis tidak tersedia; cek manual bila perlu"
        fi
        return 0
    fi
    if [ "$DRIFT" -eq 0 ]; then
        say "HEAL OK: instalasi disinkronkan dari $(source_desc) — drift nol (versi rilis $(release_version))"
        return 0
    fi
    say "GAGAL: pasca-heal masih drift — $DRIFT_DESC"
    return 1
}

# ---------------------------------------------------------------------------
# Regenerasi manifest (build-time — jalankan di salinan KANONIK saat rilis)
# ---------------------------------------------------------------------------
gen_manifest() {
    local v
    v="$(card_version "$SKILL_DIR")"
    if [ -z "$v" ]; then
        say "GAGAL: versi tidak terbaca dari $SKILL_DIR/skill-card.md — --manifest hanya untuk salinan kanonik rilis"
        return 1
    fi
    mkdir -p "$SKILL_DIR/assets"
    printf '%s\n' "$v" > "$VERSIONF"
    ( cd "$SKILL_DIR" && find . -type f \
        | sed 's|^\./||' \
        | grep -v '^assets/integrity\.sha256$' \
        | grep -v '^skill-card\.md$' \
        | grep -v '^_meta\.json$' \
        | grep -v '^\.clawhub/' \
        | grep -v '__pycache__/' \
        | grep -v '\.pyc$' \
        | sort | LC_ALL=C xargs sha256sum ) > "$MANIFEST"
    say "manifest dibuat: $(wc -l < "$MANIFEST" | tr -d ' ') file, versi rilis $v -> $MANIFEST"
    return 0
}

# ---------------------------------------------------------------------------
# MODES
# ---------------------------------------------------------------------------
case "$MODE" in
status)
    echo "=== STELLAR-TRAIL SELF-HEAL ==="
    echo "skill dir : $SKILL_DIR"
    LAYOUT_REL="$(install_rel)"
    echo "layout    : ${LAYOUT_REL:-(bukan instalasi skills/ — salinan sumber)} · hint: $(heal_hint)"
    echo "versi     : rilis=$(release_version || echo '?') · _meta=$(meta_version "$SKILL_DIR" || echo '-')"
    _lv="$(lock_version)"
    if [ -n "$_lv" ]; then echo "lock      : v$_lv"; else echo "lock      : (tidak tercatat di lock clawhub)"; fi
    if [ -f "$MANIFEST" ]; then
        echo "manifest  : $(wc -l < "$MANIFEST" | tr -d ' ') file terdaftar"
    else
        echo "manifest  : TIDAK ADA (instalasi tanpa manifest rilis — verifikasi otomatis mati)"
    fi
    pin_report status
    _vs=""
    for c in "${STELLAR_VAULT:-/home/sync/skill-vault/stellar-trail}" "$PLATFORM_PROJECT/upload/skill-vault/stellar-trail"; do
        if [ -f "$c/skill-card.md" ]; then
            _vs="${_vs:+$_vs · }$c v$(card_version "$c")"
        else
            _vs="${_vs:+$_vs · }$c (kosong)"
        fi
    done
    echo "vault     : $_vs"
    vault_hint status
    resolve_source && echo "sumber    : $(source_desc)" || echo "sumber    : $(source_desc)"
    [ -n "$TAR_TMP" ] && rm -rf "$TAR_TMP"; TAR_TMP=""
    detect_drift
    if [ "$MMISS" -eq 1 ] && [ "$SRC_BASED" -ne 1 ]; then
        echo "verdict   : TIDAK TERVERIFIKASI (tanpa manifest & tanpa sumber pembanding) — heal --force dari sumber, pasang manifest rilis, atau pasang ulang: $(heal_hint)"
    elif [ "$DOWNGRADED" -eq 1 ]; then
        echo "verdict   : DOWNGRADED — $DRIFT_DESC"
        echo "aksi      : bash scripts/heal-skill.sh --check (heal dari sumber lokal ≥ lock) atau $(heal_hint)"
    elif [ "$DRIFT" -eq 1 ]; then
        echo "verdict   : DRIFT — $DRIFT_DESC"
        echo "aksi      : bash scripts/heal-skill.sh --check"
    else
        echo "verdict   : BERSIH (drift nol)"
        age_info status
    fi
    exit 0
    ;;
check|force)
    pin_report check
    detect_drift
    if [ "$MODE" = "force" ]; then
        say "mode force — heal tanpa deteksi"
        do_heal
        exit $?
    fi
    if [ "$MMISS" -eq 1 ]; then
        if [ "$DRIFT" -eq 1 ]; then
            say "drift terdeteksi (tanpa manifest, vs sumber): $DRIFT_DESC"
            do_heal
            exit $?
        fi
        if [ "$SRC_BASED" -eq 1 ]; then
            say "check: manifest tidak ada, tapi verifikasi vs sumber: BERSIH — tidak ada aksi"
            exit 0
        fi
        # v3.5.2 LOUD-FAIL: tanpa manifest DAN tanpa sumber, verifikasi MUSTAHIL.
        # Dulu WARN + exit 0 (senyap di mata boot hook/watcher); kini exit 1
        # supaya kegagalan terlihat dan diagnostik mengarah ke solusi benar.
        say "GAGAL: manifest instalasi hilang & tidak ada sumber pembanding — verifikasi MUSTAHIL; sediakan kanonik (STELLAR_CANONICAL / <proyek>/download/stellar-trail) atau pasang ulang: $(heal_hint)"
        exit 1
    fi
    if [ "$DRIFT" -eq 0 ]; then
        say "check: BERSIH (drift nol) — tidak ada aksi"
        age_info say
        vault_hint say
        exit 0
    fi
    say "drift terdeteksi: $DRIFT_DESC"
    do_heal
    exit $?
    ;;
manifest)
    gen_manifest
    exit $?
    ;;
*)
    echo "pakai: heal-skill.sh --status | --check | --force | --manifest [--dir <path>]" >&2
    exit 2
    ;;
esac
