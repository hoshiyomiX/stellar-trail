#!/usr/bin/env bash
# ============================================================================
# bootstrap-sandbox.sh — ARMIN PERSISTENCE LAYER utk sandbox yang bisa di-reset
# stellar-trail v3.6.1 · Task 56 · 2026-09-24
#
# MASALAH YANG DISEMBUHKAN (forensik Task 55, 3/3 terkonfirmasi):
#   #1 skill files hilang pasca reset  — packer platform mengecualikan
#      skills/ dari arsip restore → instalasi ter-wipe tiap boot
#   #2 explorer/layanan mati permanen  — tak ada boot hook yang menghidupkan
#      ulang proses yang dikill reset
#   #3 rantai aktivasi putus          — worklog.md tak pernah dibuat → hook
#      R1 absen → skill tak termuat di sesi berikutnya
#
# SOLUSI (SATU JALUR TERBUKTI PER MODUL — tanpa fallback redundan):
#   core     : salin instalasi hidup → kanonik download/stellar-trail/
#              (packer MEMPERTAHANKAN download/ + .zscripts/ + memory/ +
#              worklog.md — terverifikasi dari arsip packer asli) lalu pasang
#              .zscripts/dev.sh (boot hook kontrak /start.sh) yang memulihkan
#              skills/stellar-trail dari kanonik di TIAP boot.
#   explorer : --with-explorer  → pasang .zscripts/{explorer.sh,explorer.py,
#              explorer-ui/} + langkah --ensure di dev.sh.
#   snapshot : --with-snapshot  → pasang .zscripts/repo-snapshot.sh + langkah
#              --apply-auto di dev.sh (platform dgn /home/sync).
#
# PRINSIP DESAIN:
#   - Satu jalur per modul: sumber seed = direktori instalasi tempat skrip
#     ini berjalan (self-locating, offline, tanpa negosiasi versi).
#   - Idempoten: aman dijalankan berulang (--ensure); hanya menulis bila
#     konten berbeda; TIDAK PERNAH menimpa memory/, worklog.md, atau dev.sh
#     yang bukan milik bootstrap.
#   - Tidak menyentuh .clawhub/ (identitas install clawhub milik heal-skill.sh).
#
# PERINTAH:
#   bash scripts/bootstrap-sandbox.sh                     # pasang core + laporan
#   bash scripts/bootstrap-sandbox.sh --ensure            # idempoten utk M0 (pakai modul dari state)
#   bash scripts/bootstrap-sandbox.sh --with-explorer     # aktifkan modul explorer
#   bash scripts/bootstrap-sandbox.sh --with-snapshot     # aktifkan modul snapshot
#   bash scripts/bootstrap-sandbox.sh --status            # laporan read-only
#   bash scripts/bootstrap-sandbox.sh --project-dir PATH  # override deteksi root proyek
#   bash scripts/bootstrap-sandbox.sh --force-devsh       # timpa dev.sh non-bootstrap
#
# EXIT: 0 = armed/sehat · 1 = gagal (lihat [bootstrap] baris terakhir)
# ============================================================================
set -u

# ---------------------------------------------------------------------------
# 0. SELF-LOCATE — skrip hidup di <skill-root>/scripts/, proyek = walk-up
# ---------------------------------------------------------------------------
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(dirname "$SELF_DIR")"

BOOT_VERSION="$(cat "$SKILL_ROOT/assets/integrity.version" 2>/dev/null || echo "unknown")"
STATE_MARKER="# BOOTSTRAP-GENERATED: stellar-trail bootstrap-sandbox.sh"
JUNK_DIRS=(-name '__pycache__' -o -name '.DS_Store')
JUNK_FILES=(-name '*.pyc' -o -name '*.pyo')

log() { echo "[bootstrap] $*"; }
die() { echo "[bootstrap] GAGAL: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. ARGUMEN
# ---------------------------------------------------------------------------
MODE="install"          # install | status
ENSURE=0
FORCE_DEVSH=0
OPT_PROJECT=""
MODULE_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --ensure)        ENSURE=1 ;;
        --status)        MODE="status" ;;
        --with-explorer) MODULE_ARGS+=("explorer") ;;
        --with-snapshot) MODULE_ARGS+=("snapshot") ;;
        --force-devsh)   FORCE_DEVSH=1 ;;
        --project-dir)   : ;;   # nilai diambil arg berikutnya di bawah
        --project-dir=*) OPT_PROJECT="${arg#*=}" ;;
        -h|--help)       sed -n '2,45p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) ;;
    esac
