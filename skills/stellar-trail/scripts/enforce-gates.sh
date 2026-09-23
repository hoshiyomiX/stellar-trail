#!/usr/bin/env bash
# ============================================================
# enforce-gates.sh — TERMINAL-TRACK ENFORCEMENT
# stellar-trail v3.3.1 · SKILL.md section 8b · formerly workflow-memory-guardian
#
# Terminal checks are proven by EXECUTION, never by prediction.
# Exit codes: 0 = all pass · 1 = at least one FAIL · 2 = usage error
#
# Usage:
#   bash enforce-gates.sh --task <doc|chart|web|code|mixed|conversational> \
#        [--artifact <path>] [--lint <file> …] \
#        [--check-skill <dir>] [--check-worklog <file> --task-id <id>] \
#        [--selftest]
# ============================================================
set -u
PASS=0; FAIL=0; WARN=0
R="\033[0;31m"; G="\033[0;32m"; Y="\033[1;33m"; B="\033[0;34m"; N="\033[0m"
ok(){  PASS=$((PASS+1)); printf "  ${G}[PASS]${N} %s\n" "$1"; }
bad(){ FAIL=$((FAIL+1)); printf "  ${R}[FAIL]${N} %s\n" "$1"; }
warn(){ WARN=$((WARN+1)); printf "  ${Y}[WARN]${N} %s\n" "$1"; }
note(){ printf "  ${B}[NOTE]${N} %s\n" "$1"; }

TASK=""; ARTIFACT=""; LINT_FILES=""; SKILL_DIR=""; WORKLOG=""; TASKID=""; SELFTEST=0
while [ $# -gt 0 ]; do case "$1" in
  --task) TASK="${2:-}"; shift 2;;
  --artifact) ARTIFACT="${2:-}"; shift 2;;
  --lint) shift; while [ $# -gt 0 ] && [ "${1:0:2}" != "--" ]; do LINT_FILES="$LINT_FILES $1"; shift; done;;
  --check-skill) SKILL_DIR="${2:-}"; shift 2;;
  --check-worklog) WORKLOG="${2:-}"; shift 2;;
  --task-id) TASKID="${2:-}"; shift 2;;
  --selftest) SELFTEST=1; shift;;
  -h|--help) sed -n '2,15p' "$0"; exit 0;;
  *) printf "Unknown arg: %s\n" "$1" >&2; exit 2;;
esac; done

# ---- sanity floor per task type (bytes) — below = FAIL if 0, WARN if tiny
min_size(){ case "$1" in
  doc) echo 8000;; chart) echo 3000;; web) echo 1500;; code|mixed) echo 50;; *) echo 0;;
esac; }

# ================= L1: artifact verification =================
if [ -n "$ARTIFACT" ]; then
  echo "== L1 artifact: $ARTIFACT (task=$TASK) =="
  if [ ! -e "$ARTIFACT" ]; then bad "artifact tidak ditemukan: $ARTIFACT"
  elif [ -d "$ARTIFACT" ]; then
    n=$(find "$ARTIFACT" -type f | wc -l)
    [ "$n" -gt 0 ] && ok "direktori artefak berisi $n file" || bad "direktori artefak kosong"
  elif [ ! -r "$ARTIFACT" ]; then bad "artifact tidak terbaca (permission): $ARTIFACT"
  elif [ ! -s "$ARTIFACT" ]; then bad "artifact kosong (0 byte): $ARTIFACT"
  else
    sz=$(stat -c%s "$ARTIFACT" 2>/dev/null || stat -f%z "$ARTIFACT" 2>/dev/null)
    floor=$(min_size "$TASK"); human=$(awk -v s="$sz" 'BEGIN{printf "%.1f KB", s/1024}')
    ok "artifact ada & terbaca ($human)"
    if [ "$floor" -gt 0 ] && [ "$sz" -lt "$floor" ]; then
      warn "ukuran di bawah heuristik $TASK (${floor} B) — verifikasi isi memang sesuai?"
    fi
  fi
fi

# ================= L3: lint by extension =================
if [ -n "${LINT_FILES// /}" ]; then
  echo "== L3 lint =="
  for f in $LINT_FILES; do
    [ -e "$f" ] || { bad "lint: file tidak ada: $f"; continue; }
    ext="${f##*.}"; case "$ext" in
      sh|bash)
        if bash -n "$f" 2>/tmp/eg_err; then ok "bash -n: $f"; else bad "bash -n: $f — $(head -1 /tmp/eg_err)"; fi;;
      py)
        if python3 -c "import ast,sys; ast.parse(open(sys.argv[1],encoding='utf-8').read())" "$f" 2>/tmp/eg_err; then ok "py ast: $f"; else bad "py ast: $f — $(tail -1 /tmp/eg_err)"; fi;;
      js|mjs|cjs)
        if command -v node >/dev/null 2>&1; then
          if node --check "$f" 2>/tmp/eg_err; then ok "node --check: $f"; else bad "node --check: $f — $(head -1 /tmp/eg_err)"; fi
        else note "node tidak tersedia — SKIP: $f (nyatakan fallback di marker)"; fi;;
      json)
        if python3 -m json.tool "$f" >/dev/null 2>/tmp/eg_err; then ok "json parse: $f"; else bad "json parse: $f — $(tail -1 /tmp/eg_err)"; fi;;
      html|htm)
        if python3 - "$f" <<'PYEOF' 2>/tmp/eg_err
import sys, html.parser
class P(html.parser.HTMLParser):
    def error(self, m): raise SystemExit("parse error: "+m)
