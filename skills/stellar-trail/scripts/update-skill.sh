#!/usr/bin/env bash
# ============================================================================
# update-skill.sh — AUTO-CEK-UPDATE + FORCE UPDATE & UPGRADE stellar-trail
# stellar-trail v3.6.6 · Task 67 · 2026-09-26
#
# MANDAT (user, Task 67 #1): SEBELUM fase dimulai (dipanggil protokol di M0,
# setelah bootstrap --ensure, sebelum respons pertama), bash secara otomatis:
#   cek update → bila origin lebih baru: force update & upgrade dengan
#   OVERRIDE file terbaru (lokal ditimpa, bukan merge) → seluruh proses
#   instalasi DICETAK ke stdout agar user well-informed dan bisa menindak-
#   lanjuti.
#
# SUMBER = GitHub hoshiyomiX/stellar-trail (D24: kanal distribusi utama &
# tunggal; registry clawhub BANNED permanen — TIDAK pernah disentuh skrip
# ini). Baca publik tanpa PAT; PAT tidak dibaca/ditulis di sini.
#
# DESAIN (keputusan terkunci Task 67 via klarifikasi):
#   - TRIGGER: dipanggil `--ensure` di M0 tiap sesi; DEBOUNCE 24 jam —
#     cek jaringan penuh maksimal 1x/hari (state .zscripts/.update-check.last),
#     sisanya laporan ringan tanpa jaringan. `--force` menembus debounce.
#   - SEMANTIK: oto-override TERVERIFIKASI — clone staging → verifikasi
#     manifest SHA-256 PENUH → assert tag≡konten (anti-racun) → assert
#     anti-downgrade (remote < lokal = DITOLAK) → baru swap. Urutan swap
#     mengikuti doktrin environment-resilience §8: KANONIK dulu → vault
#     kelas-A → instalasi live TERAKHIR (kegagalan tengah jalan menyisakan
#     live utuh; boot-heal dev.sh menuntaskan dari kanonik yang sudah segar).
#   - PASCA-SWAP AUTO-RESTART: vault-sync --apply (best-effort) + deploy
#     watcher dari kanonik baru + restart (--stop → cp → --force-start,
#     membersihkan stop-flag) + bootstrap-sandbox --ensure (best-effort).
#   - OFFLINE = LAPOR, BUKAN BLOKIR: kegagalan jaringan/git dicetak satu
#     baris lalu exit 0 — M0 tidak pernah tergantung jaringan (boot chain
#     tetap offline-first; heal/bootstrap tetap jaring-pengaman offline).
#   - SELF-COPY RE-EXEC: skrip menyalin dirinya ke temp SEBELUM swap —
#     menimpa direktori instalasi tempat file ini sedang dieksekusi adalah
#     kondisi undefined; salinan temp mengeksekusi swap dengan aman.
#   - IDENTITAS TIDAK PERNAH DITIMPA: _meta.json + .clawhub/ dikecualikan
#     dari rsync --delete (doktrin heal-skill; identitas clawhub tidak
#     tersentuh — dikecualikan, bukan dihapus).
#
# DOKTRIN STANDALONE-HELPER (Appendix B environment-resilience.md): skrip ini
# mandiri — tidak mensourcing pustaka bersama; version_lt() di bawah adalah
# SALINAN TERKENDALI (R5 audit T63) bersama heal-skill.sh + vault-sync.sh.
#
# pakai: bash scripts/update-skill.sh [--ensure|--force|--check|--status|-h]
#   (tanpa argumen = --ensure — jalur M0)
#   --ensure  cek dgn debounce 24j + auto-update bila origin lebih baru
#   --force   tembus debounce + auto-update (cek jaringan penuh SEKARANG)
#   --check   cek jaringan penuh TANPA swap (laporan saja — dry-run)
#   --status  laporan state lokal tanpa jaringan
#
# Env: STELLAR_PROJECT (root proyek) · STELLAR_UPDATE_ORIGIN (repo git;
#      default GitHub hoshiyomiX/stellar-trail) · STELLAR_UPDATE_STATE
#      (file debounce) · STELLAR_UPDATE_DEBOUNCE (detik, default 86400) ·
#      STELLAR_VAULT_SYNC_DIR / STELLAR_VAULT_UPLOAD_DIR (diteruskan ke
#      vault-sync.sh)
#
# Exit: 0 = OK / sudah-terbaru / ditolak-wajar / offline-graceful
#       1 = update GAGAL (verify/racun/swap) — laporkan, jangan blokir M0
# ============================================================================
set -u