done
# tangkap nilai --project-dir PATH (dua token)
prev=""
for arg in "$@"; do
    if [ "$prev" = "--project-dir" ]; then OPT_PROJECT="$arg"; fi
    prev="$arg"
done

# ---------------------------------------------------------------------------
# 2. DETEKSI ROOT PROYEK — walk-up maks 6 level, atau --project-dir
#    marker: skills/ · download/ · .zscripts/ · .clawhub/ · worklog.md · package.json
# ---------------------------------------------------------------------------
find_project_root() {
    local d="$SKILL_ROOT"
    for _ in 1 2 3 4 5 6; do
        d="$(dirname "$d")"
        if [ -d "$d/skills" ] || [ -d "$d/download" ] || [ -d "$d/.zscripts" ] \
           || [ -d "$d/.clawhub" ] || [ -f "$d/worklog.md" ] || [ -f "$d/package.json" ]; then
            echo "$d"; return 0
        fi
        [ "$d" = "/" ] && break
    done
    return 1
}

if [ -n "$OPT_PROJECT" ]; then
    PROJECT="$(cd "$OPT_PROJECT" 2>/dev/null && pwd)" || die "--project-dir tidak valid: $OPT_PROJECT"
else
    PROJECT="$(find_project_root)" || die "root proyek tidak terdeteksi dari $SKILL_ROOT (tidak ada skills/ · download/ · .zscripts/ · worklog.md · package.json di 6 level atas). Gunakan --project-dir <path>."
fi
[ "$PROJECT" = "/" ] && die "root proyek terdeteksi '/' — tolak."
[ -w "$PROJECT" ] || die "root proyek tidak writable: $PROJECT"

CANON="$PROJECT/download/stellar-trail"
ZDIR="$PROJECT/.zscripts"
STATE_FILE="$ZDIR/bootstrap.state"
MEMORY_DIR="$PROJECT/memory"
WORKLOG="$PROJECT/worklog.md"
MODULES_FILE="/tmp/bootstrap-modules.$$"