p=P(); p.feed(open(sys.argv[1],encoding="utf-8",errors="replace").read())
raise SystemExit(0)
PYEOF
        then ok "html parse: $f"; else bad "html parse: $f — $(tail -1 /tmp/eg_err)"; fi;;
      md)
        fences=$(grep -c '^```' "$f" 2>/dev/null); fences=${fences:-0}
        if [ $((fences % 2)) -eq 0 ]; then ok "md code-fence seimbang ($fences): $f"; else bad "md code-fence GANJIL ($fences): $f"; fi;;
      *) note "tanpa linter untuk .$ext — periksa manual: $f";;
    esac
  done
fi

# ================= skill package integrity =================
if [ -n "$SKILL_DIR" ]; then
  echo "== check-skill: $SKILL_DIR =="
  S="$SKILL_DIR/SKILL.md"
  [ -f "$S" ] || { bad "SKILL.md tidak ada di $SKILL_DIR"; S=""; }
  if [ -n "$S" ]; then
    head -1 "$S" | grep -q '^---' && ok "frontmatter pembuka ---" || bad "frontmatter pembuka --- hilang"
    grep -q '^name:' "$S" && ok "field name: ada" || bad "field name: hilang"
    if grep -q '^description:' "$S"; then
      ok "field description: ada"
      # ekstrak blok deskripsi (yaml folded > dibuka ke satu baris)
      desc=$(python3 - "$S" <<'PYEOF'
import sys,re
t=open(sys.argv[1],encoding="utf-8").read()
m=re.match(r"^---\n(.*?)\n---\n",t,re.S)
if not m: print(""); raise SystemExit
fm=m.group(1)
dm=re.search(r"^description:\s*>-\s*\n((?:\s{2,}.*\n)+)",fm,re.M)
if not dm:
    dm=re.search(r"^description:\s*>?\s*\n?((?:\s{2,}.*\n)+)",fm,re.M)
d=dm.group(1) if dm else ""
print(re.sub(r"\s+"," ",d).strip() if d else "")
PYEOF
)
      dlen=${#desc}
      if [ "$dlen" -gt 0 ] && [ "$dlen" -le 1024 ]; then ok "panjang description $dlen/1024"; else bad "panjang description $dlen — di luar 1..1024"; fi
      case "$desc" in *"<"*|*">"*) bad "description mengandung angle bracket < >";; *) ok "description tanpa angle bracket";; esac
    else bad "field description: hilang"; fi
    # referensi & skrip yang disebut harus ada
    miss=0
    for ref in $(grep -o 'references/[A-Za-z0-9_-]*\.md' "$S" | sort -u); do
      [ -f "$SKILL_DIR/$ref" ] || { bad "referensi hilang: $ref"; miss=1; }; done
    [ "$miss" -eq 0 ] && ok "semua references/*.md yang dirujuk ada"
    miss=0
    for scr in $(grep -o 'scripts/[A-Za-z0-9_-]*\.sh' "$S" | sort -u); do
      [ -f "$SKILL_DIR/$scr" ] || { bad "script hilang: $scr"; miss=1; }; done
    [ "$miss" -eq 0 ] && ok "semua scripts/*.sh yang dirujuk ada"
  fi
fi

# ================= worklog section =================
if [ -n "$WORKLOG" ]; then
  echo "== check-worklog: $WORKLOG (Task ID: ${TASKID:-?}) =="
  if [ -z "$TASKID" ]; then bad "--task-id wajib bersama --check-worklog";
  elif [ ! -f "$WORKLOG" ]; then bad "worklog tidak ada: $WORKLOG";
  elif grep -q "Task ID: $TASKID" "$WORKLOG"; then ok "section 'Task ID: $TASKID' ditemukan";
  else bad "worklog belum punya section Task ID: $TASKID"; fi
fi

# ================= selftest: prove the gate CAN fail =================
if [ "$SELFTEST" -eq 1 ]; then
  echo "== selftest (gate harus bisa GAGAL) =="
  T=$(mktemp -d)
  echo "ok" > "$T/good.sh"; printf 'if [ broken\n' > "$T/bad.sh"
  echo '{"a":1}' > "$T/good.json"; echo '{a:1}' > "$T/bad.json"
  printf '```fence\n' > "$T/bad.md"; printf '```\n```\n' > "$T/good.md"
  bash -n "$T/good.sh" 2>/dev/null && ok "selftest: skrip valid diterima" || bad "selftest: skrip valid DITOLAK (gate terlalu ketat)"
  bash -n "$T/bad.sh" 2>/dev/null && bad "selftest: skrip rusak LOLOS (gate bocor)" || ok "selftest: skrip rusak ditolak benar"
  python3 -m json.tool "$T/bad.json" >/dev/null 2>&1 && bad "selftest: json rusak LOLOS" || ok "selftest: json rusak ditolak benar"
  [ $(( $(grep -c '^```' "$T/bad.md") % 2 )) -eq 0 ] && bad "selftest: fence ganjil LOLOS" || ok "selftest: fence ganjil ditolak benar"
  [ -f "$T/tidak-ada.png" ] && bad "selftest: file hilang LOLOS" || ok "selftest: file hilang ditolak benar"
  rm -rf "$T"
fi

# ================= summary =================
TOTAL=$((PASS+FAIL))
echo "----------------------------------------"
if [ "$TOTAL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
  echo "ENFORCE-GATES: tidak ada check diminta — lihat --help"; exit 2
fi
printf "ENFORCE-GATES: ${G}%d PASS${N} · ${R}%d FAIL${N} · ${Y}%d WARN${N}\n" "$PASS" "$FAIL" "$WARN"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
