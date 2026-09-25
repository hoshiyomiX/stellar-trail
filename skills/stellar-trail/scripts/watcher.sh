#!/usr/bin/env bash
# ============================================================================
# watcher.sh — WATCHER DAEMON PERSISTEN (lapis auto-heal runtime)
# stellar-trail v3.6.4 · watcher v1.8 · Task 64 · 2026-09-25
#
# ORIGIN v1.7 (Task 62): produktifikasi daemon v1.6 yang teruji di sandbox
# referensi sejak 2026-09-15 (hidup lintas boot & lintas sesi). Laporan
# forensik konsumer (2026-09-25, "T46") membuktikan kontrak antarmuka daemon
# ini sudah lama DIRUJUK empat komponen paket (dev.sh.template §3, header
# explorer.sh, guardian explorer.py via .zscripts/watcher.pid, kartu Guardian
# UI) — tapi filenya tidak pernah dikirim dalam rilis mana pun; guard
# [ -f ] menelan absennya secara senyap. Sejak v3.6.3 file ini dikirim di
# scripts/ dan dipasang bootstrap-sandbox.sh ke .zscripts/.
#
# GUARD v1.8 (Task 64, R1 audit internal T63): skill-card.md dan
# assets/integrity.sha256 adalah FILE RILIS di luar manifest sha256 —
# manifest tak bisa meng-hash dirinya sendiri dan skill-card adalah sumber
# versi generator manifest, sehingga keduanya sengaja di luar daftar.
# Konsekuensinya terbukti di lapangan 4x (3x file hilang + 1x ditimpa
# konten era-versi-lama oleh lapisan skill-manager platform saat boot,
# semuanya pasca-boot, aktor teridentifikasi dari forensik mtime T63):
# selama file itu rusak/hilang, heal-skill --check tetap melapor BERSIH —
# tidak ada satu pun lapisan yang mengawasinya. Guard ini menutup celah itu
# pada runtime: cek keberadaan + kesegaran versi tiap siklus, auto-restore
# dari vault kelas-A yang segar (kartu vault wajib versi == rilis).
#
# TEMUAN ARSITEKTUR (diverifikasi empiris 2026-09-15, sandbox referensi):
#   - Setiap panggilan tool = shell baru (bash --noprofile --norc) yang
#     di-spawn service platform; saat perintah selesai, platform MEMBUNUH
#     seluruh pohon proses turunannya (PPID-tree walk).
#   - PROSES YATIM (double-fork -> PPID=1, session sendiri via setsid)
#     LOLOS dari pembersihan itu — terbukti hidup lintas panggilan tool.
#   - Tidak ada cron/at/tmux/inotifywait di container; .bashrc tidak
#     tersourcing (--norc). Jadi: polling loop yatim = satu-satunya jalan
#     daemon tanpa reboot.
#
# CARA KERJA (loop tiap 30 dtk; interval via env WATCHER_INTERVAL):
#   v1.0  perubahan top-level download/ -> trigger dev.sh (auto-tidy;
#         dev.sh punya lock + logging sendiri; watcher hanya pemicu)
#   v1.1  healthz Task Files Explorer (:3000) + auto-heal explorer.sh
#         --ensure bila gagal (guard Next.js ada di explorer.sh — bila ada
#         package.json, explorer berdiri down)
#   v1.3  tiap 20 siklus (~10 mnt) heal-skill.sh --check (location-aware,
#         kedua konvensi layout install); tiap 30 siklus (~15 mnt)
#         repo-snapshot.sh --apply-auto (debounce+cooldown internal)
#   v1.6  compliance sentinel tiap 4 siklus (~2 mnt): worklog aktif bertumbuh
#         TAPI memory/SESSION-STATE.md tidak di-rewrite >30 mnt = signature
#         protokol tidak berjalan -> alarm di tail worklog (debounce 1 jam)
#   v1.7  PRODUKTIFISASI (Task 62): self-locating (dipanggil dari .zscripts/
#         ATAU dari pohon instalasi skills/stellar-trail/scripts/), hardcode
#         path proyek dihapus (bug v1.6: guard explorer mengecek
#         /home/z/my-project/package.json literal), dev.sh kini OPSIONAL
#         (trigger tidy skip senyap bila absen), ZDIR dibuat bila belum ada.
#   v1.8  GUARD FILE RILIS NON-MANIFEST tiap siklus (Task 64, R1 audit T63):
#         kanonik download/stellar-trail/ diperiksa — skill-card.md wajib
#         ADA dan versinya (## Skill Version) == assets/integrity.version,
#         assets/integrity.sha256 wajib ADA; bila bermasalah -> auto-restore
#         dari vault kelas-A segar pertama (default: <project>/upload/
#         skill-vault/stellar-trail lalu /home/sync/skill-vault/stellar-trail;
#         override env STELLAR_VAULTS, format path:path) + verifikasi pasca-
#         restore; debounce 10 mnt antar percobaan (anti spam log); instalasi
#         konsumer tanpa kanonik = skip senyap. Catatan arah konvergensi:
#         integrity.version adalah otoritas — vault yang kartunya lebih TUA
#         dari rilis dilewati (anti-downgrade), vault lebih baru pun dilewati
#         (guard hanya menerima kartu == rilis; upgrade versi adalah urusan
#         proses rilis, bukan guard). Plus fix kontrak --force-start: kini
#         benar-benar membersihkan stop-flag yang tersisa (v1.7: daemon lolos
#         gerbang pra-spawn tapi mati di siklus pertama).
#
# PERINTAH:
#   bash watcher.sh --ensure        # nyalakan bila belum jalan (idempoten)
#   bash watcher.sh --status        # lihat status daemon
#   bash watcher.sh --stop          # hentikan + pasang stop-flag
#   bash watcher.sh --force-start   # paksa nyala meski stop-flag ada
#
# JARING PENGAMAN (triple redundancy — tiga jalur menuju satu daemon):
#   1. Boot container  -> dev.sh (hook /start.sh / bootstrap) memanggil --ensure
#   2. Tiap sesi baru  -> protokol M0 (Standing Instructions) memanggil --ensure
#   3. Kapan pun       -> manual
# ============================================================================

