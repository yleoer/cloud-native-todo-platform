#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="${1:-todo-process-demo}"
URL="${TODO_DEMO_URL:-http://127.0.0.1:${TODO_DEMO_PORT:-18080}}"
PORT="${TODO_DEMO_PORT:-}"
FAILURES=0

ok() {
  printf '[OK] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

parse_port() {
  local value="${1#http://}"
  value="${value#https://}"
  value="${value%%/*}"
  if [[ "$value" == *:* ]]; then
    printf '%s\n' "${value##*:}"
  elif [[ "$1" == https://* ]]; then
    printf '443\n'
  else
    printf '80\n'
  fi
}

require_command() {
  if command -v "$1" >/dev/null 2>&1; then
    ok "command exists: $1"
  else
    fail "command missing: $1"
  fi
}

require_file() {
  if [[ -f "$1" ]]; then
    ok "file exists: $1"
  else
    fail "file missing: $1"
  fi
}

main() {
  if [[ -z "$PORT" ]]; then
    PORT="$(parse_port "$URL")"
  fi

  require_command systemctl
  require_command journalctl
  require_command curl
  require_command ps
  require_command ss

  require_file /opt/todo-platform/bin/todo-process-demo
  require_file /etc/todo-platform/process-demo.env
  require_file /etc/systemd/system/todo-process-demo.service

  if systemctl is-active --quiet "$SERVICE"; then
    ok "service active: $SERVICE"
  else
    fail "service is not active: $SERVICE"
  fi

  local pid
  pid="$(systemctl show -p MainPID --value "$SERVICE")"
  if [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 0 ]]; then
    ok "MainPID is valid: $pid"
    if ps -p "$pid" -o pid,ppid,user,stat,%cpu,%mem,etime,cmd >/dev/null; then
      ok "process exists for MainPID: $pid"
    else
      fail "process not found for MainPID: $pid"
    fi
  else
    fail "MainPID is invalid: $pid"
  fi

  if [[ -f /run/todo-platform/todo-process-demo.pid ]]; then
    local file_pid
    file_pid="$(cat /run/todo-platform/todo-process-demo.pid)"
    if [[ "$file_pid" == "$pid" ]]; then
      ok "pid file matches MainPID"
    else
      fail "pid file mismatch: file=$file_pid systemd=$pid"
    fi
  else
    fail "pid file missing: /run/todo-platform/todo-process-demo.pid"
  fi

  if curl --noproxy 127.0.0.1,localhost -fsS "$URL/healthz" >/dev/null; then
    ok "health endpoint ok: $URL/healthz"
  else
    fail "health endpoint failed: $URL/healthz"
  fi

  # Do not use -p here: showing process names often requires sudo.
  if ss -lnt | grep -q ":${PORT} "; then
    ok "port listening: $PORT"
  else
    fail "port not listening: $PORT"
  fi

  if journalctl -u "$SERVICE" --since "1 hour ago" --no-pager | grep -q 'todo-process-demo'; then
    ok "journal contains recent service log"
  else
    fail "recent service log not found in journal"
  fi

  if [[ "$FAILURES" -gt 0 ]]; then
    printf '\nProcess service check failed: %s issue(s).\n' "$FAILURES"
    exit 1
  fi

  printf '\nProcess service check completed.\n'
}

main "$@"
