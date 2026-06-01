#!/usr/bin/env bash
set -Eeuo pipefail

ok() {
  printf '[OK] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1"
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$script_dir/versions.conf" ]]; then
  # shellcheck disable=SC1091
  source "$script_dir/versions.conf"
fi

need_cmd() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    ok "$name found: $(command -v "$name")"
  else
    fail "$name not found in PATH"
  fi
}

version_output=""

show_and_capture_version() {
  local name="$1"
  shift
  printf '\n==> %s\n' "$name"
  if version_output="$("$@" 2>&1)"; then
    printf '%s\n' "$version_output"
  else
    printf '%s\n' "$version_output"
    fail "$name version check failed"
  fi
}

warn_if_missing_prefix() {
  local name="$1"
  local output="$2"
  local expected="$3"
  if [[ -z "$expected" ]]; then
    return 0
  fi
  if [[ "$output" == *"$expected"* ]]; then
    ok "$name matches expected prefix: $expected"
  else
    warn "$name does not match expected prefix: $expected"
  fi
}

main() {
  need_cmd go
  need_cmd git
  need_cmd docker
  need_cmd kubectl
  need_cmd kind
  need_cmd helm

  show_and_capture_version "Go" go version
  go_version="$version_output"
  show_and_capture_version "Go proxy" go env GOPROXY
  go_proxy="$version_output"
  show_and_capture_version "Git" git --version
  show_and_capture_version "Docker CLI" docker --version
  docker_version="$version_output"
  show_and_capture_version "kubectl" kubectl version --client
  kubectl_version="$version_output"
  show_and_capture_version "kind" kind version
  kind_version="$version_output"
  show_and_capture_version "Helm" helm version --template '{{.Version}}'
  helm_version="$version_output"

  warn_if_missing_prefix "Go" "$go_version" "${GO_REQUIRED_PREFIX:-}"
  warn_if_missing_prefix "Go proxy" "$go_proxy" "${GO_PROXY_REQUIRED:-}"
  warn_if_missing_prefix "Docker CLI" "$docker_version" "${DOCKER_REQUIRED_PREFIX:-}"
  warn_if_missing_prefix "kubectl" "$kubectl_version" "${KUBECTL_REQUIRED_PREFIX:-}"
  warn_if_missing_prefix "kind" "$kind_version" "${KIND_REQUIRED_PREFIX:-}"
  warn_if_missing_prefix "Helm" "$helm_version" "${HELM_REQUIRED_PREFIX:-}"

  printf '\n==> Docker daemon\n'

  if docker info >/dev/null 2>&1; then
    ok "Docker daemon is reachable"
  else
    warn "Docker CLI exists, but Docker daemon is not reachable"
    warn "Start Docker Engine, then run this script again"
  fi

  printf '\nEnvironment check completed.\n'
}

main "$@"