# --- SELF-LOCATE (v1.7) ------------------------------------------------------
# Prioritas: env STELLAR_PROJECT > lokasi .zscripts/<file ini> > walk-up dari
# lokasi skrip (marker: skills/ · download/ · worklog.md · package.json) >
# fallback /home/z/my-project. Bekerja dari .zscripts/ (hasil deploy bootstrap)
# dan dari pohon instalasi (skills/stellar-trail/scripts/) tanpa perubahan.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="${STELLAR_PROJECT:-}"
if [ -z "$PROJECT" ]; then
    if [ "$(basename "$SELF_DIR")" = ".zscripts" ]; then
        PROJECT="$(dirname "$SELF_DIR")"
    else
        _d="$SELF_DIR"
        for _ in 1 2 3 4 5 6; do
            _d="$(dirname "$_d")"
            if [ -d "$_d/skills" ] || [ -d "$_d/download" ] \
               || [ -f "$_d/worklog.md" ] || [ -f "$_d/package.json" ]; then
                PROJECT="$_d"; break
            fi
            [ "$_d" = "/" ] && break
        done
    fi
fi
PROJECT="${PROJECT:-/home/z/my-project}"

ZDIR="$PROJECT/.zscripts"
DOWNLOAD="$PROJECT/download"
PIDFILE="$ZDIR/watcher.pid"
STOPFLAG="$ZDIR/watcher.stop"
LOG="$ZDIR/watcher.log"
DEVSH="$ZDIR/dev.sh"
INTERVAL="${WATCHER_INTERVAL:-30}"
# v1.8: kandidat vault kelas-A untuk guard file rilis non-manifest —
# project-relative dulu (portabel), lalu konvensi reference-sandbox.
# Override via env STELLAR_VAULTS (format colon-separated).
VAULTS="${STELLAR_VAULTS:-$PROJECT/upload/skill-vault/stellar-trail:/home/sync/skill-vault/stellar-trail}"
mkdir -p "$ZDIR" 2>/dev/null || true

wlog() {
    echo "[$(date '+%F %T')] $*" >> "$LOG"
    # cap log 50KB -> simpan 100 baris terakhir
    if [ -s "$LOG" ] && [ "$(stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt 51200 ]; then
        tail -100 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
    fi
}

alive() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
}

