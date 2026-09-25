#!/usr/bin/env bash
# ============================================================================
# audit-compliance.sh — AUDIT KEPATUHAN PROTOCOL stellar-trail DARI LUAR MODEL
# (R3, v3.5.5 — lahir dari laporan insiden 2026-09-21: 3 session non-compliance
#  senyap, hanya terdeteksi audit manual user)
# v3.6.2 (Task 60, 2026-09-25 — laporan konsumer fresh-install): C1/C5 kini
#  membawa HINT BOOTSTRAP satu baris — di instalasi CLI-only tanpa persistence
#  layer, C1 FAIL (memory/ absen) + C5 WARN (hook R1 belum di-append) adalah
#  state EXPECTED pasca-install, bukan pelanggaran; hint mengarahkan ke
#  scripts/bootstrap-sandbox.sh (memory consent-gated — SKILL.md §4b) agar
#  konsumer fresh-install tidak mengira auditnya rusak.
#
# FILOSOFI: pelanggaran senyap karena TIDAK ADA sinyal alarm — respons tanpa
#   marker tidak menimbulkan error apa pun. Skrip ini memberi user satu
#   perintah murah untuk memeriksa signature kepatuhan dari artefak di disk,
#   TANPA bergantung pada disiplin model. Read-only; tidak pernah memperbaiki
#   (perbaikan = heal-skill.sh / M1 checkpoint oleh agent).
#
# CHECKS:
#   C1 memory/SESSION-STATE.md ada (fondasi protokol memory)
#   C2 Active-table hygiene (SKILL.md §4d H2): baris DONE/CANCELLED/TERTUTUP
#      di bawah "## Active Tasks" = FAIL (task selesai tampil sbg pending)
#   C3 staleness: worklog aktif bertumbuh TAPI SESSION-STATE tidak di-rewrite
#      >30 mnt = WARN (signature tidak ada checkpoint M1 — pola insiden)
#   C4 version sanity (§4c): assets/integrity.version tiap instalasi vs
#      .clawhub/lock.json vs kanonik download/stellar-trail — drift = WARN
#   C5 worklog activation hook (R1): baris ACTIVATE di tail worklog = ada?
#
# VERDICT: FAIL > 0 → exit 1 · hanya PASS/WARN → exit 0
#   (WARN = temuan yang BISA absah sekejap — tetap dilaporkan, tidak menggagalkan)
#
# USAGE:
#   bash scripts/audit-compliance.sh [--root <project-root>] [--quiet]
#   --root  default: 3 level di atas lokasi skrip ini (layout instalasi skill)
#           → sesuaikan bila project root berbeda
# ============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd)"
QUIET=0

while [ $# -gt 0 ]; do
    case "$1" in
        --root)  ROOT="$(cd "$2" 2>/dev/null && pwd)" || { echo "ERROR: --root $2 tidak valid"; exit 2; }; shift 2 ;;
        --quiet) QUIET=1; shift ;;
        *) echo "pakai: bash scripts/audit-compliance.sh [--root <dir>] [--quiet]"; exit 2 ;;
    esac
done

PASS=0; WARN=0; FAIL=0
say() { [ "$QUIET" -eq 0 ] && echo "$*"; return 0; }
res() { # res <PASS|WARN|FAIL> <kode-check> <detail>
    case "$1" in
        PASS) PASS=$((PASS+1)); say "  [PASS] $2 — $3" ;;
        WARN) WARN=$((WARN+1)); say "  [WARN] $2 — $3" ;;
        *)    FAIL=$((FAIL+1)); say "  [FAIL] $2 — $3" ;;
    esac
}

say "[audit-compliance] root: $ROOT"

# --- C1: memory/SESSION-STATE.md ------------------------------------------------
SS="$ROOT/memory/SESSION-STATE.md"
WL="$ROOT/worklog.md"
if [ -f "$SS" ]; then res PASS "C1 memory" "SESSION-STATE.md ada ($(wc -l < "$SS") baris)"
else res FAIL "C1 memory" "memory/SESSION-STATE.md TIDAK ADA — protokol memory tanpa fondasi — fresh install? bash scripts/bootstrap-sandbox.sh (memory consent-gated — SKILL.md §4b)"; fi

