#!/usr/bin/env bash
# Test-ExecJob.sh -- unit-tests exec-job.sh's staging/publish/wait/status mechanics against a MOCK runtime
# (no executor daemon). Off-machine safe. Exits 0 iff every assertion passes.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXEC="$SCRIPT_DIR/../exec-job.sh"
pass=0; fail=0
ok(){ if [ "$1" = "1" ]; then pass=$((pass+1)); echo "  PASS  $2"; else fail=$((fail+1)); echo "  FAIL  $2"; fi; }

WORK="$(mktemp -d)"
export EXEC_RT="$WORK/runtime"
mkdir -p "$EXEC_RT"
echo "==== exec-job.sh mock-runtime tests ===="
echo "exec=$EXEC"; echo "rt=$EXEC_RT"; echo ""

# dummy task.ps1 to submit
DUMMY="$WORK/dummy.ps1"; printf "Write-Output hi\n" > "$DUMMY"

# --- submit ---
bash "$EXEC" submit t1 60 "$DUMMY" "a description" >/dev/null 2>&1
sub_rc=$?
echo "S1 submit:"
ok "$([ $sub_rc -eq 0 ] && echo 1 || echo 0)" "S1 submit exit 0"
ok "$([ -f "$EXEC_RT/pending/t1/task.ps1" ] && echo 1 || echo 0)" "S1 pending/t1/task.ps1 exists"
ok "$([ -f "$EXEC_RT/pending/t1/task.json" ] && echo 1 || echo 0)" "S1 pending/t1/task.json exists"
ok "$(grep -q '"task_id":"t1"' "$EXEC_RT/pending/t1/task.json" && echo 1 || echo 0)" "S1 task.json has task_id=t1"
ok "$(grep -q '"script_file":"task.ps1"' "$EXEC_RT/pending/t1/task.json" && echo 1 || echo 0)" "S1 task.json script_file=task.ps1"
ok "$(grep -q '"timeout_seconds":60' "$EXEC_RT/pending/t1/task.json" && echo 1 || echo 0)" "S1 task.json timeout_seconds=60"
ok "$([ ! -d "$EXEC_RT/staging/t1.tmp" ] && echo 1 || echo 0)" "S1 staging dir consumed (atomic publish)"
if command -v python3 >/dev/null 2>&1; then
  python3 -c "import json,sys; json.load(open('$EXEC_RT/pending/t1/task.json'))" >/dev/null 2>&1
  ok "$([ $? -eq 0 ] && echo 1 || echo 0)" "S1 task.json is valid JSON"
fi

# --- collision refused ---
bash "$EXEC" submit t1 60 "$DUMMY" "dup" >/dev/null 2>&1
ok "$([ $? -ne 0 ] && echo 1 || echo 0)" "S2 duplicate id refused (nonzero exit)"

# --- bad id refused ---
bash "$EXEC" submit "bad id" 60 "$DUMMY" >/dev/null 2>&1
ok "$([ $? -ne 0 ] && echo 1 || echo 0)" "S3 invalid id (space) refused"
bash "$EXEC" submit ".." 60 "$DUMMY" >/dev/null 2>&1
ok "$([ $? -ne 0 ] && echo 1 || echo 0)" "S3 dotdot id refused"

# --- status while pending ---
st=$(bash "$EXEC" status t1 2>/dev/null)
ok "$([ "$st" = "pending" ] && echo 1 || echo 0)" "S4 status=pending"

# --- simulate completion, then wait ---
mkdir -p "$EXEC_RT/completed"
mv "$EXEC_RT/pending/t1" "$EXEC_RT/completed/t1"
printf '{"task_id":"t1","status":"completed","exit_code":0,"duration_ms":1234}\n' > "$EXEC_RT/completed/t1/result.json"
printf 'DEVSHIP_JSON_HERE line1\nline2\n' > "$EXEC_RT/completed/t1/stdout.txt"
printf '' > "$EXEC_RT/completed/t1/stderr.txt"
out=$(bash "$EXEC" wait t1 5 2>/dev/null); wrc=$?
echo "S5 wait completed:"
ok "$([ $wrc -eq 0 ] && echo 1 || echo 0)" "S5 wait exit 0 on completed"
ok "$(printf '%s' "$out" | grep -q 'STATE=completed' && echo 1 || echo 0)" "S5 prints STATE=completed"
ok "$(printf '%s' "$out" | grep -q 'status=completed' && echo 1 || echo 0)" "S5 parses status from result.json"
ok "$(printf '%s' "$out" | grep -q 'DEVSHIP_JSON_HERE' && echo 1 || echo 0)" "S5 prints stdout.txt content"
ok "$([ "$(bash "$EXEC" status t1 2>/dev/null)" = "completed" ] && echo 1 || echo 0)" "S5 status=completed"

# --- wait on a failed task returns nonzero but still prints ---
mkdir -p "$EXEC_RT/failed/f1"
printf '{"task_id":"f1","status":"failed","exit_code":1,"duration_ms":5}\n' > "$EXEC_RT/failed/f1/result.json"
printf 'boom\n' > "$EXEC_RT/failed/f1/stdout.txt"
out=$(bash "$EXEC" wait f1 5 2>/dev/null); wrc=$?
echo "S6 wait failed:"
ok "$([ $wrc -eq 1 ] && echo 1 || echo 0)" "S6 wait exit 1 on failed"
ok "$(printf '%s' "$out" | grep -q 'STATE=failed' && echo 1 || echo 0)" "S6 prints STATE=failed"

# --- devship staging shape (maxw=0 -> no sleep, returns before completion) ---
INP="$WORK/inputs.json"; printf '{"files":[],"commit":false}\n' > "$INP"
bash "$EXEC" devship ds1 "$INP" 120 0 >/dev/null 2>&1
echo "S7 devship staging:"
ok "$([ -f "$EXEC_RT/pending/ds1/task.ps1" ] && echo 1 || echo 0)" "S7 pending/ds1/task.ps1 exists"
ok "$([ -f "$EXEC_RT/pending/ds1/devship-input.json" ] && echo 1 || echo 0)" "S7 devship-input.json placed alongside"
ok "$(grep -q 'Invoke-DevShip.ps1' "$EXEC_RT/pending/ds1/task.ps1" && echo 1 || echo 0)" "S7 wrapper invokes Invoke-DevShip.ps1"
ok "$(grep -q 'devship-input.json' "$EXEC_RT/pending/ds1/task.ps1" && echo 1 || echo 0)" "S7 wrapper reads devship-input.json"
ok "$(grep -q '"timeout_seconds":120' "$EXEC_RT/pending/ds1/task.json" && echo 1 || echo 0)" "S7 devship task.json timeout=120"

rm -rf "$WORK"
echo ""
echo "==== RESULT pass=$pass fail=$fail ===="
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "FAILURES"; exit 1; fi
