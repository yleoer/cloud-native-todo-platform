#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_DIR="$ROOT_DIR/server/todo-platform"
FAILURES=0

ok() {
  printf '[OK] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

file_mode() {
  local path="$1"
  local mode
  mode="$(stat -c '%a' "$path")"
  printf '%s\n' "$mode" | sed 's/^0*//; s/^$/0/'
}

require_dir() {
  local path="$1"
  if [[ -d "$path" ]]; then
    ok "directory exists: ${path#$ROOT_DIR/}"
  else
    fail "directory missing: ${path#$ROOT_DIR/}"
  fi
}

require_file() {
  local path="$1"
  if [[ -f "$path" ]]; then
    ok "file exists: ${path#$ROOT_DIR/}"
  else
    fail "file missing: ${path#$ROOT_DIR/}"
  fi
}

require_mode() {
  local path="$1"
  local expected="$2"
  if [[ ! -e "$path" ]]; then
    fail "cannot check mode, path missing: ${path#$ROOT_DIR/}"
    return
  fi

  local actual
  actual="$(file_mode "$path")"
  if [[ "$actual" == "$expected" ]]; then
    ok "mode ${expected}: ${path#$ROOT_DIR/}"
  else
    fail "mode expected ${expected}, got ${actual}: ${path#$ROOT_DIR/}"
  fi
}

require_symlink_target() {
  local path="$1"
  local expected="$2"
  if [[ ! -L "$path" ]]; then
    fail "symlink missing: ${path#$ROOT_DIR/}"
    return
  fi

  local actual
  actual="$(readlink "$path")"
  if [[ "$actual" == "$expected" ]]; then
    ok "symlink target ${expected}: ${path#$ROOT_DIR/}"
  else
    fail "symlink target expected ${expected}, got ${actual}: ${path#$ROOT_DIR/}"
  fi
}

main() {
  require_dir "$BASE_DIR"
  require_dir "$BASE_DIR/config"
  require_dir "$BASE_DIR/logs"
  require_dir "$BASE_DIR/data"
  require_dir "$BASE_DIR/tmp"
  require_dir "$BASE_DIR/releases/2026-05-27-001"

  require_file "$BASE_DIR/config/app.env"
  require_file "$BASE_DIR/config/app.env.backup"
  require_file "$BASE_DIR/logs/todo-api.log"
  require_file "$BASE_DIR/data/.keep"
  require_file "$BASE_DIR/releases/2026-05-27-001/README.md"

  require_mode "$BASE_DIR/config" "750"
  require_mode "$BASE_DIR/logs" "750"
  require_mode "$BASE_DIR/data" "750"
  require_mode "$BASE_DIR/releases" "750"
  require_mode "$BASE_DIR/config/app.env" "640"
  require_mode "$BASE_DIR/config/app.env.backup" "640"
  require_mode "$BASE_DIR/logs/todo-api.log" "640"
  require_mode "$BASE_DIR/tmp" "700"
  require_symlink_target "$BASE_DIR/current" "releases/2026-05-27-001"

  if grep -q 'TODO_ENV=dev' "$BASE_DIR/config/app.env"; then
    ok "app.env contains TODO_ENV=dev"
  else
    fail "app.env does not contain TODO_ENV=dev"
  fi

  if grep -q 'ERROR' "$BASE_DIR/logs/todo-api.log"; then
    ok "sample log contains ERROR line for grep practice"
  else
    warn "sample log does not contain ERROR line"
  fi

  if [[ "$FAILURES" -gt 0 ]]; then
    printf '\nServer layout check failed: %s issue(s).\n' "$FAILURES"
    exit 1
  fi

  printf '\nServer layout check completed.\n'
}

main "$@"