#!/usr/bin/env bash
# ============================================================================
# repo-snapshot.sh — REFRESH /home/sync/repo.tar (anti pre-stop gagal)
# v1.4 — bundled asset skill stellar-trail v3.3.1; salinan hidup proyek:
#        <proyek>/.zscripts/repo-snapshot.sh (konten identik — jaga tetap sync)
#
# CHANGELOG v1.4 (Task 27, stellar-trail v3.3.0):
#   - Lapis shadow backup DIHAPUS TOTAL (user verdict: worthless — forensik
#     insiden 07:38: deteksi stale false-positive, blind spot & failure domain
#     sama dgn arsip yang diamankan, 62MB tulis/30 mnt). Tidak ada lagi
#     backup oportunistik dari --apply-auto.
#   - Direktori state dipecah: WMG_ORIG_DIR (backup repo.tar asli, default
#     $WMG_SYNC/repo-originals — alias legacy WMG_SHADOW_DIR tetap dihormati)
#     dan WMG_STATE_DIR (marker debounce/cooldown/fingerprint, default
#     $WMG_SYNC/repo-state). wmg-shadow/ tidak dipakai lagi.
#
# CHANGELOG v1.3 (Task 26 — arsitektur resilience v2):
#   - MODE BARU --apply-auto: refresh dengan gerbang ganda — debounce
#     (perubahan material sejak apply terakhir) + cooldown 15 menit;
#     dipanggil otomatis oleh boot hook & watcher berkala.
#     --apply manual tetap tanpa gerbang (force).
#   - build_tar MENYERTAKAN skills/stellar-trail (append bedah via tar -rf;
#     official skills lain tetap di-exclude) — menutup celah "skills/
#     tidak pernah ikut repo.tar", penyebab degrade pasca restart 07:37 UTC.
#
# CHANGELOG v1.2 (respons temuan clawscan v2.2.1 "tar command-injection"):
#   - build_tar memakai daftar NUL-terpisah via 'tar --null -T' — nama entri
#     TIDAK PERNAH di-parse sebagai opsi tar, menutup vektor argument
#     injection (file bernama '--use-compress-program=...' di project root
#     tidak bisa membuat tar mengeksekusi perintah)
#   - top_entries SKIP nama mencurigakan: diawali '-' (bisa dibaca sebagai
#     opsi oleh tool lain) atau berisi newline — pertahanan berlapis
#
# CHANGELOG v1.1 (respons temuan keamanan clawscan v2.2.0 "unsafe tar invocation"):
#   - audit member baru: tar yang dipasang di jalur restore boot WAJIB bebas
#     path traversal (member absolut atau berkomponen '..' DITOLAK keras;
#     symlink ber-target absolut diberi peringatan) — /start.sh mengekstrak
#     repo.tar via 'tar xf' tanpa proteksi member, jadi pemeriksaan ada di sini
#   - --restore-original DIVERIFIKASI sebelum swap (struktur + audit member):
#     undo tetap byte-identical, tetapi arsip korup/hostile DITOLAK agar
#     tidak merusak boot berikutnya; backup asli tidak pernah dihapus
#
# MASALAH YANG DISEMBUHKAN:
#   /home/sync/repo.tar adalah satu-satunya sumber restore boot container
#   (dibaca /start.sh: rm -rf project kecuali upload -> tar xf repo.tar).
#   Tar ini normalnya ditulis ulang oleh PRE-STOP platform saat container
#   berhenti — tetapi pre-stop TIDAK SELALU jalan (crash, force-kill, pack
#   gagal; cabang ini diakui sendiri oleh start.sh). Bila itu terjadi, boot
#   berikutnya me-restore kondisi lama = rollback diam-diam.
#
# SOLUSI: refresh repo.tar dengan snapshot kondisi TERKINI, sehingga restore
#   boot SELALU mendapat state segar terlepas dari nasib pre-stop. Lapis
#   pendampingnya: heal-skill.sh (self-heal instalasi dari kanonik/arsip ini)
#   dan --restore-original (undo).
#
# KOMPATIBILITAS FORMAT (hasil forensik Task 16-d):
#   - entri relatif TANPA prefix ./ (mis. ".zscripts/dev.sh", "worklog.md")
#   - packer platform mengecualikan: skills/, node_modules/, db/
#   - upload/ dikecualikan (mount OSS terpisah, ikut di-skip saat ekstraksi
#     oleh start.sh --exclude); .venv/.next = artefak build, ikut dikecualikan
#   - start.sh menoleransi tar korup (warning + lanjut) — non-fatal, dan
#     skrip ini memverifikasi tar SEBELUM swap + mem-backup yang asli dulu.
#
# KEAMANAN SWAP (teruji empiris di ossfs):
#   build di /tmp (lokal, cepat) -> verifikasi (struktur + audit member)
#   -> backup asli ke repo-originals/ -> salin ke .repo.tar.staged (satu mount)
#   -> mv rename-overwrite (didukung ossfs, uji 2026-09-16) -> verifikasi
#   akhir. Restore-original pun diverifikasi (struktur + member) sebelum swap.
#
# PERINTAH:
#   repo-snapshot.sh --status             # diagnosis usia repo.tar (default)
#   repo-snapshot.sh --dry-run            # build + verifikasi, TANPA swap
#   repo-snapshot.sh --apply              # backup asli -> build -> swap -> verify
#   repo-snapshot.sh --apply-auto         # --apply dengan gerbang ganda (berkala)
#   repo-snapshot.sh --restore-original   # kembalikan repo.tar asli terakhir
#
# Override sandbox: WMG_PROJECT, WMG_SYNC, WMG_ORIG_DIR (alias legacy:
# WMG_SHADOW_DIR), WMG_STATE_DIR, WMG_TMP
# Exit: 0 sukses/tidak ada aksi · 1 gagal · 2 salah pakai
# ============================================================================
WMG_PROJECT="${WMG_PROJECT:-/home/z/my-project}"
WMG_SYNC="${WMG_SYNC:-/home/sync}"
WMG_ORIG_DIR="${WMG_ORIG_DIR:-${WMG_SHADOW_DIR:-$WMG_SYNC/repo-originals}}"
WMG_STATE_DIR="${WMG_STATE_DIR:-$WMG_SYNC/repo-state}"
WMG_TMP="${WMG_TMP:-/tmp}"
TAR_PATH="$WMG_SYNC/repo.tar"
LOG="$WMG_PROJECT/.zscripts/boot.log"
KEEP_ORIG=5                      # retensi backup repo.tar asli (rolling)
COOLDOWN_AUTO=900                # jarak minimum antar --apply-auto (detik)

