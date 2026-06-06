#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${CF_FINDER_AGENT_SERVICE_NAME:-cf-finder-agent}"
RELEASE_REPO="${RELEASE_REPO:-wxyjay/cffinder-releases}"
INSTALL_DIR="${CF_FINDER_AGENT_INSTALL_DIR:-/etc/cf-finder-agent}"
DATA_DIR="${CF_FINDER_AGENT_DATA_DIR:-/var/lib/cf-finder-agent}"
RUNTIME_DIR="${CF_FINDER_AGENT_RUNTIME_DIR:-/var/run/cf-finder-agent}"
CONFIG_PATH="${CF_FINDER_AGENT_CONFIG_PATH:-${INSTALL_DIR}/config.json}"
BIN_PATH="${INSTALL_DIR}/cf-finder-agent"
BRANCH="main"
ACTION=""
HUB_URL=""
AGENTS_TOKEN=""
AGENT_ID=""
AGENT_SECRET=""
NAME=""
NO_START=0
INTERACTIVE=0
WRITE_CONFIG=0

usage() {
  cat <<'EOF'
Usage:
  install-agent-go.sh [--branch main|debug] [--install|--uninstall|--purge|--status|--interactive]
                      [--hub-url URL] [--agents-token TOKEN] [--agent-id ID]
                      [--agent-secret SECRET] [--name NAME] [--no-start]

Actions:
  --install      Install or update, preserving existing identity and data.
  --uninstall    Stop service and remove program files, preserving config/data.
  --purge        Stop service and remove program files, config and data.
  --status       Show service status.
  --interactive  Show menu.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --install|install|update|reinstall) ACTION="install"; shift ;;
    --uninstall|uninstall|remove) ACTION="uninstall"; shift ;;
    --purge) ACTION="purge"; shift ;;
    --status|status) ACTION="status"; shift ;;
    --interactive) ACTION="interactive"; INTERACTIVE=1; shift ;;
    --hub-url) HUB_URL="${2:-}"; WRITE_CONFIG=1; shift 2 ;;
    --agents-token) AGENTS_TOKEN="${2:-}"; WRITE_CONFIG=1; shift 2 ;;
    --agent-id) AGENT_ID="${2:-}"; WRITE_CONFIG=1; shift 2 ;;
    --agent-secret) AGENT_SECRET="${2:-}"; WRITE_CONFIG=1; shift 2 ;;
    --name) NAME="${2:-}"; WRITE_CONFIG=1; shift 2 ;;
    --no-start) NO_START=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ "$BRANCH" != "main" && "$BRANCH" != "debug" ]]; then
  echo "--branch must be main or debug." >&2
  exit 1
fi

if [[ -z "$ACTION" ]]; then
  if [[ -t 0 ]]; then
    ACTION="interactive"
  else
    ACTION="install"
  fi
fi

require_root() {
  if [[ "$(id -u)" != "0" ]]; then
    echo "Please run as root, for example: curl -fsSL <script-url> | sudo bash -s -- --install" >&2
    exit 1
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "aarch64" ;;
    armv7l|armv7|armhf) echo "armv7" ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
  esac
}

detect_libc() {
  if [[ -f /etc/alpine-release ]]; then
    echo "musl"
  elif command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
    echo "musl"
  else
    echo "glibc"
  fi
}

detect_target() {
  local arch libc
  arch="$(detect_arch)"
  libc="$(detect_libc)"
  if [[ "$libc" == "musl" ]]; then
    case "$arch" in
      amd64|aarch64) echo "alpine-${arch}" ;;
      *) echo "Alpine target does not support arch=${arch}" >&2; exit 1 ;;
    esac
  else
    echo "$arch"
  fi
}

service_manager() {
  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    echo "systemd"
  elif command -v rc-service >/dev/null 2>&1 || [[ -d /run/openrc ]]; then
    echo "openrc"
  else
    echo "none"
  fi
}

manifest_url() {
  local channel="$1"
  printf 'https://raw.githubusercontent.com/%s/%s/manifests/agent-go/%s.json' "$RELEASE_REPO" "$BRANCH" "$channel"
}