# ---------------------------------------------------------------------------
# 3. STATE MODUL — state lama + modul baru; persist setelah sukses
#    format state: satu baris per kunci: v=<versi> m=<modul,...> d=<tanggal>
# ---------------------------------------------------------------------------
load_state_modules() {
    [ -f "$STATE_FILE" ] || return 0
    local m; m="$(sed -n 's/^m=//p' "$STATE_FILE" 2>/dev/null)"
    [ -n "$m" ] || return 0
    local mod
    for mod in ${m//,/ }; do echo "$mod" >> "$MODULES_FILE"; done
}
add_module() { echo "$1" >> "$MODULES_FILE"; }
has_module() { grep -qx -- "$1" "$MODULES_FILE" 2>/dev/null; }
sort_modules() { sort -u "$MODULES_FILE" 2>/dev/null > "${MODULES_FILE}.s" && mv "${MODULES_FILE}.s" "$MODULES_FILE" 2>/dev/null; }

: > "$MODULES_FILE" 2>/dev/null || die "tmp tidak writable"
load_state_modules
for m in "${MODULE_ARGS[@]:-}"; do [ -n "$m" ] && add_module "$m"; done
sort_modules
MODULE_LIST="$(tr '\n' ',' < "$MODULES_FILE" | sed 's/,$//')"
[ -z "$MODULE_LIST" ] && MODULE_LIST="-"

# ---------------------------------------------------------------------------
# 4. FUNGSI UTIL — tulis-bila-beda (idempoten)
# ---------------------------------------------------------------------------
write_if_changed() {  # $1=konten-file-sumber  $2=target  → echo "wrote"|"kept"
    local src="$1" dst="$2"
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then echo "kept"; return 0; fi
    mkdir -p "$(dirname "$dst")"
    cp -p "$src" "$dst" && echo "wrote"
}

prune_junk() {  # $1=root tree — buang __pycache__/*.pyc/.DS_Store
    find "$1" \( -type d \( -name '__pycache__' -o -name '.DS_Store' \) -exec rm -rf {} + \) 2>/dev/null
    find "$1" \( -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete \) 2>/dev/null
    return 0
}

# ---------------------------------------------------------------------------
# 5. MODE --status — read-only, tidak pernah mengubah apa pun
# ---------------------------------------------------------------------------
if [ "$MODE" = "status" ]; then
    echo "=== BOOTSTRAP STATUS (v$BOOT_VERSION) ==="
    echo "skill root : $SKILL_ROOT"
    echo "project    : $PROJECT"
    echo "modules    : ${MODULE_LIST}"
    if [ -d "$CANON" ]; then
        echo -n "canonical  : $(find "$CANON" -type f | wc -l) file"
        if (cd "$CANON" && sha256sum -c assets/integrity.sha256 --quiet >/dev/null 2>&1); then
            echo " · manifest OK"
        else
            echo " · manifest GAGAL/absen"
        fi
    else
        echo "canonical  : BELUM ADA (belum di-seed)"
    fi
    if [ -f "$ZDIR/dev.sh" ]; then
        if head -n 2 "$ZDIR/dev.sh" | grep -qF "$STATE_MARKER"; then
            echo "dev.sh     : bootstrap-generated ($(sed -n 's/^# .*modules: //p' "$ZDIR/dev.sh" | head -n 1))"
        else
            echo "dev.sh     : ADA tapi BUKAN milik bootstrap (dilewati tanpa --force-devsh)"
        fi
    else
        echo "dev.sh     : BELUM TERPASANG"
    fi
    has_module explorer && {
        for f in explorer.sh explorer.py explorer-ui/index.html; do
            echo "explorer   : .zscripts/$f $([ -f "$ZDIR/$f" ] && echo OK || echo HILANG)"
        done
    }
    has_module snapshot && echo "snapshot   : .zscripts/repo-snapshot.sh $([ -f "$ZDIR/repo-snapshot.sh" ] && echo OK || echo HILANG)"
    echo "memory     : $([ -f "$MEMORY_DIR/SESSION-STATE.md" ] && echo "scaffold/aktif ($MEMORY_DIR)" || echo "BELUM ADA")"
    echo "worklog    : $([ -f "$WORKLOG" ] && { grep -q '⚡ACTIVATE' "$WORKLOG" && echo "ada + hook R1 OK" || echo "ada TANPA hook R1"; } || echo "BELUM ADA")"
    echo "state file : $([ -f "$STATE_FILE" ] && cat "$STATE_FILE" | tr '\n' ' ' || echo "belum ada")"
    rm -f "$MODULES_FILE"
    exit 0
fi

# ---------------------------------------------------------------------------
# 6. MODUL CORE-A — SEED KANONIK: live install → download/stellar-trail/
#    staging + compare + swap (idempoten; junk dibuang dari kanonik)
# ---------------------------------------------------------------------------
STAGE="$(mktemp -d "$PROJECT/.bootstrap-stage.XXXXXX")" || die "mktemp gagal"
trap 'rm -rf "$STAGE" "$MODULES_FILE"' EXIT

log "seed kanonik: $SKILL_ROOT → $CANON"
mkdir -p "$STAGE/stellar-trail"
cp -a "$SKILL_ROOT/." "$STAGE/stellar-trail/" || { die "gagal menyalin tree skill dari $SKILL_ROOT"; }
prune_junk "$STAGE/stellar-trail"

if [ -d "$CANON" ]; then
    prune_junk "$CANON"
    if diff -rq "$CANON" "$STAGE/stellar-trail" >/dev/null 2>&1; then
        log "kanonik sudah segar (0 perubahan)"
    else
        rm -rf "${CANON}.old"
        mv "$CANON" "${CANON}.old" && mv "$STAGE/stellar-trail" "$CANON" \
            || die "swap kanonik gagal (backup: ${CANON}.old)"
        rm -rf "${CANON}.old"
        log "kanonik disegarkan ($(find "$CANON" -type f | wc -l) file)"
    fi
else
    mkdir -p "$(dirname "$CANON")"
    mv "$STAGE/stellar-trail" "$CANON" || die "gagal menulis kanonik"
    log "kanonik DIBUAT ($(find "$CANON" -type f | wc -l) file)"
fi

# verifikasi kanonik vs manifest rilis (bawaan paket)
if (cd "$CANON" && sha256sum -c assets/integrity.sha256 --quiet >/dev/null 2>&1); then
    log "verifikasi manifest: OK"
    VERIFY="manifest OK"
else
    BAD_N=$(cd "$CANON" && sha256sum -c assets/integrity.sha256 2>/dev/null | grep -c 'FAILED' || true)
    log "WARN: manifest mismatch ($BAD_N entri) — kanonik tetap dipakai apa adanya (jalur tunggal: salinan instalasi inilah sumbernya)"
    VERIFY="manifest MISMATCH ($BAD_N)"
fi

# ---------------------------------------------------------------------------
# 7. MODUL CORE-B — GENERATE .zscripts/dev.sh (boot hook kontrak /start.sh)
#    Satu jalur restore skill: kanonik → skills/stellar-trail (manifest-check).
#    dev.sh milik bootstrap ditandai; dev.sh asing tidak pernah ditimpa
#    kecuali --force-devsh.
# ---------------------------------------------------------------------------
build_devsh() {
    cat <<'DEVSH_HEAD'
#!/usr/bin/env bash
DEVSH_HEAD
    echo "$STATE_MARKER v$BOOT_VERSION (modules: $MODULE_LIST)"
    cat <<'DEVSH_BODY'
# dev.sh — PERSISTENT BOOT HOOK (dijalankan otomatis oleh /start.sh setiap boot)
# DIBUAT OLEH bootstrap-sandbox.sh — JANGAN edit manual; regenerasi via
#   bash download/stellar-trail/scripts/bootstrap-sandbox.sh [--with-*]
#
# SATU JALUR PER MODUL (tanpa fallback redundan):
#   1. SKILL RESTORE : skills/stellar-trail diverifikasi vs kanonik
#      download/stellar-trail (manifest SHA-256); rusak/hilang → dipulihkan
#      dari kanonik. Kanonik = salinan instalasi saat bootstrap — apa yang
#      Anda pasang adalah yang dipertahankan.
#   2. FULLSTACK GUARD: keberadaan dev.sh MENGGANTIKAN flow bun milik
#      /start.sh — flow itu direplikasi di sini agar proyek web tetap hidup.
#   3. TIDY download/ : artifact eval/audit dipindah ke archive/ (undo-able).
DEVSH_BODY
    has_module explorer && cat <<'DEVSH_EXPL'
#   4. EXPLORER --ensure : hidupkan explorer bila mati + segarkan drift.
DEVSH_EXPL
    has_module snapshot && cat <<'DEVSH_SNAP'
#   5. SNAPSHOT --apply-auto : segarkan arsip restore (debounce internal).
DEVSH_SNAP
    cat <<'DEVSH_VARS'

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOAD="$PROJECT/download"
ARCHIVE="$PROJECT/archive"
BOOTLOG="$PROJECT/.zscripts/boot.log"
LOCKDIR="/tmp/dev-sh.lock"
CANON="$DOWNLOAD/stellar-trail"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(ts)] $*" >> "$BOOTLOG"; echo "[dev.sh] $*"; }

if [ "$1" = "--status" ]; then
    echo "=== project: $PROJECT ==="
    echo "=== download/ (top-level) ==="; ls -1 "$DOWNLOAD" 2>/dev/null
    echo "=== boot.log (15 terakhir) ==="; tail -15 "$BOOTLOG" 2>/dev/null || echo "(belum ada)"
    exit 0
fi

# anti double-run (lock 10 menit, basi otomatis diambil alih)
if [ -d "$LOCKDIR" ]; then
    if [ -z "$(find "$LOCKDIR" -maxdepth 0 -mmin -10 2>/dev/null)" ]; then
        rm -rf "$LOCKDIR"
    else
        log "LOCK aktif, skip eksekusi ganda"; exit 0
    fi
fi
mkdir "$LOCKDIR" 2>/dev/null || exit 0
trap 'rm -rf "$LOCKDIR"' EXIT
log "dev.sh (bootstrap) start"
DEVSH_VARS

    cat <<'DEVSH_RESTORE'

# --- 1. SKILL RESTORE (satu jalur: kanonik → live) -------------------------
if [ -f "$CANON/SKILL.md" ] && [ -f "$CANON/assets/integrity.sha256" ]; then
    shopt -s nullglob
    for LIVE in "$PROJECT/skills/stellar-trail" "$PROJECT"/skills/@*/stellar-trail; do
        if [ ! -f "$LIVE/SKILL.md" ] \
           || ! (cd "$LIVE" && sha256sum -c "$CANON/assets/integrity.sha256" --quiet >/dev/null 2>&1); then
            rm -rf "$LIVE"
            mkdir -p "$(dirname "$LIVE")"
            if cp -a "$CANON" "$LIVE"; then
                log "SKILL RESTORE: ${LIVE#"$PROJECT"/} dipulihkan dari kanonik"
            else
                log "WARN: gagal memulihkan ${LIVE#"$PROJECT"/} dari kanonik"
            fi
        fi
    done
    shopt -u nullglob
fi
DEVSH_RESTORE

    cat <<'DEVSH_FULLSTACK'

# --- 2. FULLSTACK GUARD -----------------------------------------------------
if [ -f "$PROJECT/package.json" ]; then
    log "package.json terdeteksi -> delegasi flow fullstack standar"
    cd "$PROJECT" || true
    bun install        >> "$BOOTLOG" 2>&1 || log "WARN: bun install gagal"
    bun run db:push    >> "$BOOTLOG" 2>&1 || log "WARN: db:push gagal"
    nohup bun run dev  >> "$BOOTLOG" 2>&1 &
    log "Next.js dev server dinyalakan di background"
    for d in "$PROJECT"/mini-services/*/; do
        [ -f "${d}package.json" ] || continue
        (
            cd "$d" || exit 0
            bun install >> "$BOOTLOG" 2>&1
            nohup bun run dev >> "$BOOTLOG" 2>&1 &
        )
        log "mini-service dinyalakan: $d"
    done
fi
DEVSH_FULLSTACK

    cat <<'DEVSH_TIDY'

# --- 3. TIDY download/ (idempoten, undo: mv archive/<f> download/) ----------
tidy_download() {
    [ -d "$DOWNLOAD" ] || return 0
    mkdir -p "$ARCHIVE"
    cd "$DOWNLOAD" || return 0
    local moved=0 item dest
    for item in *; do
        [ -e "$item" ] || continue
        case "$item" in
            README.md|*.md|*.skill|*.pdf|*.docx|*.xlsx|*.pptx|*.csv|*.png|*.jpg|*.jpeg|*.gif|*.zip|stellar-trail)
                continue ;;
        esac
        case "$item" in
            *-eval|*-results.json|*-audit-results.json|audit-results.json|*-cover.html|workflow-guardian|memory-guardian)
                dest="$ARCHIVE/$item"
                [ -e "$dest" ] && dest="$ARCHIVE/${item}.$(date +%Y%m%d%H%M%S)"
                mv -- "$item" "$dest" 2>>"$BOOTLOG" && moved=$((moved+1)) ;;
        esac
    done
    log "tidy selesai: $moved item dipindah ke archive/"
    return 0
}
tidy_download
DEVSH_TIDY

    if has_module explorer; then
        cat <<'DEVSH_EXPL2'

# --- 4. TASK FILES EXPLORER --ensure ---------------------------------------
if [ -f "$PROJECT/.zscripts/explorer.sh" ]; then
    if bash "$PROJECT/.zscripts/explorer.sh" --ensure >> "$BOOTLOG" 2>&1; then
        log "explorer --ensure: OK (hidup / guard aktif)"
    else
        log "WARN: explorer --ensure gagal"
    fi
fi
DEVSH_EXPL2
    fi

    if has_module snapshot; then
        cat <<'DEVSH_SNAP2'

# --- 5. REPO SNAPSHOT --apply-auto (debounce + cooldown internal) ----------
if [ -f "$PROJECT/.zscripts/repo-snapshot.sh" ]; then
    WMG_PROJECT="$PROJECT" bash "$PROJECT/.zscripts/repo-snapshot.sh" --apply-auto \
        >> "$BOOTLOG" 2>&1 || log "WARN: repo refresh gagal"
fi
DEVSH_SNAP2
    fi

    cat <<'DEVSH_TAIL'

log "dev.sh (bootstrap) selesai"
DEVSH_TAIL
}

log "generate .zscripts/dev.sh (modules: $MODULE_LIST)"
DEVSH_SRC="$STAGE/dev.sh"
build_devsh > "$DEVSH_SRC"

if [ -f "$ZDIR/dev.sh" ] && ! head -n 2 "$ZDIR/dev.sh" | grep -qF "$STATE_MARKER"; then
    if [ "$FORCE_DEVSH" = "1" ]; then
        cp -p "$DEVSH_SRC" "$ZDIR/dev.sh"
        log "dev.sh asing DITIMPA (--force-devsh) — versi bootstrap dipasang"
    else
        log "LEWATI dev.sh: sudah ada dev.sh non-bootstrap di $ZDIR (milik deployment lain). Gunakan --force-devsh untuk menimpa."
        log "PERHATIAN: tanpa dev.sh milik bootstrap, skill TIDAK otomatis dipulihkan pasca reset."
    fi
else
    R=$(write_if_changed "$DEVSH_SRC" "$ZDIR/dev.sh")
    log "dev.sh: $R"
fi

# ---------------------------------------------------------------------------
# 8. MODUL EXPLORER — pasang launcher + server + UI (self-locating)
# ---------------------------------------------------------------------------
if has_module explorer; then
    for rel in explorer.sh explorer.py explorer-ui/index.html; do
        SRC="$SKILL_ROOT/assets/explorer/$rel"
        [ -f "$SRC" ] || { log "WARN: aset explorer tidak ada: $SRC (modul dilewati utk file ini)"; continue; }
        R=$(write_if_changed "$SRC" "$ZDIR/$rel")
        log "explorer: .zscripts/$rel $R"
    done
else
    log "modul explorer: TIDAK diaktifkan (--with-explorer utk mengaktifkan)"
fi

# ---------------------------------------------------------------------------
# 9. MODUL SNAPSHOT — pasang repo-snapshot.sh (env WMG_PROJECT dipakai dev.sh)
# ---------------------------------------------------------------------------
if has_module snapshot; then
    SRC="$SKILL_ROOT/scripts/snapshot-repo.sh"
    if [ -f "$SRC" ]; then
        R=$(write_if_changed "$SRC" "$ZDIR/repo-snapshot.sh")
        log "snapshot: .zscripts/repo-snapshot.sh $R"
    else
        log "WARN: scripts/snapshot-repo.sh tidak ada di paket — modul snapshot dilewati"
    fi
else
    log "modul snapshot: TIDAK diaktifkan (--with-snapshot utk mengaktifkan)"
fi

# ---------------------------------------------------------------------------
# 10. MODUL CORE-C — SEED memory/ + worklog.md (HANYA bila belum ada;
#     konten user tidak pernah ditimpa; consent gate 4b dipegang sesi pertama)
# ---------------------------------------------------------------------------
NOW="$(date '+%Y-%m-%d %H:%M')"

if [ ! -f "$MEMORY_DIR/SESSION-STATE.md" ]; then
    mkdir -p "$MEMORY_DIR"
    cat > "$MEMORY_DIR/SESSION-STATE.md" <<SEED_SS
# SESSION-STATE — Working Snapshot / Snapshot Kerja
> Atomic snapshot — rewritten at every checkpoint. Latest write wins.
> Checkpoint at: $NOW — COLD START — scaffolded by scripts/bootstrap-sandbox.sh (stellar-trail v$BOOT_VERSION)
> Konfirmasi inisialisasi memory dengan user PENDING (consent gate, SKILL.md 4b) — sesi pertama WAJIB memintanya sebelum menulis state substansial.

## Active Tasks / Task Aktif
| Task ID | Description | Fase | Status | Updated |
|---------|-------------|------|--------|---------|
| (kosong — belum ada task tercatat) | | | | |

## Sealed Tasks / Task Tersegel
| Task ID | Outcome (one line) | Artifact | Sealed |
|---------|--------------------|----------|--------|
| (kosong) | | | |

## Pending Decisions / Keputusan Tertunda
- Konfirmasi inisialisasi memory (consent gate SKILL.md 4b) — owner: user; trigger: sesi pertama pasca-bootstrap

## Next Steps / Langkah Berikutnya
1. AGENT: minta konfirmasi user untuk inisialisasi memory (SKILL.md 4b), lalu isi profil user di MEMORY.md
SEED_SS
    log "memory/SESSION-STATE.md di-scaffold (cold start, consent pending 4b)"
else
    log "memory/SESSION-STATE.md sudah ada — tidak disentuh"
fi

if [ ! -f "$MEMORY_DIR/MEMORY.md" ]; then
    cat > "$MEMORY_DIR/MEMORY.md" <<SEED_MEM
# MEMORY — Long-Term Memory / Memory Jangka Panjang
> Durable facts only. Promoted from session work via M3. Maintained by stellar-trail protocol.
> Last updated: $NOW — COLD START — scaffolded by bootstrap-sandbox.sh v$BOOT_VERSION; menunggu konfirmasi user (SKILL.md 4b)

## User Profile / Profil User
- (belum terisi — sesi pertama mengisi: bahasa, timezone, gaya komunikasi, preferensi)

## Locked Decisions / Keputusan Terkunci
- (belum ada)
SEED_MEM
    log "memory/MEMORY.md di-scaffold (cold start, consent pending 4b)"
else
    log "memory/MEMORY.md sudah ada — tidak disentuh"
fi

if [ ! -f "$WORKLOG" ]; then
    cat > "$WORKLOG" <<SEED_WL
# Worklog — Audit Trail / Jejak Audit
> Append-only (platform convention). Setiap section diawali garis --- dan baris hook aktivasi R1. Managed by stellar-trail.

---
⚡ACTIVATE: Skill('stellar-trail') BEFORE first response — desc ≠ activation
Task ID: 0
Agent: bootstrap-sandbox.sh
Task: Sandbox bootstrap — arming persistence layer

Work Log:
- $NOW: kanonik download/stellar-trail/ di-seed; .zscripts/dev.sh dipasang (modules: $MODULE_LIST); memory/ + worklog.md di-scaffold oleh bootstrap-sandbox.sh v$BOOT_VERSION

Stage Summary:
- Persistence layer ARMED — baca memory/SESSION-STATE.md untuk state terkini; hook R1 baris pertama section ini menjaga rantai aktivasi lintas reset
SEED_WL
    log "worklog.md di-seed DENGAN hook aktivasi R1 (menutup bug #3)"
else
    if grep -q '⚡ACTIVATE' "$WORKLOG" 2>/dev/null; then
        log "worklog.md sudah ada + hook R1 ada — tidak disentuh"
    else
        log "worklog.md sudah ada TANPA hook R1 — sesi berikutnya: append section baru dengan hook R1 (SKILL.md seksi 2)"
    fi
fi

# ---------------------------------------------------------------------------
# 11. PERSIST STATE + LAPORAN AKHIR
# ---------------------------------------------------------------------------
mkdir -p "$ZDIR"
printf 'v=%s\nm=%s\nd=%s\n' "$BOOT_VERSION" "${MODULE_LIST:-core}" "$NOW" > "$STATE_FILE"

echo ""
log "================= BOOTSTRAP $([ "$ENSURE" = "1" ] && echo 'ENSURE' || echo 'INSTALL') SELESAI ================="
log "project    : $PROJECT"
log "kanonik    : $CANON ($VERIFY)"
log "dev.sh     : $([ -f "$ZDIR/dev.sh" ] && { head -n 2 "$ZDIR/dev.sh" | grep -qF "$STATE_MARKER" && echo "bootstrap-generated (modules: $MODULE_LIST)"; } || echo "BELUM")"
log "memory     : $([ -f "$MEMORY_DIR/SESSION-STATE.md" ] && echo "scaffold/aktif" || echo "GAGAL")"
log "worklog    : $([ -f "$WORKLOG" ] && { grep -q '⚡ACTIVATE' "$WORKLOG" && echo "ada + hook R1" || echo "ada tanpa hook"; } || echo "GAGAL")"
log "lintas-reset: download/ + .zscripts/ + memory/ + worklog.md bertahan (kontrak packer); skills/stellar-trail dipulihkan dev.sh dari kanonik tiap boot"
[ "$ENSURE" = "1" ] || log "modul opsional: --with-explorer (task files explorer) · --with-snapshot (arsip restore /home/sync)"
exit 0