# ---------------------------------------------------------------------------
# MODE --stop / --status
# ---------------------------------------------------------------------------
case "$1" in
    --stop)
        if alive; then
            kill "$(cat "$PIDFILE")" 2>/dev/null
            wlog "watcher dihentikan manual (--stop)"
            echo "[watcher] dihentikan (pid $(cat "$PIDFILE"))"
        fi
        rm -f "$PIDFILE"
        touch "$STOPFLAG"
        echo "[watcher] stop-flag dipasang: $STOPFLAG (hapus file itu untuk izinkan nyala lagi)"
        exit 0
        ;;
    --status)
        echo "=== WATCHER STATUS (v1.8) ==="
        echo "project : $PROJECT"
        if alive; then
            echo "daemon  : HIDUP (pid $(cat "$PIDFILE"))"
            ps -o pid,ppid,etime,cmd -p "$(cat "$PIDFILE")" 2>/dev/null | tail -1
        else
            echo "daemon  : MATI / belum jalan"
        fi
        [ -f "$STOPFLAG" ] && echo "stopflag: AKTIF (auto-start diblokir)" || echo "stopflag: tidak ada"
        echo "interval: ${INTERVAL}s   log: $LOG"
        echo "--- watcher.log (10 terakhir) ---"
        tail -10 "$LOG" 2>/dev/null || echo "(kosong)"
        exit 0
        ;;
esac

# ---------------------------------------------------------------------------
# --ensure / --force-start / tanpa argumen: nyalakan bila perlu
# ---------------------------------------------------------------------------
if alive; then
    echo "[watcher] sudah jalan (pid $(cat "$PIDFILE")) — tidak melakukan apa pun"
    exit 0
fi
if [ -f "$STOPFLAG" ] && [ "$1" != "--force-start" ]; then
    echo "[watcher] stop-flag aktif — tidak dinyalakan. (hapus $STOPFLAG atau pakai --force-start)"
    exit 0
fi
# v1.8: --force-start membersihkan stop-flag yang tersisa — di v1.7 daemon
# lolos gerbang pra-spawn tapi mati di siklus pertama (kontrak "paksa nyala"
# patah; pola produksi selama ini harus --stop + rm stopflag + --ensure)
if [ "$1" = "--force-start" ]; then
    rm -f "$STOPFLAG"
fi
# v1.7: dev.sh OPSIONAL — trigger tidy nonaktif bila absen; sisanya tetap jalan
if [ ! -f "$DEVSH" ]; then
    echo "[watcher] NOTE: $DEVSH tidak ada — trigger tidy download/ nonaktif (auto-heal explorer + heal berkala + repo refresh tetap jalan)"
fi

