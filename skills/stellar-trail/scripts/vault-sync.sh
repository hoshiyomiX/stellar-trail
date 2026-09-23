#!/usr/bin/env bash
# ============================================================================
# vault-sync.sh — PENYEGARAN SKILL-VAULT KELAS-A (bundled sejak v3.5.4)
#
# Adopsi arsitektur skill-vault (Task 35 → Task 41), 5 syarat yang dilayani:
#   (1) placement kelas-A: /home/sync/skill-vault/ + <proyek>/upload/skill-vault/
#       (ossfs) — keduanya DI LUAR area wipe boot (bukan skills/, bukan repo.tar);
#   (2) version-assert anti-timpa-baru: --apply MENOLAK menimpa vault yang
#       lebih baru dengan kanonik lebih tua (assert simetris di sisi penulis);
#   (3) verifikasi: tiap --apply diikuti sha256sum -c manifest DI DALAM salinan
#       vault + laporan versi; --check memverifikasi tanpa menulis (drill);
#   (4) wiring: vault dibaca otomatis oleh heal-skill.sh (kandidat sumber
#       kelas-A, pemilihan berbasis versi) — dipicu boot-heal & watcher;
#   (5) refresh pada write yang SAMA dengan publish: panggil --apply setiap
#       kali rilis (setelah clawhub publish + lock sync), drill --check berkala
#       (disiplin bulanan tercatat di MEMORY).
#
# Struktur vault: <vault-root>/stellar-trail/  = salinan penuh kanonik
# (termasuk skill-card.md + assets/integrity.sha256 — heal membutuhkan keduanya
# untuk membaca & memverifikasi versi vault).
#
# pakai: bash scripts/vault-sync.sh --status | --check | --apply
#   --status  laporan ringkas state kedua vault (ada? versi?)
#   --check   verifikasi penuh tanpa menulis (versi + manifest) — drill bulanan
#   --apply   salin kanonik → kedua vault + verifikasi (SAAT RILIS; KONSUMER
#             boleh menjalankannya dari direktori instalasi — self-arm v3.5.7)
#
# Exit: 0 OK · 1 gagal (verify/apply) · 2 salah pakai
# ============================================================================
set -u

SAY_PREFIX="[vault-sync]"
say() { echo "$SAY_PREFIX $*"; }
die() { say "GAGAL: $*"; exit 1; }

MODE="${1:-}"
case "$MODE" in
    --status|--check|--apply) ;;
    -h|--help|"")
        sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0;;
    *) echo "argumen tidak dikenal: $MODE (pakai --help)" >&2; exit 2;;
esac

# Kanonik = parent dari scripts/ tempat skrip ini hidup (dijalankan dari
# salinan kanonik saat rilis). Bisa dioverride: STELLAR_CANONICAL.
CANON="${STELLAR_CANONICAL:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[ -f "$CANON/skill-card.md" ] && [ -f "$CANON/assets/integrity.sha256" ] \
    || die "kanonik tidak valid (butuh skill-card.md + manifest): $CANON — jalankan dari salinan kanonik rilis"

card_version() {
    grep -A3 -i '^## *Skill Version' "$1/skill-card.md" 2>/dev/null \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}
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

CV="$(card_version "$CANON")"
[ -n "$CV" ] || die "versi kanonik tak terbaca dari $CANON/skill-card.md"

# Root proyek dari path kanonik (<root>/download/stellar-trail); fallback env.
ROOT="$(dirname "$(dirname "$CANON")")"
ROOT="${STELLAR_PLATFORM_PROJECT:-$ROOT}"
VAULT_SYNC="${STELLAR_VAULT_SYNC_DIR:-/home/sync/skill-vault}"
VAULT_UPLOAD="${STELLAR_VAULT_UPLOAD_DIR:-$ROOT/upload/skill-vault}"

vault_state() {  # $1 = vault-root → echo "vX.Y.Z" | "(kosong)"
    if [ -f "$1/stellar-trail/skill-card.md" ]; then
        echo "v$(card_version "$1/stellar-trail" || echo '?')"
    else
        echo "(kosong)"
    fi
}