ts() { date '+%Y-%m-%d %H:%M:%S'; }
# selalu cetak ke stdout (skrip ini manual/diagnostik, bukan cron-silent)
slog() {
    echo "[repo-snap] $*"
    echo "[$(ts)] [repo-snap] $*" >> "$LOG" 2>/dev/null
}
# log-only TANPA stdout — wajib dipakai di fungsi yang memproduksi data di
# stdout (mis. top_entries): diagnostik yang bocor ke stdout akan terbaca
# sebagai entri daftar oleh pemanggilnya (bug nyata v1.2, tertangkap uji sandbox)
slog_q() {
    echo "[$(ts)] [repo-snap] $*" >> "$LOG" 2>/dev/null
}

# Entri top-level project mengikuti konvensi packer platform
EXCLUDE_TOP="skills node_modules db upload .venv .next"

top_entries() {
    local e name
    for e in "$WMG_PROJECT"/* "$WMG_PROJECT"/.[!.]*; do
        [ -e "$e" ] || continue
        name="$(basename "$e")"
        case " $EXCLUDE_TOP " in
            *" $name "*) continue ;;
        esac
        # anti argument-injection (v1.2): nama diawali '-' bisa dibaca sebagai
        # opsi oleh tool penerima daftar; nama ber-newline merusak format daftar.
        # slog_q (bukan slog): stdout fungsi ini adalah DATA daftar, bukan log.
        case "$name" in
            -*) slog_q "SKIP entri mencurigakan (diawali '-'): $name"; continue ;;
            *$'\n'*) slog_q "SKIP entri newline: $name"; continue ;;
        esac
        printf '%s\n' "$name"
    done
}

build_tar() {  # $1 = path output (lokal)
    # v1.2 anti command-injection: daftar entri NUL-terpisah via -T — nama file
    # TIDAK PERNAH mengenali sebagai opsi tar (beda dgn ekspansi $ents unquoted
    # yang memungkinkan file '--use-compress-program=...' dieksekusi).
    local list="$WMG_TMP/repo-snap-list-$$.nul"
    top_entries | while IFS= read -r e; do printf '%s\0' "$e"; done > "$list"
    [ -s "$list" ] || { slog "GAGAL: tidak ada entri top-level di $WMG_PROJECT"; rm -f "$list"; return 1; }
    if ! tar -cf "$1" --null -C "$WMG_PROJECT" -T "$list" 2>>"$LOG"; then
        rm -f "$list"; return 1
    fi
    rm -f "$list"
    # v1.3: append bedah skills/stellar-trail — path literal hardcoded (bukan
    # ekspansi nama file; vektor argument-injection v1.2 tidak berlaku).
    # Best-effort: gagal append tidak membatalkan apply (lapis utama untuk
    # skills/ tetap heal-skill.sh di boot hook).
    if [ -d "$WMG_PROJECT/skills/stellar-trail" ]; then
        if tar -rf "$1" -C "$WMG_PROJECT" skills/stellar-trail 2>>"$LOG"; then
            slog_q "append skills/stellar-trail: $(tar -tf "$1" 2>/dev/null | grep -c '^skills/stellar-trail') entri"
        else
            slog "WARN: gagal append skills/stellar-trail (non-fatal)"
        fi
    else
        slog_q "skip append skills/stellar-trail (belum ada — heal akan membuatnya)"
    fi
}

audit_members() {  # $1 = path tar, $2 = label; sukses = 0 (anti path-traversal)
    # /start.sh mengekstrak repo.tar via 'tar xf' TANPA validasi member —
    # member absolut/berkomponen '..' bisa menulis di luar project root.
    # Jalur restore boot adalah aset kritikal: audit ini tidak bisa di-skip.
    local t="$1" label="$2" bad
    bad="$(tar -tf "$t" 2>/dev/null \
          | awk 'BEGIN{FS="/"} /^\//{print; next} {for(i=1;i<=NF;i++) if($i==".."){print; break}}' \
          | head -2)"
    if [ -n "$bad" ]; then
        slog "GAGAL audit $label: member tidak aman: $(printf '%s' "$bad" | head -1)"
        return 1
    fi
    # best-effort: symlink member ber-target absolut (potensi escape saat ekstraksi)
    local sym
    sym="$(tar -tvf "$t" 2>/dev/null | awk '$1 ~ /^l/ && / -> \//' | head -2)"
    [ -z "$sym" ] || slog "PERINGATAN audit $label: symlink ber-target absolut terdeteksi — periksa manual"
    return 0
}

verify_tar() {  # $1 = path tar, $2 = label; sukses = 0
    local t="$1" label="$2" n
    [ -s "$t" ] || { slog "GAGAL verifikasi $label: file kosong/hilang"; return 1; }
    if ! tar -tf "$t" >/dev/null 2>&1; then
        slog "GAGAL verifikasi $label: struktur tar tidak valid"; return 1
    fi
    audit_members "$t" "$label" || return 1
    n="$(tar -tf "$t" 2>/dev/null | wc -l)"
    [ "$n" -ge 10 ] || { slog "GAGAL verifikasi $label: hanya $n entri (terlalu sedikit)"; return 1; }
    # entri kunci WAJIB ada (bukti kita mem-pack direktori yang benar)
    local key missing=0
    for key in .zscripts/dev.sh worklog.md memory/SESSION-STATE.md; do
        if ! tar -tf "$t" 2>/dev/null | grep -qx "$key"; then
            slog "GAGAL verifikasi $label: entri kunci '$key' tidak ada"; missing=1
        fi
    done
    [ "$missing" -eq 0 ] || return 1
    slog "verifikasi $label OK: $n entri, entri kunci lengkap ($(du -h "$t" | cut -f1))"
    VERIFIED_ENTRIES="$n"
    return 0
}

newest_orig() { ls -1t "$WMG_ORIG_DIR"/repo.tar.orig-* 2>/dev/null | head -1; }

# fingerprint tar milik kita yang terakhir di-swap (mtime|size) — agar kita
# tidak mem-backup build sendiri dan tidak menimpa backup original sejati
ours_marker() { cat "$WMG_STATE_DIR/repo-snapshot.last" 2>/dev/null; }
tar_fingerprint() { stat -c '%Y|%s' "$TAR_PATH" 2>/dev/null; }

do_status() {
    echo "=== REPO SNAPSHOT (refresh manual repo.tar) ==="
    echo "project  : $WMG_PROJECT"
    echo "sync     : $WMG_SYNC"
    echo "orig dir : $WMG_ORIG_DIR · state dir: $WMG_STATE_DIR"
    if [ -f "$TAR_PATH" ]; then
        local tm age
        tm="$(stat -c %Y "$TAR_PATH" 2>/dev/null)"
        age=$(( $(date +%s) - tm ))
        echo "repo.tar : $(stat -c '%s bytes · %y' "$TAR_PATH" 2>/dev/null) (usia $((age/3600))j $(((age%3600)/60))m)"
        if [ "$age" -gt 3600 ]; then
            echo "verdict  : *** BASI — bila container berhenti tanpa pre-stop, boot berikutnya rollback ke kondisi itu. Jalankan --apply untuk menyegarkan. ***"
        else
            echo "verdict  : SEGAR (usia < 1 jam)"
        fi
    else
        echo "repo.tar : tidak ditemukan (boot berikutnya = cabang clean-project!)"
    fi
    local o
    o="$(newest_orig)"
    echo "orig bkp : ${o:-belum ada}$([ -n "$o" ] && echo " ($(du -h "$o" | cut -f1))")"
    local al ac
    al="$(cat "$WMG_STATE_DIR/repo-snap.auto.last" 2>/dev/null)"
    ac="$(cat "$WMG_STATE_DIR/repo-snap.auto.count" 2>/dev/null)"
    [ -n "$al" ] && echo "auto     : #${ac:-0} terakhir $(date -d @"$al" '+%F %T' 2>/dev/null) (cooldown ${COOLDOWN_AUTO}s)"
    echo "skills/  : $([ -d "$WMG_PROJECT/skills/stellar-trail" ] && echo 'stellar-trail ikut di-tar (append)' || echo 'stellar-trail TIDAK ada (append dilewati)')"
    return 0
}

do_apply() {  # $1 = dry|full
    local mode="$1"
    # Prasyarat: sync dir writable
    if ! mkdir -p "$WMG_ORIG_DIR" "$WMG_STATE_DIR" 2>/dev/null; then
        slog "GAGAL: $WMG_SYNC tidak writable — tidak bisa refresh repo.tar"; return 1; fi
    [ -d "$WMG_PROJECT" ] || { slog "GAGAL: $WMG_PROJECT tidak ada"; return 1; }

    local build="$WMG_TMP/repo-snap-build-$$.tar"
    trap 'rm -f "$build"' EXIT

    # 1. BUILD lokal
    if ! build_tar "$build"; then rm -f "$build"; return 1; fi
    # 2. VERIFIKASI sebelum menyentuh apa pun
    if ! verify_tar "$build" "build"; then rm -f "$build"; return 1; fi

    if [ "$mode" = dry ]; then
        echo "[repo-snap] DRY-RUN OK — $VERIFIED_ENTRIES entri, $(du -h "$build" | cut -f1); repo.tar TIDAK disentuh"
        rm -f "$build"; return 0
    fi

    # 3. BACKUP repo.tar asing (SEBELUM swap) — tar milik platform / belum dikenal.
    #    Tar yang fingerprint-nya cocok dgn marker kita = build sendiri -> skip.
    if [ -f "$TAR_PATH" ]; then
        local fp marker
        fp="$(tar_fingerprint)"; marker="$(ours_marker)"
        if [ -n "$marker" ] && [ "$fp" = "$marker" ]; then
            slog "repo.tar saat ini = build kita sebelumnya — skip backup"
        else
            # nama ms-resolution + anti-timpa (pelajaran bug kolisi detik)
            local bk="$WMG_ORIG_DIR/repo.tar.orig-$(date +%Y%m%d-%H%M%S-%3N)" n=0
            while [ -e "$bk" ] && [ $n -lt 50 ]; do
                bk="$WMG_ORIG_DIR/repo.tar.orig-$(date +%Y%m%d-%H%M%S)-$n"; n=$((n+1)); done
            if cp "$TAR_PATH" "$bk" 2>>"$LOG"; then
                slog "backup repo.tar asli (asing) -> $(basename "$bk")"
                ls -1t "$WMG_ORIG_DIR"/repo.tar.orig-* 2>/dev/null | tail -n +$((KEEP_ORIG + 1)) \
                  | while read -r old; do rm -f "$old" && slog "retensi: hapus $(basename "$old")"; done
            else
                slog "GAGAL backup asli — BATALKAN swap demi keamanan"; rm -f "$build"; return 1
            fi
        fi
    fi

    # 4. STAGE ke satu mount lalu rename-overwrite (atomik sebisanya ossfs)
    local staged="$WMG_SYNC/.repo.tar.staged"
    if ! cp "$build" "$staged" 2>>"$LOG"; then
        slog "GAGAL stage ke $staged"; rm -f "$build" "$staged"; return 1; fi
    if ! verify_tar "$staged" "staged"; then rm -f "$build" "$staged"; return 1; fi
    if ! mv -f "$staged" "$TAR_PATH" 2>>"$LOG"; then
        slog "GAGAL rename-overwrite repo.tar"; rm -f "$build" "$staged"; return 1; fi

    # 5. VERIFIKASI AKHIR
    if ! verify_tar "$TAR_PATH" "final"; then
        slog "*** FINAL GAGAL — pulihkan dgn: repo-snapshot.sh --restore-original ***"
        rm -f "$build"; return 1
    fi
    rm -f "$build"
    mkdir -p "$WMG_STATE_DIR" 2>/dev/null
    tar_fingerprint > "$WMG_STATE_DIR/repo-snapshot.last" 2>/dev/null
    slog "REPO.TAR DISEGARKAN: $VERIFIED_ENTRIES entri ($(du -h "$TAR_PATH" | cut -f1)) — restore boot berikutnya = kondisi terkini"
    echo "[repo-snap] repo.tar berhasil direfresh ($VERIFIED_ENTRIES entri)."
    return 0
}

do_apply_auto() {
    # refresh berkala dengan gerbang ganda — dipanggil boot hook (step 5)
    # dan watcher. Tujuan: selama container hidup, repo.tar tidak pernah
    # lebih tua dari ~15 menit dari kondisi project.
    local now last
    now="$(date +%s)"
    last="$(cat "$WMG_STATE_DIR/repo-snap.auto.last" 2>/dev/null)"
    if [ -n "$last" ] && [ $((now - last)) -lt "$COOLDOWN_AUTO" ]; then
        slog_q "auto: cooldown ($((now - last))s < ${COOLDOWN_AUTO}s) — lewati"
        return 0
    fi
    # debounce: hanya bila ada perubahan material sejak apply terakhir
    # (heal-skill.sh sengaja MENGHAPUS marker ini saat heal agar hasilnya
    #  langsung dibawa refresh berikutnya — rsync -a mempertahankan mtime
    #  lama sehingga find -newer tidak melihatnya)
    local mark="$WMG_STATE_DIR/.repo-auto-trigger"
    if [ -f "$mark" ]; then
        local changed
        changed="$(find "$WMG_PROJECT" \
            \( -path "$WMG_PROJECT/skills" -o -path "$WMG_PROJECT/node_modules" \
               -o -path "$WMG_PROJECT/.venv" -o -path "$WMG_PROJECT/.next" \
               -o -path "$WMG_PROJECT/upload" -o -path "$WMG_PROJECT/db" \
               -o -path "$WMG_PROJECT/.git" -o -path "$WMG_PROJECT/archive" \
               -o -name "*.log" -o -name "*.pid" \) -prune \
            -o -type f -newer "$mark" -print 2>/dev/null | head -1)"
        # pengecualian sadar: skills/stellar-trail adalah material (hasil heal)
        if [ -z "$changed" ] && [ -d "$WMG_PROJECT/skills/stellar-trail" ]; then
            changed="$(find "$WMG_PROJECT/skills/stellar-trail" -type f -newer "$mark" 2>/dev/null | head -1)"
        fi
        if [ -z "$changed" ]; then
            slog_q "auto: tidak ada perubahan material — lewati"
            return 0
        fi
    fi
    if do_apply full; then
        mkdir -p "$WMG_STATE_DIR" 2>/dev/null
        date +%s > "$WMG_STATE_DIR/repo-snap.auto.last" 2>/dev/null
        touch "$WMG_STATE_DIR/.repo-auto-trigger" 2>/dev/null
        local n; n=$(( $(cat "$WMG_STATE_DIR/repo-snap.auto.count" 2>/dev/null || echo 0) + 1 ))
        echo "$n" > "$WMG_STATE_DIR/repo-snap.auto.count" 2>/dev/null
        slog "auto-apply #$n sukses"
        return 0
    fi
    slog_q "auto: apply gagal — cooldown dipasang agar tidak spam retry"
    date +%s > "$WMG_STATE_DIR/repo-snap.auto.last" 2>/dev/null
    return 1
}

do_restore_original() {
    # UNDO eksplisit: kembalikan repo.tar asli terakhir — DIVERIFIKASI dulu.
    # Undo tetap byte-identical (tidak ada rebuild/penyaringan); verifikasi hanya
    # MEMBACA arsip: struktur valid + audit member (anti traversal). Arsip korup
    # atau hostile DITOLAK — memasangnya justru merusak boot berikutnya, persis
    # kegagalan yang skrip ini cegah. Backup asli tidak pernah dihapus saat tolak.
    # Verifikasi sengaja TIDAK memakai ambang entri/entri-kunci verify_tar penuh —
    # original platform sah mungkin tidak memuat entri kunci kita.
    local o; o="$(newest_orig)"
    [ -n "$o" ] || { slog "tidak ada backup repo.tar asli untuk dipulihkan"; return 1; }
    [ -s "$o" ] || { slog "backup asli kosong — tolak"; return 1; }
    if ! tar -tf "$o" >/dev/null 2>&1; then
        slog "GAGAL restore: backup asli korup (struktur tar invalid) — swap DIBATALKAN; backup utuh di $(basename "$o")"; return 1
    fi
    if ! audit_members "$o" "restore-original"; then
        slog "GAGAL restore: backup asli memuat member tidak aman — swap DIBATALKAN; backup utuh di $(basename "$o")"; return 1
    fi
    local staged="$WMG_SYNC/.repo.tar.staged"
    cp "$o" "$staged" 2>>"$LOG" || { slog "GAGAL stage restore"; return 1; }
    mv -f "$staged" "$TAR_PATH" 2>>"$LOG" || { rm -f "$staged"; return 1; }
    rm -f "$WMG_STATE_DIR/repo-snapshot.last"   # tar kini bukan milik kita
    slog "repo.tar dikembalikan ke asli: $(basename "$o")"
    echo "[repo-snap] repo.tar dikembalikan ke snapshot asli terakhir."
    return 0
}

case "${1:---status}" in
    --status)           do_status ;;
    --dry-run)          do_apply dry ;;
    --apply)            do_apply full ;;
    --apply-auto)       do_apply_auto ;;
    --restore-original) do_restore_original ;;
    *)
        echo "pakai: repo-snapshot.sh --status | --dry-run | --apply | --apply-auto | --restore-original"
        exit 2 ;;
esac
exit $?