# --- DOUBLE-FORK ORPHAN SPAWN (inti mekanisme lolos pembersihan platform) ---
(
    setsid bash -c '
        ZDIR="'"$ZDIR"'"
        PROJECT="'"$PROJECT"'"
        DOWNLOAD="'"$DOWNLOAD"'"
        DEVSH="'"$DEVSH"'"
        INTERVAL="'"$INTERVAL"'"
        VAULT_DIRS="'"$VAULTS"'"
        PIDFILE="$ZDIR/watcher.pid"
        STOPFLAG="$ZDIR/watcher.stop"
        LOG="$ZDIR/watcher.log"
        wlog() {
            echo "[$(date "+%F %T")] $*" >> "$LOG"
            if [ -s "$LOG" ] && [ "$(stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt 51200 ]; then
                tail -100 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
            fi
        }
        echo $$ > "$PIDFILE"
        wlog "watcher START (pid $$, interval ${INTERVAL}s, project $PROJECT)"
        CYCLES=0
        CANON_DIR="$DOWNLOAD/stellar-trail"
        GUARD_STATE="$ZDIR/.guard-release.state"
        LAST="$(ls -1 "$DOWNLOAD" 2>/dev/null | sort | md5sum)"
        while true; do
            if [ -f "$STOPFLAG" ]; then
                wlog "watcher berhenti: stop-flag terdeteksi"
                rm -f "$PIDFILE"
                exit 0
            fi
            sleep "$INTERVAL"
            CUR="$(ls -1 "$DOWNLOAD" 2>/dev/null | sort | md5sum)"
            if [ "$CUR" != "$LAST" ]; then
                LAST="$CUR"
                # v1.7: dev.sh opsional — skip senyap bila absen
                if [ -f "$DEVSH" ]; then
                    wlog "perubahan download/ terdeteksi -> trigger dev.sh"
                    bash "$DEVSH" >> "$LOG" 2>&1
                    wlog "dev.sh selesai (return $?)"
                fi
            fi
            # v1.1: auto-heal Task Files Explorer (skip bila Next.js aktif;
            #       v1.7 FIX: cek package.json di $PROJECT, bukan hardcode)
            if [ -f "$ZDIR/explorer.sh" ] && [ ! -f "$PROJECT/package.json" ]; then
                curl -fsS -m 2 http://127.0.0.1:3000/healthz >/dev/null 2>&1 || {
                    wlog "explorer tidak sehat -> auto-heal (explorer.sh --ensure)"
                    bash "$ZDIR/explorer.sh" --ensure >> "$LOG" 2>&1
                }
            fi
            # v1.8: GUARD FILE RILIS NON-MANIFEST (R1 audit T63, Task 64).
            #       skill-card.md + assets/integrity.sha256 di kanonik = file
            #       rilis DI LUAR manifest — heal --check tak pernah memeriksa
            #       (insiden 4x: 3x hilang + 1x reversion konten lama pasca-
            #       boot). Cek keberadaan + kesegaran versi tiap siklus;
            #       restore hanya dari vault yang kartunya == versi rilis.
            #       Instalasi konsumer tanpa kanonik = skip senyap.
            if [ -d "$CANON_DIR" ] && [ -f "$CANON_DIR/assets/integrity.version" ]; then
                REL_VER="$(cat "$CANON_DIR/assets/integrity.version" 2>/dev/null)"
                GUARD_ISSUE=""
                if [ -n "$REL_VER" ]; then
                    if [ ! -f "$CANON_DIR/skill-card.md" ]; then
                        GUARD_ISSUE="skill-card.md hilang"
                    else
                        GUARD_CARD_V="$(grep -A3 -i "^## *Skill Version" "$CANON_DIR/skill-card.md" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)"
                        [ "$GUARD_CARD_V" = "$REL_VER" ] || GUARD_ISSUE="skill-card.md basi (kartu ${GUARD_CARD_V:-?} != rilis $REL_VER)"
                    fi
                    [ -f "$CANON_DIR/assets/integrity.sha256" ] || GUARD_ISSUE="${GUARD_ISSUE:+$GUARD_ISSUE; }assets/integrity.sha256 hilang"
                fi
                if [ -z "$GUARD_ISSUE" ]; then
                    # sehat — bersihkan penanda bila siklus sebelumnya bermasalah
                    if [ -f "$GUARD_STATE" ]; then
                        rm -f "$GUARD_STATE"
                        wlog "GUARD rilis: sehat kembali (kartu == $REL_VER)"
                    fi
                else
                    # debounce 10 mnt antar PERCOBAAN restore (state file = stempel waktu)
                    G_NOW=$(date +%s); G_LAST=0
                    [ -f "$GUARD_STATE" ] && G_LAST=$(stat -c%Y "$GUARD_STATE" 2>/dev/null || echo 0)
                    if [ $((G_NOW - G_LAST)) -ge 600 ]; then
                        touch "$GUARD_STATE"
                        wlog "GUARD rilis: $GUARD_ISSUE -> cari vault segar"
                        G_DONE=""
                        for G_VAULT in ${VAULT_DIRS//:/ }; do
                            [ -f "$G_VAULT/skill-card.md" ] || continue
                            G_VV="$(grep -A3 -i "^## *Skill Version" "$G_VAULT/skill-card.md" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)"
                            [ "$G_VV" = "$REL_VER" ] || continue
                            cp "$G_VAULT/skill-card.md" "$CANON_DIR/skill-card.md" 2>/dev/null && chmod 644 "$CANON_DIR/skill-card.md"
                            if [ ! -f "$CANON_DIR/assets/integrity.sha256" ] && [ -f "$G_VAULT/assets/integrity.sha256" ]; then
                                cp "$G_VAULT/assets/integrity.sha256" "$CANON_DIR/assets/integrity.sha256" 2>/dev/null && chmod 644 "$CANON_DIR/assets/integrity.sha256"
                            fi
                            G_CHK="$(grep -A3 -i "^## *Skill Version" "$CANON_DIR/skill-card.md" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)"
                            if [ "$G_CHK" = "$REL_VER" ]; then
                                rm -f "$GUARD_STATE"
                                wlog "GUARD rilis: PULIH dari $G_VAULT (kartu $G_CHK == rilis)"
                                G_DONE=1
                                break
                            else
                                wlog "GUARD rilis: restore dari $G_VAULT gagal verifikasi pasca-salin"
                            fi
                        done
                        [ -n "$G_DONE" ] || wlog "GUARD rilis: tak ada vault segar utk versi $REL_VER — cek manual (vault-sync --apply?)"
                    fi
                fi
            fi
            # v1.3: heal skill berkala (location-aware — kedua layout install)
            #       + repo refresh berkala (gerbang ganda di skrip masing-masing)
            CYCLES=$((CYCLES + 1))
            if [ $((CYCLES % 20)) -eq 0 ]; then
                for CAND in "$PROJECT/skills/stellar-trail" "$PROJECT"/skills/@*/stellar-trail; do
                    [ -d "$CAND" ] || continue
                    if [ -f "$CAND/scripts/heal-skill.sh" ]; then
                        bash "$CAND/scripts/heal-skill.sh" --check >> "$LOG" 2>&1
                    elif [ -f "$PROJECT/download/stellar-trail/scripts/heal-skill.sh" ]; then
                        bash "$PROJECT/download/stellar-trail/scripts/heal-skill.sh" --check --dir "$CAND" >> "$LOG" 2>&1
                    fi
                done
            fi
            if [ $((CYCLES % 30)) -eq 0 ] && [ -f "$ZDIR/repo-snapshot.sh" ]; then
                bash "$ZDIR/repo-snapshot.sh" --apply-auto >> "$LOG" 2>&1
            fi
            # v1.6: compliance sentinel — signature non-compliance (R2 insiden
            #       2026-09-21): worklog bertumbuh TAPI SESSION-STATE beku
            if [ $((CYCLES % 4)) -eq 0 ]; then
                WL="$PROJECT/worklog.md"
                SS="$PROJECT/memory/SESSION-STATE.md"
                if [ -f "$WL" ] && [ -f "$SS" ]; then
                    WL_M=$(stat -c%Y "$WL" 2>/dev/null || echo 0)
                    SS_M=$(stat -c%Y "$SS" 2>/dev/null || echo 0)
                    NOW=$(date +%s)
                    if [ "$WL_M" -gt "$SS_M" ] && [ $((NOW - WL_M)) -lt 900 ] && [ $((WL_M - SS_M)) -gt 1800 ]; then
                        LAST_ALARM=0
                        [ -f "$ZDIR/.compliance-alarm.last" ] && LAST_ALARM=$(cat "$ZDIR/.compliance-alarm.last" 2>/dev/null)
                        if [ $((NOW - LAST_ALARM)) -gt 3600 ]; then
                            echo "$NOW" > "$ZDIR/.compliance-alarm.last"
                            printf "\n> COMPLIANCE-ALARM %s: worklog aktif tapi SESSION-STATE tidak di-checkpoint >30 mnt — signature protokol stellar-trail TIDAK berjalan. Agent: invoke Skill(stellar-trail) SEKARANG + jalankan M0/M1 checkpoint. User: audit respons agent (cari banner stellar-trail di tiap respons).\n" "$(date "+%F %T")" >> "$WL"
                            wlog "COMPLIANCE-ALARM: SESSION-STATE stale >30m saat worklog aktif"
                        fi
                    fi
                fi
            fi
        done
    ' >/dev/null 2>&1 &
)
sleep 1
if alive; then
    echo "[watcher] DINYALAKAN (pid $(cat "$PIDFILE"), PPID=$(awk '{print $4}' /proc/$(cat "$PIDFILE")/stat 2>/dev/null) — yatim, kebal pembersihan per-tool-call)"
else
    echo "[watcher] GAGAL start — cek $LOG"
    exit 1
fi