# --- SELF-COPY RE-EXEC (anti menimpa file yang sedang dieksekusi) -----------
if [ "${STELLAR_UPDATE_SELFEXE:-}" != "1" ]; then
    _tmp_self="$(mktemp /tmp/stellar-trail-update.XXXXXX.sh)" || exit 1
    if ! cat "${BASH_SOURCE[0]}" > "$_tmp_self" 2>/dev/null; then
        echo "[update] FATAL: gagal self-copy ke $_tmp_self" >&2; exit 1
    fi
    STELLAR_UPDATE_SELFEXE=1 STELLAR_UPDATE_ORIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" \
        exec bash "$_tmp_self" "$@"
fi
trap 'rm -f "$0" 2>/dev/null' EXIT
SELF_DIR="${STELLAR_UPDATE_ORIG_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

say() { echo "[update] $*"; }

# --- LOKASI -----------------------------------------------------------------
SKILL_ROOT="$(cd "$SELF_DIR/.." && pwd)"
PROJECT="${STELLAR_PROJECT:-}"
if [ -z "$PROJECT" ]; then
    _d="$SELF_DIR"
    for _ in 1 2 3 4 5 6 7; do
        _d="$(dirname "$_d")"
        if [ -d "$_d/skills" ] || [ -d "$_d/download" ] || [ -d "$_d/.zscripts" ] \
           || [ -f "$_d/worklog.md" ]; then
            PROJECT="$_d"; break
        fi
        [ "$_d" = "/" ] && break
    done
fi
PROJECT="${PROJECT:-$(dirname "$(dirname "$SKILL_ROOT")")}"
ZDIR="$PROJECT/.zscripts"
CANON="$PROJECT/download/stellar-trail"
ORIGIN="${STELLAR_UPDATE_ORIGIN:-https://github.com/hoshiyomiX/stellar-trail.git}"
STATE="${STELLAR_UPDATE_STATE:-$ZDIR/.update-check.last}"
DEBOUNCE="${STELLAR_UPDATE_DEBOUNCE:-86400}"

# SALINAN TERKENDALI (R5 audit T63, sejak v3.6.5; trio sejak v3.6.6):
# duplikat eksak fungsi version_lt hidup di heal-skill.sh, vault-sync.sh,
# dan update-skill.sh (file ini) — doktrin standalone-helper (Appendix B
# environment-resilience.md) MELARANG konsolidasi ke pustaka bersama;
# ubah KETIGANYA bersamaan.
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

local_version() {
    cat "$SKILL_ROOT/assets/integrity.version" 2>/dev/null | tr -d '[:space:]'
}
read_state() {  # echo "<epoch> <ver>"
    [ -f "$STATE" ] && cat "$STATE" 2>/dev/null || echo "0 -"
}
write_state() {  # $1 = versi terpantau
    mkdir -p "$(dirname "$STATE")" 2>/dev/null || return 0
    echo "$(date +%s) $1" > "$STATE" 2>/dev/null || true
}

MODE="${1:---ensure}"
case "$MODE" in
    --ensure|--force|--check|--status|-h|--help) ;;
    *) echo "[update] argumen tidak dikenal: $MODE (pakai --help)" >&2; exit 1;;
esac

if [ "$MODE" = "-h" ] || [ "$MODE" = "--help" ]; then
    sed -n '2,52p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

