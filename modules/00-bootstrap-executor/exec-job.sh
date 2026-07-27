#!/usr/bin/env bash
# exec-job.sh -- driver-side client for the Trusted High-Risk Bootstrap Executor (Module 0 job-runner, D-0047/D-0048).
#
# Run from the device's Linux mount (device_bash). It encapsulates the staging->pending submit dance and a
# bounded wait, returning a COMPACT result -- so the frontier driver stops re-authoring mkdir/heredoc/mv and
# stops reading raw dumps. It mirrors Submit-BootstrapTask.ps1's on-disk contract exactly (task_id pattern,
# staging/<id>.tmp -> atomic mv -> pending/<id>, task.json fields).
#
# Usage:
#   exec-job.sh submit  <id> <timeout_seconds> <task_ps1_path> [description]
#   exec-job.sh wait    <id> [max_wait_seconds=40]
#   exec-job.sh run     <id> <timeout_seconds> <task_ps1_path> [max_wait_seconds=40] [description]
#   exec-job.sh devship <id> <inputs_json_path> [timeout_seconds=900] [max_wait_seconds=40]
#   exec-job.sh status  <id>
#
# NOTE: device_bash caps a single call at ~45s, so `wait` polls up to max_wait (default 40s) then returns
# STATE=running/pending -- just re-run `wait <id>` to keep polling a long (GPU) job. Short jobs (a gate,
# a commit) finish inside one call.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Runtime root: normally alongside this script; EXEC_RT overrides it (tests / a non-default runtime).
RT="${EXEC_RT:-$SCRIPT_DIR/runtime}"
# Canonical Windows path to the dev.ship orchestrator (baked; the repo is canonically here).
DEVSHIP_WIN='C:\Users\just_\LifeOrchestrator-Refresh\modules\00-bootstrap-executor\Invoke-DevShip.ps1'

die(){ echo "exec-job: $*" >&2; exit 2; }
valid_id(){ [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] && [[ "$1" =~ [A-Za-z0-9] ]] && [[ "$1" != "." ]] && [[ "$1" != ".." ]]; }
exists_anywhere(){ local d; for d in pending running completed failed; do [ -e "$RT/$d/$1" ] && return 0; done; return 1; }
esc(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

_publish(){  # mv a prepared staging/<id>.tmp into pending/<id>
  local id="$1"
  mv "$RT/staging/$id.tmp" "$RT/pending/$id" || die "publish (mv to pending) failed for $id"
}

_write_taskjson(){  # <dest_dir> <id> <timeout> <description>
  printf '{"task_id":"%s","script_file":"task.ps1","visible_window":false,"submitted_by":"claude","description":"%s","timeout_seconds":%s}\n' \
    "$2" "$(esc "$4")" "$3" > "$1/task.json"
}

cmd_submit(){
  local id="$1" timeout="$2" ps1="$3" desc="${4:-task}"
  valid_id "$id" || die "bad task id: $id"
  [[ "$timeout" =~ ^[0-9]+$ ]] || die "timeout must be an integer: $timeout"
  [ -f "$ps1" ] || die "task.ps1 not found: $ps1"
  exists_anywhere "$id" && die "task id already in the pipeline: $id"
  mkdir -p "$RT/staging" "$RT/pending"
  local st="$RT/staging/$id.tmp"
  rm -rf "$st" 2>/dev/null; mkdir -p "$st"
  cp -f "$ps1" "$st/task.ps1"
  _write_taskjson "$st" "$id" "$timeout" "$desc"
  _publish "$id"
  echo "submitted $id (timeout=${timeout}s)"
}

_emit(){  # <id> <where>  -- print compact header + full stdout.txt (+ stderr tail)
  local id="$1" where="$2" dir="$RT/$2/$1"
  local status exit_code duration
  status=$(sed -n 's/.*"status"[ ]*:[ ]*"\([^"]*\)".*/\1/p' "$dir/result.json" 2>/dev/null | head -1)
  exit_code=$(sed -n 's/.*"exit_code"[ ]*:[ ]*\([^,}]*\).*/\1/p' "$dir/result.json" 2>/dev/null | head -1 | tr -d ' ')
  duration=$(sed -n 's/.*"duration_ms"[ ]*:[ ]*\([0-9]*\).*/\1/p' "$dir/result.json" 2>/dev/null | head -1)
  echo "STATE=$where status=${status:-?} exit_code=${exit_code:-?} duration_ms=${duration:-?}"
  echo "----- stdout.txt -----"
  cat "$dir/stdout.txt" 2>/dev/null || echo "(no stdout)"
  local errsz; errsz=$(wc -c < "$dir/stderr.txt" 2>/dev/null || echo 0)
  if [ "${errsz:-0}" -gt 0 ]; then echo "----- stderr.txt (tail 800) -----"; tail -c 800 "$dir/stderr.txt" 2>/dev/null; fi
}

cmd_wait(){
  local id="$1" maxw="${2:-40}" waited=0
  while :; do
    if [ -d "$RT/completed/$id" ]; then _emit "$id" completed; return 0; fi
    if [ -d "$RT/failed/$id" ]; then _emit "$id" failed; return 1; fi
    [ "$waited" -ge "$maxw" ] && break
    sleep 3; waited=$((waited+3))
  done
  local state="pending"; [ -d "$RT/running/$id" ] && state="running"
  echo "STATE=$state (not finished after ${maxw}s; re-run: exec-job.sh wait $id)"
  return 3
}

cmd_run(){ cmd_submit "$1" "$2" "$3" "${5:-task}"; cmd_wait "$1" "${4:-40}"; }

cmd_devship(){
  local id="$1" inputs="$2" timeout="${3:-900}" maxw="${4:-40}"
  valid_id "$id" || die "bad task id: $id"
  [ -f "$inputs" ] || die "inputs json not found: $inputs"
  [[ "$timeout" =~ ^[0-9]+$ ]] || die "timeout must be an integer: $timeout"
  exists_anywhere "$id" && die "task id already in the pipeline: $id"
  mkdir -p "$RT/staging" "$RT/pending"
  local st="$RT/staging/$id.tmp"
  rm -rf "$st" 2>/dev/null; mkdir -p "$st"
  cp -f "$inputs" "$st/devship-input.json"
  cat > "$st/task.ps1" <<PS1
\$ErrorActionPreference='Continue'
\$inputs = Get-Content -LiteralPath (Join-Path \$PSScriptRoot 'devship-input.json') -Raw
& '$DEVSHIP_WIN' -InputsJson \$inputs
exit \$LASTEXITCODE
PS1
  _write_taskjson "$st" "$id" "$timeout" "dev.ship gate/commit"
  _publish "$id"
  echo "submitted devship $id (timeout=${timeout}s)"
  cmd_wait "$id" "$maxw"
}

cmd_status(){ local id="$1" d; for d in pending running completed failed; do [ -e "$RT/$d/$id" ] && { echo "$d"; return 0; }; done; echo "none"; }

sub="${1:-}"; shift 2>/dev/null || true
case "$sub" in
  submit)  cmd_submit  "$@" ;;
  wait)    cmd_wait    "$@" ;;
  run)     cmd_run     "$@" ;;
  devship) cmd_devship "$@" ;;
  status)  cmd_status  "$@" ;;
  *) echo "usage: exec-job.sh {submit|wait|run|devship|status} ... (see header)" >&2; exit 2 ;;
esac