download_asset() {
  local target="$1"
  local channel="stable"
  [[ "$BRANCH" == "debug" ]] && channel="debug"
  local tmp_dir="$2"
  local manifest="${tmp_dir}/manifest.json"
  local tag asset

  curl -fsSL "$(manifest_url "$channel")" -o "$manifest"
  tag="$(sed -n 's/.*"tag"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n 1)"
  asset="$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\(cf-finder-agent-[^"]*linux-'"${target}"'\.tar\.gz\)".*/\1/p' "$manifest" | head -n 1)"
  if [[ -z "$tag" || -z "$asset" ]]; then
    echo "No cf-finder-agent asset found for target=${target} in ${channel} manifest." >&2
    exit 1
  fi
  local url="https://github.com/${RELEASE_REPO}/releases/download/${tag}/${asset}"
  curl -fL "$url" -o "${tmp_dir}/${asset}"
  printf '%s\n' "${tmp_dir}/${asset}"
}

json_string() {
  local key="$1"
  [[ -f "$CONFIG_PATH" ]] || return 0
  sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG_PATH" | head -n 1
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_config() {
  local existing_hub existing_token existing_id existing_secret existing_name
  existing_hub="$(json_string hubUrl || true)"
  existing_token="$(json_string agentsToken || true)"
  existing_id="$(json_string agentId || true)"
  existing_secret="$(json_string agentSecret || true)"
  existing_name="$(json_string name || true)"

  HUB_URL="${HUB_URL:-$existing_hub}"
  AGENTS_TOKEN="${AGENTS_TOKEN:-$existing_token}"
  AGENT_ID="${AGENT_ID:-$existing_id}"
  AGENT_SECRET="${AGENT_SECRET:-$existing_secret}"
  NAME="${NAME:-$existing_name}"
  NAME="${NAME:-$(hostname 2>/dev/null || echo cf-finder-agent)}"

  if [[ -z "$HUB_URL" || -z "$AGENTS_TOKEN" ]]; then
    echo "Missing --hub-url or --agents-token. Use --interactive for guided setup." >&2
    exit 1
  fi

  mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$RUNTIME_DIR"
  cat > "$CONFIG_PATH" <<EOF
{
  "version": 1,
  "dataDir": "$(json_escape "$DATA_DIR")",
  "runtimeDir": "$(json_escape "$RUNTIME_DIR")",
  "agent": {
    "enabled": true,
    "hubUrl": "$(json_escape "$HUB_URL")",
    "agentsToken": "$(json_escape "$AGENTS_TOKEN")",
    "agentId": "$(json_escape "$AGENT_ID")",
    "agentSecret": "$(json_escape "$AGENT_SECRET")",
    "name": "$(json_escape "$NAME")",
    "heartbeatSeconds": 30,
    "registerBackoffMinSeconds": 3,
    "registerBackoffMaxSeconds": 60
  },
  "ddns": {
    "enabled": true
  },
  "singbox": {
    "enabled": true,
    "binaryPath": "$(json_escape "$DATA_DIR")/singbox/bin/sing-box",
    "configPath": "$(json_escape "$DATA_DIR")/singbox/effective.json"
  }
}
EOF
  chmod 600 "$CONFIG_PATH"
}

write_systemd_unit() {
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=CFFinder Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${BIN_PATH} run -config ${CONFIG_PATH}
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

write_openrc_service() {
  cat > "/etc/init.d/${SERVICE_NAME}" <<EOF
#!/sbin/openrc-run
name="CFFinder Agent"
command="${BIN_PATH}"
command_args="run -config ${CONFIG_PATH}"
command_background="yes"
pidfile="/run/${SERVICE_NAME}.pid"
output_log="${RUNTIME_DIR}/service.log"
error_log="${RUNTIME_DIR}/service.err"
depend() {
  need net
  after firewall
}
EOF
  chmod +x "/etc/init.d/${SERVICE_NAME}"
}

enable_and_start() {
  local manager
  manager="$(service_manager)"
  case "$manager" in
    systemd)
      write_systemd_unit
      systemctl daemon-reload
      systemctl enable "$SERVICE_NAME"
      if [[ "$NO_START" -eq 0 ]]; then
        systemctl restart "$SERVICE_NAME"
      fi
      systemctl --no-pager status "$SERVICE_NAME" || true
      ;;
    openrc)
      write_openrc_service
      rc-update add "$SERVICE_NAME" default >/dev/null 2>&1 || true
      if [[ "$NO_START" -eq 0 ]]; then
        rc-service "$SERVICE_NAME" restart || rc-service "$SERVICE_NAME" start || true
      fi
      rc-service "$SERVICE_NAME" status || true
      ;;
    *)
      echo "No supported service manager found. Binary installed at ${BIN_PATH}."
      ;;
  esac
}