LOCAL_VER="$(local_version)"
if [ -z "$LOCAL_VER" ]; then
    say "FATAL: versi lokal tak terbaca ($SKILL_ROOT/assets/integrity.version) — instalasi tidak dikenali"
    exit 1
fi

# --- MODE --status (tanpa jaringan) -----------------------------------------
if [ "$MODE" = "--status" ]; then
    ST="$(read_state)"; ST_EPOCH="${ST%% *}"; ST_VER="${ST#* }"
    ST_HUMAN="belum pernah"
    [ "$ST_EPOCH" -gt 0 ] 2>/dev/null && ST_HUMAN="$(date -d "@$ST_EPOCH" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "@$ST_EPOCH") v$ST_VER"
    echo "=== UPDATE-SKILL STATUS ==="
    echo "instalasi : $SKILL_ROOT (v$LOCAL_VER)"
    echo "origin    : $ORIGIN"
    echo "cek       : $ST_HUMAN · debounce ${DEBOUNCE}s"
    echo "kanonik   : $CANON $([ -d "$CANON" ] && echo "(ada)" || echo "(tidak ada)")"
    echo "watcher   : $ZDIR/watcher.sh $([ -f "$ZDIR/watcher.sh" ] && echo "(ada)" || echo "(tidak ada)")"
    exit 0
fi

# --- DEBOUNCE (--ensure saja; --force/--check menembus) ----------------------
if [ "$MODE" = "--ensure" ]; then
    ST="$(read_state)"; ST_EPOCH="${ST%% *}"; ST_VER="${ST#* }"
    NOW="$(date +%s)"
    if [ "$ST_EPOCH" -gt 0 ] 2>/dev/null && [ $((NOW - ST_EPOCH)) -lt "$DEBOUNCE" ]; then
        say "cek dilewati (debounce ${DEBOUNCE}s): terakhir $(date -d "@$ST_EPOCH" '+%H:%M' 2>/dev/null) terpantau v$ST_VER — lokal v$LOCAL_VER · pakai --force untuk cek sekarang"
        exit 0
    fi
fi

# --- CEK REMOTE -------------------------------------------------------------
if ! command -v git >/dev/null 2>&1; then
    say "git tidak tersedia — cek update dilewati (offline-first; jalur heal tetap utuh)"
    exit 0
fi
say "cek origin: $ORIGIN"
REMOTE_VER="$(timeout 25 git ls-remote --tags --refs --sort=-v:refname "$ORIGIN" 'v[0-9]*' 2>/dev/null \
    | head -1 | awk -F/ '{print $NF}' | sed 's/^v//' | tr -d '[:space:]')"
if [ -z "$REMOTE_VER" ]; then
    say "origin tidak terjangkau / tak ada tag — dilewati (offline-first; M0 tidak diblokir)"
    exit 0
fi
say "origin terpantau: v$REMOTE_VER · lokal: v$LOCAL_VER"

if [ "$REMOTE_VER" = "$LOCAL_VER" ]; then
    write_state "$REMOTE_VER"
    say "sudah terbaru (v$LOCAL_VER) — tidak ada tindakan"
    exit 0
fi
if version_lt "$REMOTE_VER" "$LOCAL_VER"; then
    write_state "$REMOTE_VER"
    say "DITOLAK: origin v$REMOTE_VER LEBIH TUA dari lokal v$LOCAL_VER (anti-downgrade — lokal mode-dev? push dulu ke origin)"
    exit 0
fi
if [ "$MODE" = "--check" ]; then
    say "UPDATE TERSEDIA: v$LOCAL_VER → v$REMOTE_VER (mode --check: tidak ada swap — jalankan --ensure/--force untuk memasang)"
    exit 0
fi

# ============================================================================
# APPLY — OVERRIDE dengan file terbaru (staging → verify → swap)
# ============================================================================
say "=== PEMBARUAN v$LOCAL_VER → v$REMOTE_VER DIMULAI ==="
STAGING="$(mktemp -d /tmp/stellar-trail-update-src.XXXXXX)" || { say "FATAL: mktemp gagal"; exit 1; }
cleanup() { rm -rf "$STAGING" 2>/dev/null || true; }
trap 'cleanup; rm -f "$0" 2>/dev/null' EXIT