# --- C2: Active-table hygiene (H2) ----------------------------------------------
if [ -f "$SS" ]; then
    # ekstrak seksi Active Tasks lalu cari status terminal di kolom status
    ACTIVE_ROWS="$(awk '/^## Active Tasks/{f=1;next} /^## /{f=0} f && /^\|/' "$SS" | grep -vE '^\|[[:space:]]*-|^\|[[:space:]]*Task ID' || true)"
    if [ -z "$ACTIVE_ROWS" ]; then
        res PASS "C2 hygiene" "tabel aktif kosong (tidak ada task aktif) — bersih"
    elif echo "$ACTIVE_ROWS" | grep -qiE '\| *(DONE|CANCELLED|TERTUTUP|SEALED) *\|'; then
        res FAIL "C2 hygiene" "baris terminal (DONE/CANCELLED/...) di Active table — pelanggaran H2, risiko stale-pickup"
    else
        res PASS "C2 hygiene" "Active table hanya berisi baris ACTIVE/BLOCKED/STALE ($(echo "$ACTIVE_ROWS" | wc -l) baris)"
    fi
fi

# --- C3: staleness SESSION-STATE vs worklog --------------------------------------
if [ -f "$SS" ] && [ -f "$WL" ]; then
    SS_M=$(stat -c%Y "$SS" 2>/dev/null || echo 0)
    WL_M=$(stat -c%Y "$WL" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    if [ "$WL_M" -gt "$SS_M" ] && [ $((NOW - WL_M)) -lt 900 ] && [ $((WL_M - SS_M)) -gt 1800 ]; then
        res WARN "C3 staleness" "worklog aktif ($(date -d "@$WL_M" '+%H:%M' 2>/dev/null)) tapi SESSION-STATE terakhir $(date -d "@$SS_M" '+%H:%M' 2>/dev/null) — gap $(( (WL_M - SS_M) / 60 )) mnt: signature TIDAK ada checkpoint M1"
    else
        res PASS "C3 staleness" "checkpoint segar (gap aman / tidak ada kerja aktif yang yatim checkpoint)"
    fi
fi

# --- C4: version sanity (4c) ------------------------------------------------------
LOCK="$ROOT/.clawhub/lock.json"
CANON_VER="$(cat "$ROOT/download/stellar-trail/assets/integrity.version" 2>/dev/null || echo '')"
[ -n "$CANON_VER" ] || CANON_VER="(kanonik tak ada)"
for CAND in "$ROOT/skills/stellar-trail" "$ROOT"/skills/@*/stellar-trail; do
    [ -d "$CAND" ] || continue
    IV="$(cat "$CAND/assets/integrity.version" 2>/dev/null || echo '?')"
    KEY="$(basename "$(dirname "$CAND")")/$(basename "$CAND")"; [ "$KEY" = "skills/stellar-trail" ] && KEY="stellar-trail"
    LV="$(python3 -c "import json,sys
try:
    d=json.load(open('$LOCK'))
    v=d.get('skills',{}).get('$KEY',{}).get('version','?')
    if v=='?':
        k=[x for x in d.get('skills',{}) if x.endswith('stellar-trail')]
        v=d.get('skills',{}).get(k[0],{}).get('version','?') if k else '?'
    print(v)
except Exception: print('?')" 2>/dev/null || echo '?')"
    if [ "$IV" = "?" ]; then res WARN "C4 versi $KEY" "integrity.version tak terbaca di $CAND"
    elif [ "$IV" != "$LV" ]; then res WARN "C4 versi $KEY" "instal $IV ≠ lock $LV — jalankan heal-skill.sh --check"
    else res PASS "C4 versi $KEY" "instal $IV = lock $LV"
    fi
done

# --- C5: worklog activation hook (R1) ---------------------------------------------
if [ -f "$WL" ]; then
    if tail -50 "$WL" | grep -q '⚡ACTIVATE'; then
        res PASS "C5 hook-R1" "pemicu aktivasi ada di tail worklog"
    else
        res WARN "C5 hook-R1" "baris ⚡ACTIVATE tidak di 50 baris terakhir worklog — hook R1 belum di-append (v3.5.5+) — fresh install? bash scripts/bootstrap-sandbox.sh"
    fi
fi

# --- verdict ------------------------------------------------------------------------
say "[audit-compliance] VERDICT: PASS=$PASS WARN=$WARN FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
    say "[audit-compliance] GAGAL — temuan FAIL di atas wajib ditindak (seal task via M1 / heal / re-audit)"
    exit 1
fi
say "[audit-compliance] LOLOS — ${WARN:+$WARN temuan WARN dilaporkan di atas}"
exit 0