install_or_update() {
  require_root
  need_cmd curl
  need_cmd tar
  local target tmp_dir archive
  target="$(detect_target)"
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  echo "Installing CFFinder Agent (${BRANCH}, ${target})"
  archive="$(download_asset "$target" "$tmp_dir")"

  mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$RUNTIME_DIR"
  tar -xzf "$archive" -C "$tmp_dir"
  if [[ ! -x "${tmp_dir}/cf-finder-agent" ]]; then
    echo "Archive does not contain cf-finder-agent binary." >&2
    exit 1
  fi
  if [[ -x "$BIN_PATH" ]]; then
    cp -f "$BIN_PATH" "${BIN_PATH}.bak"
  fi
  install -m 0755 "${tmp_dir}/cf-finder-agent" "$BIN_PATH"

  if [[ "$WRITE_CONFIG" -eq 1 || ! -f "$CONFIG_PATH" ]]; then
    write_config
  else
    echo "Keeping existing config: ${CONFIG_PATH}"
  fi
  enable_and_start
}

stop_disable() {
  local manager
  manager="$(service_manager)"
  case "$manager" in
    systemd)
      systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
      systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
      rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
      systemctl daemon-reload >/dev/null 2>&1 || true
      ;;
    openrc)
      rc-service "$SERVICE_NAME" stop >/dev/null 2>&1 || true
      rc-update del "$SERVICE_NAME" default >/dev/null 2>&1 || true
      rm -f "/etc/init.d/${SERVICE_NAME}"
      ;;
  esac
}

uninstall_keep_data() {
  require_root
  stop_disable
  rm -f "$BIN_PATH" "${BIN_PATH}.bak"
  echo "Removed program files. Config/data preserved: ${INSTALL_DIR}, ${DATA_DIR}"
}

purge_all() {
  require_root
  stop_disable
  rm -rf "$INSTALL_DIR" "$DATA_DIR" "$RUNTIME_DIR"
  echo "Removed program files, config and data."
}

show_status() {
  local manager
  manager="$(service_manager)"
  case "$manager" in
    systemd) systemctl --no-pager status "$SERVICE_NAME" || true ;;
    openrc) rc-service "$SERVICE_NAME" status || true ;;
    *) echo "No supported service manager found." ;;
  esac
}

interactive_menu() {
  echo "CFFinder Agent installer"
  echo "1) Install or update"
  echo "2) Uninstall (keep config/data)"
  echo "3) Purge (remove config/data)"
  echo "4) Status"
  read -r -p "Choose: " choice
  case "$choice" in
    1)
      read -r -p "Branch main/debug (Enter keeps ${BRANCH}): " input_branch
      BRANCH="${input_branch:-$BRANCH}"
      if [[ ! -f "$CONFIG_PATH" ]]; then
        read -r -p "Hub URL: " HUB_URL
        read -r -p "Agents token: " AGENTS_TOKEN
        read -r -p "Agent ID (optional, Enter for new): " AGENT_ID
        read -r -p "Agent secret (optional): " AGENT_SECRET
        read -r -p "Name (optional): " NAME
        WRITE_CONFIG=1
      fi
      install_or_update
      ;;
    2) uninstall_keep_data ;;
    3) purge_all ;;
    4) show_status ;;
    *) echo "Cancelled." ;;
  esac
}

case "$ACTION" in
  install) install_or_update ;;
  uninstall) uninstall_keep_data ;;
  purge) purge_all ;;
  status) show_status ;;
  interactive) interactive_menu ;;
  *) usage; exit 1 ;;
esac