say "[1/7] unduh staging: git clone --depth 1 --branch v$REMOTE_VER"
if ! timeout 180 git clone --quiet --depth 1 --branch "v$REMOTE_VER" "$ORIGIN" "$STAGING/repo" 2>/dev/null; then
    say "GAGAL: clone v$REMOTE_VER tidak bisa — update dibatalkan (instalasi lokal UTUH)"
    exit 1
fi
SKILL_SRC="$STAGING/repo/skills/stellar-trail"
if [ ! -f "$SKILL_SRC/assets/integrity.sha256" ] || [ ! -f "$SKILL_SRC/assets/integrity.version" ]; then
    say "GAGAL: staging bukan paket stellar-trail yang dikenal (manifest hilang) — dibatalkan"
    exit 1
fi

say "[2/7] verifikasi manifest SHA-256 staging"
MANIFEST_N="$(wc -l < "$SKILL_SRC/assets/integrity.sha256")"
if ! ( cd "$SKILL_SRC" && LC_ALL=C sha256sum -c assets/integrity.sha256 --quiet >/dev/null 2>&1 ); then
    say "GAGAL: manifest staging TIDAK LOLOS ($MANIFEST_N entri) — sumber racun, dibatalkan (menyalin kerusakan bukanlah penyembuhan)"
    exit 1
fi
SRC_VER="$(cat "$SKILL_SRC/assets/integrity.version" | tr -d '[:space:]')"
if [ "$SRC_VER" != "$REMOTE_VER" ]; then
    say "GAGAL: tag v$REMOTE_VER berisi konten v$SRC_VER (tag ≠ konten) — sumber racun, dibatalkan"
    exit 1
fi
say "       manifest $MANIFEST_N/$MANIFEST_N OK · tag≡konten v$SRC_VER · anti-downgrade OK"

swap_tree() {  # $1 = sumber staging, $2 = target, $3 = label
    local src="$1" tgt="$2" label="$3" n
    rm -rf "${tgt}.update-bak" 2>/dev/null || true
    cp -a "$tgt" "${tgt}.update-bak" 2>/dev/null || true
    if ! rsync -a --delete --exclude='_meta.json' --exclude='.clawhub' --exclude='*.pyc' \
            --exclude='__pycache__' "$src/" "$tgt/"; then
        say "GAGAL: rsync ke $label gagal — rollback dari .update-bak"
        rm -rf "$tgt"; mv "${tgt}.update-bak" "$tgt" 2>/dev/null || true
        return 1
    fi
    find "$tgt" -type f -not -path '*/.clawhub/*' -exec chmod 644 {} + 2>/dev/null || true
    if ! ( cd "$tgt" && LC_ALL=C sha256sum -c assets/integrity.sha256 --quiet >/dev/null 2>&1 ); then
        say "GAGAL: verifikasi pasca-swap $label gagal — rollback dari .update-bak"
        rm -rf "$tgt"; mv "${tgt}.update-bak" "$tgt" 2>/dev/null || true
        return 1
    fi
    n="$(find "$tgt" -type f -not -path '*/.clawhub/*' | wc -l)"
    rm -rf "${tgt}.update-bak" 2>/dev/null || true
    say "       $label: v$(cat "$tgt/assets/integrity.version" 2>/dev/null) · $n file terpasang · manifest OK"
    return 0
}

say "[3/7] swap KANONIK (download/stellar-trail) — doktrin §8: kanonik dulu"
if [ -d "$CANON" ] && [ -f "$CANON/assets/integrity.sha256" ]; then
    swap_tree "$SKILL_SRC" "$CANON" "kanonik" || { say "FATAL: kanonik gagal — hentikan (live belum disentuh)"; exit 1; }
else
    say "       kanonik tidak ada di $CANON — dilewati (instalasi konsumer)"
fi