verify_vault() {  # $1 = vault-root → 0 = manifest OK, 1 = rusak/tak ada
    local d="$1/stellar-trail"
    [ -f "$d/assets/integrity.sha256" ] || return 1
    ( cd "$d" && LC_ALL=C sha256sum -c assets/integrity.sha256 >/dev/null 2>&1 )
}

README_BODY="# skill-vault — lapis sumber kelas-A untuk self-heal stellar-trail

Salinan kanonik stellar-trail yang hidup DI LUAR siklus wipe/restore container
(lihat references/environment-resilience.md). Dibaca otomatis oleh
scripts/heal-skill.sh sebagai kandidat sumber perbaikan (pemilihan berbasis
versi + anti-timpa-baru). Segarkan via scripts/vault-sync.sh --apply pada
setiap rilis; verifikasi berkala via --check.

Konsumer (pasang via clawhub install/update): jalankan SEKALI pasca-install
\`bash <direktori-instalasi>/scripts/vault-sync.sh --apply\` — skrip ini dapat
dijalankan langsung dari instalasi (kanonik = parent dari scripts/) sehingga
vault kelas-A terisi sejak menit pertama, sebelum recycle container pertama."

case "$MODE" in
--status)
    echo "=== SKILL-VAULT (kelas-A) ==="
    echo "kanonik   : $CANON (v$CV)"
    echo "vault #1  : $VAULT_SYNC — $(vault_state "$VAULT_SYNC")"
    echo "vault #2  : $VAULT_UPLOAD — $(vault_state "$VAULT_UPLOAD")"
    echo "hint      : --apply saat rilis · --check untuk drill verifikasi"
    exit 0;;
--check)
    echo "=== SKILL-VAULT VERIFY ==="
    echo "kanonik   : v$CV ($CANON)"
    FAIL=0
    for V in "$VAULT_SYNC" "$VAULT_UPLOAD"; do
        ST="$(vault_state "$V")"
        if [ "$ST" = "(kosong)" ]; then
            say "$V — (kosong) · dilewati"
            continue
        fi
        if verify_vault "$V"; then
            say "$V — $ST · manifest OK"
        else
            say "$V — $ST · MANIFEST RUSAK/FAIL — jalankan --apply"
            FAIL=1
        fi
    done
    [ "$FAIL" -eq 0 ] && say "verify: OK" || die "ada vault yang gagal verifikasi"
    exit 0;;
--apply)
    say "kanonik v$CV → vault ($VAULT_SYNC · $VAULT_UPLOAD)"
    command -v rsync >/dev/null 2>&1 || die "rsync tidak tersedia"
    FAIL=0
    for V in "$VAULT_SYNC" "$VAULT_UPLOAD"; do
        ST="$(vault_state "$V")"
        # assert simetris (syarat 2): jangan timpa vault lebih baru dgn kanonik tua
        if [ "$ST" != "(kosong)" ] && [ "$ST" != "v?" ] \
           && version_lt "$CV" "${ST#v}"; then
            say "$V — DITOLAK: vault $ST lebih baru dari kanonik v$CV (anti-timpa-baru) — sinkronkan kanonik dulu"
            FAIL=1
            continue
        fi
        if ! mkdir -p "$V" 2>/dev/null; then
            say "$V — tidak bisa dibuat/ditulis — dilewati"
            FAIL=1
            continue
        fi
        if ! rsync -a --delete "$CANON/" "$V/stellar-trail/"; then
            say "$V — rsync GAGAL"
            FAIL=1
            continue
        fi
        printf '%s\n' "$README_BODY" \
            "" "Versi: v$CV · disinkronkan $(date '+%Y-%m-%d %H:%M:%S') dari kanonik rilis." \
            > "$V/README.md"
        if verify_vault "$V"; then
            say "$V — tersinkron v$CV · manifest OK"
        else
            say "$V — tersinkron TAPI manifest gagal diverifikasi"
            FAIL=1
        fi
    done
    [ "$FAIL" -eq 0 ] || die "ada vault yang gagal --apply (lihat atas)"
    say "apply: OK — kedua vault kelas-A v$CV"
    exit 0;;
esac