say "[4/7] segarkan VAULT kelas-A (vault-sync --apply)"
if [ -f "$CANON/scripts/vault-sync.sh" ]; then
    # capture-dulu-baru-print (pelajaran T62/T64: jangan uji exit status pipeline sed)
    _vs_out="$(bash "$CANON/scripts/vault-sync.sh" --apply 2>&1)"; _vs_rc=$?
    printf '%s\n' "$_vs_out" | sed 's/^/       /'
    [ "$_vs_rc" -eq 0 ] || say "       WARN: vault-sync --apply gagal (rc=$_vs_rc) — update tetap lanjut (vault best-effort)"
else
    say "       vault-sync.sh tidak ada di kanonik — dilewati"
fi

say "[5/7] swap INSTALASI LIVE (skills/stellar-trail — TERAKHIR per §8)"
LIVE_OK=0; LIVE_N=0
shopt -s nullglob
for LIVE in "$PROJECT/skills/stellar-trail" "$PROJECT"/skills/@*/stellar-trail; do
    [ -d "$LIVE" ] || continue
    LIVE_N=$((LIVE_N + 1))
    if swap_tree "$SKILL_SRC" "$LIVE" "live ${LIVE#"$PROJECT"/}"; then
        LIVE_OK=$((LIVE_OK + 1))
    fi
done
shopt -u nullglob
if [ "$LIVE_N" -gt 0 ] && [ "$LIVE_OK" -ne "$LIVE_N" ]; then
    say "FATAL: $((LIVE_N - LIVE_OK)) instalasi live gagal swap — boot-heal dev.sh akan menuntaskan dari kanonik v$REMOTE_VER (sudah segar)"
    exit 1
fi
[ "$LIVE_N" -eq 0 ] && say "       tidak ada instalasi live di $PROJECT/skills/ — hanya kanonik yang disegarkan"

say "[6/7] restart WATCHER dari kanonik baru (--stop → deploy → --force-start)"
if [ -d "$ZDIR" ] && [ -f "$CANON/scripts/watcher.sh" ]; then
    [ -f "$ZDIR/watcher.sh" ] && bash "$ZDIR/watcher.sh" --stop >/dev/null 2>&1 || true
    if cp "$CANON/scripts/watcher.sh" "$ZDIR/watcher.sh" 2>/dev/null; then
        chmod 644 "$ZDIR/watcher.sh"
        _w_out="$(bash "$ZDIR/watcher.sh" --force-start 2>&1)"; _w_rc=$?
        printf '%s\n' "$_w_out" | sed 's/^/       /'
        [ "$_w_rc" -eq 0 ] || say "       WARN: watcher --force-start gagal — cek manual: bash $ZDIR/watcher.sh --force-start"
    else
        say "       WARN: gagal menyalin watcher.sh ke $ZDIR — cek izin tulis"
    fi
else
    say "       .zscripts/ atau watcher.sh kanonik tidak ada — dilewati (env tanpa bootstrap)"
fi

say "[7/7] bootstrap --ensure (refresh lapisan persistensi)"
if [ -f "$CANON/scripts/bootstrap-sandbox.sh" ]; then
    _bs_out="$(bash "$CANON/scripts/bootstrap-sandbox.sh" --ensure 2>&1)"; _bs_rc=$?
    printf '%s\n' "$_bs_out" | tail -4 | sed 's/^/       /'
    [ "$_bs_rc" -eq 0 ] || say "       WARN: bootstrap --ensure gagal — lapisan tetap berfungsi dari state sebelumnya"
else
    say "       bootstrap-sandbox.sh tidak ada di kanonik — dilewati"
fi

write_state "$REMOTE_VER"
say "=== PEMBARUAN SELESAI: v$LOCAL_VER → v$REMOTE_VER ==="
say "tindak lanjut: protokol kini berjalan di atas v$REMOTE_VER — banner respons naik v$REMOTE_VER; bila sesi ini sedang berjalan, muat ulang body skill pada sesi berikutnya (Activation rule 11)"
exit 0
