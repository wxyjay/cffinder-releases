#!/bin/sh
set -eu

SERVICE_NAME="${CF_FINDER_AGENT_LITE_SERVICE_NAME:-cffinder-agent-lite}"
RELEASE_REPO="${RELEASE_REPO:-wxyjay/cffinder-releases}"
BRANCH="main"
ACTION=""
HUB_URL=""
AGENTS_TOKEN=""
AGENT_ID=""
AGENT_SECRET=""
NAME=""
NO_START=0
RUN_FOREGROUND=0
WRITE_CONFIG=0
INSTALL_STYLE=""
SERVICE_MANAGER=""
INSTALL_DIR=""
BIN_PATH=""
DATA_DIR=""
RUNTIME_DIR=""
CONFIG_PATH=""
TMP_DIR_TO_CLEAN=""
LOCK_DIR_TO_CLEAN=""
INSTALL_CONTRACT_PATH=""

cleanup() {
  cleanup_status="$?"
  if [ "$cleanup_status" -ne 0 ] && [ -n "${CFFINDER_SELFUPDATE_STATUS_FILE:-}" ]; then
    selfupdate_status "failed" "1" "Agent Lite installation failed" "false" "Agent Lite installation failed" || true
  fi
  if [ -n "${TMP_DIR_TO_CLEAN:-}" ]; then
    rm -rf "$TMP_DIR_TO_CLEAN"
  fi
  if [ -n "${LOCK_DIR_TO_CLEAN:-}" ]; then
    rm -rf "$LOCK_DIR_TO_CLEAN"
  fi
}

if [ "${CFFINDER_INSTALLER_LIB_ONLY:-0}" != "1" ]; then
  trap cleanup EXIT HUP INT TERM
fi

usage() {
  cat <<'EOF'
Usage:
  install-agent-lite.sh [--branch main|debug]
                        [--install|--uninstall|--purge|--status|--interactive]
                        [--hub-url URL] [--agents-token TOKEN]
                        [--agent-id ID] [--agent-secret SECRET] [--name NAME]
                        [--no-start] [--run]

The installer detects a real systemd/OpenRC host automatically. Otherwise it
uses a user-writable foreground installation suitable for restricted Linux
containers and minimal virtual machines.

Actions:
  --install      Install or update while preserving existing identity/data.
  --uninstall    Remove program/service files and preserve config/data.
  --purge        Remove program/service files plus config/data.
  --status       Show the detected installation status.
  --interactive  Show a guided menu when stdin is a terminal.
  --run          After a portable install, replace this shell with the Agent.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --install|install|update|reinstall) ACTION="install"; shift ;;
    --uninstall|uninstall|remove) ACTION="uninstall"; shift ;;
    --purge) ACTION="purge"; shift ;;
    --status|status) ACTION="status"; shift ;;
    --interactive) ACTION="interactive"; shift ;;
    --hub-url) HUB_URL="${2:-}"; WRITE_CONFIG=1; shift 2 ;;
    --agents-token) AGENTS_TOKEN="${2:-}"; WRITE_CONFIG=1; shift 2 ;;
    --agent-id) AGENT_ID="${2:-}"; WRITE_CONFIG=1; shift 2 ;;
    --agent-secret) AGENT_SECRET="${2:-}"; WRITE_CONFIG=1; shift 2 ;;
    --name) NAME="${2:-}"; WRITE_CONFIG=1; shift 2 ;;
    --no-start) NO_START=1; shift ;;
    --run) RUN_FOREGROUND=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage; exit 1 ;;
  esac
done

current_uid() {
  id -u
}

current_home() {
  if [ -n "${HOME:-}" ]; then
    printf '%s\n' "$HOME"
  else
    printf '/tmp\n'
  fi
}

existing_service_manager() {
  if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
    printf 'systemd\n'
  elif [ -f "/etc/init.d/${SERVICE_NAME}" ]; then
    printf 'openrc\n'
  else
    printf 'none\n'
  fi
}

service_manager() {
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    printf 'systemd\n'
  elif command -v rc-service >/dev/null 2>&1 \
    && { [ -d /run/openrc ] || [ -e /run/openrc/softlevel ]; }; then
    printf 'openrc\n'
  else
    printf 'none\n'
  fi
}

resolve_install_layout() {
  layout_uid="$(current_uid)"
  layout_home="$(current_home)"
  layout_existing_manager="$(existing_service_manager)"
  layout_active_manager="$(service_manager)"

  if [ "$layout_existing_manager" != "none" ]; then
    INSTALL_STYLE="service"
    SERVICE_MANAGER="$layout_existing_manager"
  elif [ "$layout_uid" = "0" ] && [ "$layout_active_manager" != "none" ]; then
    INSTALL_STYLE="service"
    SERVICE_MANAGER="$layout_active_manager"
  else
    INSTALL_STYLE="portable"
    SERVICE_MANAGER="none"
  fi

  if [ "$INSTALL_STYLE" = "service" ]; then
    INSTALL_DIR="${CF_FINDER_AGENT_LITE_INSTALL_DIR:-/usr/local/bin}"
    DATA_DIR="${CF_FINDER_AGENT_LITE_DATA_DIR:-/var/lib/cffinder-agent-lite}"
  elif [ "$layout_uid" = "0" ]; then
    INSTALL_DIR="${CF_FINDER_AGENT_LITE_INSTALL_DIR:-/usr/local/bin}"
    DATA_DIR="${CF_FINDER_AGENT_LITE_DATA_DIR:-/data}"
  else
    INSTALL_DIR="${CF_FINDER_AGENT_LITE_INSTALL_DIR:-${XDG_BIN_HOME:-${layout_home}/.local/bin}}"
    DATA_DIR="${CF_FINDER_AGENT_LITE_DATA_DIR:-${XDG_DATA_HOME:-${layout_home}/.local/share}/cffinder-agent-lite}"
  fi

  BIN_PATH="${INSTALL_DIR}/cf-finder-agent-lite"
  RUNTIME_DIR="${CF_FINDER_AGENT_LITE_RUNTIME_DIR:-${DATA_DIR}/run}"
  CONFIG_PATH="${CF_FINDER_AGENT_LITE_CONFIG_PATH:-${DATA_DIR}/config.json}"
}

detect_arch_from() {
  case "$1" in
    x86_64|amd64) printf 'amd64\n' ;;
    aarch64|arm64) printf 'aarch64\n' ;;
    armv7l|armv7|armhf) printf 'armv7\n' ;;
    *) printf 'Unsupported architecture: %s\n' "$1" >&2; return 1 ;;
  esac
}

detect_arch() {
  detect_arch_from "$(uname -m)"
}

manifest_url() {
  manifest_channel="$1"
  printf 'https://raw.githubusercontent.com/%s/%s/manifests/agent-lite/%s.json' \
    "$RELEASE_REPO" "$BRANCH" "$manifest_channel"
}

manifest_string() {
  manifest_file="$1"
  manifest_key="$2"
  sed -n 's/.*"'"$manifest_key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest_file" | head -n 1
}

select_asset() {
  asset_manifest="$1"
  asset_target="$2"
  sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\(cf-finder-agent-lite-[^"]*-linux-'"$asset_target"'\.tar\.gz\)".*/\1/p' "$asset_manifest" | head -n 1
}

extract_asset_sha() {
  checksum_manifest="$1"
  checksum_asset="$2"
  awk -v target="$checksum_asset" '
    {
      line = $0
      if (line ~ /"name"[[:space:]]*:[[:space:]]*"/) {
        name = line
        sub(/^.*"name"[[:space:]]*:[[:space:]]*"/, "", name)
        sub(/".*$/, "", name)
        current = name
      }
      if (current == target && line ~ /"sha256"[[:space:]]*:[[:space:]]*"/) {
        sha = line
        sub(/^.*"sha256"[[:space:]]*:[[:space:]]*"/, "", sha)
        sub(/".*$/, "", sha)
        print sha
        exit
      }
    }
  ' "$checksum_manifest"
}

sha256_file() {
  checksum_file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$checksum_file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$checksum_file" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$checksum_file" | awk '{print $NF}'
  else
    printf 'Missing sha256sum, shasum, or openssl.\n' >&2
    return 1
  fi
}

download_to() {
  download_url="$1"
  download_output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$download_url" -o "$download_output"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$download_output" "$download_url"
  else
    printf 'Missing curl or wget.\n' >&2
    return 1
  fi
}

ensure_dependencies() {
  dependency_missing=""
  for dependency_command in tar uname sed awk grep mktemp chmod mkdir mv cp rm head dirname sleep id date; do
    if ! command -v "$dependency_command" >/dev/null 2>&1; then
      dependency_missing="${dependency_missing} ${dependency_command}"
    fi
  done
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    dependency_missing="${dependency_missing} curl-or-wget"
  fi
  if ! command -v sha256sum >/dev/null 2>&1 \
    && ! command -v shasum >/dev/null 2>&1 \
    && ! command -v openssl >/dev/null 2>&1; then
    dependency_missing="${dependency_missing} sha256-tool"
  fi
  if [ -n "$dependency_missing" ]; then
    printf 'Missing required command(s):%s\n' "$dependency_missing" >&2
    printf 'Install them with the environment package manager, then rerun. No package index update is performed automatically.\n' >&2
    return 1
  fi
}

json_string() {
  json_key="$1"
  [ -f "$CONFIG_PATH" ] || return 0
  sed -n 's/.*"'"$json_key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG_PATH" | head -n 1
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

selfupdate_status() {
  status_path="${CFFINDER_SELFUPDATE_STATUS_FILE:-}"
  [ -n "$status_path" ] || return 0
  status_phase="$1"
  status_progress="$2"
  status_message="$3"
  status_running="${4:-false}"
  status_error="${5:-}"
  status_operation="${CFFINDER_SELFUPDATE_OPERATION:-updating}"
  status_current_version="${CFFINDER_SELFUPDATE_CURRENT_VERSION:-unknown}"
  status_current_channel="${CFFINDER_SELFUPDATE_CURRENT_CHANNEL:-stable}"
  status_target_version="${CFFINDER_SELFUPDATE_TARGET_VERSION:-$status_current_version}"
  status_target_channel="${CFFINDER_SELFUPDATE_TARGET_CHANNEL:-$status_current_channel}"
  status_update_available="true"
  [ "$status_phase" = "completed" ] && status_update_available="false"
  status_now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  status_parent="$(dirname "$status_path")"
  mkdir -p "$status_parent"
  status_temporary="${status_path}.tmp.$$"
  cat > "$status_temporary" <<EOF
{
  "version": {
    "currentVersion": "$(json_escape "$status_current_version")",
    "currentChannel": "$(json_escape "$status_current_channel")",
    "latestVersion": "$(json_escape "$status_target_version")",
    "latestChannel": "$(json_escape "$status_target_channel")",
    "updateAvailable": $status_update_available,
    "lastCheckedAt": "$status_now"
  },
  "operation": "$(json_escape "$status_operation")",
  "phase": "$(json_escape "$status_phase")",
  "progress": $status_progress,
  "message": "$(json_escape "$status_message")",
  "isRunning": $status_running,
  "error": "$(json_escape "$status_error")",
  "targetVersion": "$(json_escape "$status_target_version")",
  "targetChannel": "$(json_escape "$status_target_channel")",
  "updatedAt": "$status_now"
}
EOF
  chmod 600 "$status_temporary"
  mv -f "$status_temporary" "$status_path"
}

write_install_contract() {
  contract_channel="stable"
  [ "$BRANCH" = "debug" ] && contract_channel="debug"
  contract_self_update="false"
  if [ "$INSTALL_STYLE" = "service" ] \
    && { [ "$SERVICE_MANAGER" = "systemd" ] || [ "$SERVICE_MANAGER" = "openrc" ]; }; then
    contract_self_update="true"
  fi
  INSTALL_CONTRACT_PATH="${DATA_DIR}/install-contract.json"
  mkdir -p "$DATA_DIR"
  contract_temporary="${INSTALL_CONTRACT_PATH}.tmp.$$"
  cat > "$contract_temporary" <<EOF
{
  "schemaVersion": 1,
  "productType": "agent-lite",
  "installStyle": "$(json_escape "$INSTALL_STYLE")",
  "serviceManager": "$(json_escape "$SERVICE_MANAGER")",
  "serviceName": "$(json_escape "$SERVICE_NAME")",
  "binaryPath": "$(json_escape "$BIN_PATH")",
  "configPath": "$(json_escape "$CONFIG_PATH")",
  "dataDir": "$(json_escape "$DATA_DIR")",
  "channel": "$contract_channel",
  "releaseRepo": "$(json_escape "$RELEASE_REPO")",
  "selfUpdateEnabled": $contract_self_update
}
EOF
  chmod 600 "$contract_temporary"
  mv -f "$contract_temporary" "$INSTALL_CONTRACT_PATH"
}

write_config() {
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

  if [ -z "$HUB_URL" ] || [ -z "$AGENTS_TOKEN" ]; then
    printf 'A new installation requires --hub-url and --agents-token.\n' >&2
    return 1
  fi

  mkdir -p "$DATA_DIR" "$RUNTIME_DIR"
  config_temporary="${CONFIG_PATH}.tmp.$$"
  cat > "$config_temporary" <<EOF
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
    "heartbeatSeconds": 60,
    "registerBackoffMinSeconds": 3,
    "registerBackoffMaxSeconds": 60
  }
}
EOF
  chmod 600 "$config_temporary"
  mv -f "$config_temporary" "$CONFIG_PATH"
}

write_systemd_unit() {
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=CFFinder Agent Lite
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
name="CFFinder Agent Lite"
command="${BIN_PATH}"
command_args="run -config ${CONFIG_PATH}"
command_background="yes"
pidfile="${RUNTIME_DIR}/${SERVICE_NAME}.pid"
output_log="${RUNTIME_DIR}/service.log"
error_log="${RUNTIME_DIR}/service.err"
depend() {
  need net
  after firewall
}
limit_service_log() {
  log_path="\$1"
  [ -f "\$log_path" ] || return 0
  log_size="\$(wc -c < "\$log_path" 2>/dev/null || printf '0')"
  [ "\$log_size" -le 2097152 ] && return 0
  tail -c 2097152 "\$log_path" > "\$log_path.tmp" 2>/dev/null && mv -f "\$log_path.tmp" "\$log_path"
}
start_pre() {
  checkpath -d -m 0755 "${DATA_DIR}"
  checkpath -d -m 0755 "${RUNTIME_DIR}"
  limit_service_log "\$output_log"
  limit_service_log "\$error_log"
}
EOF
  chmod +x "/etc/init.d/${SERVICE_NAME}"
}

start_service() {
  case "$SERVICE_MANAGER" in
    systemd)
      write_systemd_unit
      systemctl daemon-reload
      systemctl enable "$SERVICE_NAME" >/dev/null
      [ "$NO_START" = "1" ] && return 0
      systemctl restart "$SERVICE_NAME"
      sleep 2
      systemctl is-active --quiet "$SERVICE_NAME"
      ;;
    openrc)
      write_openrc_service
      rc-update add "$SERVICE_NAME" default >/dev/null 2>&1 || true
      [ "$NO_START" = "1" ] && return 0
      rc-service "$SERVICE_NAME" restart >/dev/null 2>&1 || rc-service "$SERVICE_NAME" start >/dev/null
      sleep 2
      rc-service "$SERVICE_NAME" status >/dev/null
      ;;
  esac
}

remove_service() {
  case "$SERVICE_MANAGER" in
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

acquire_install_lock() {
  lock_parent="$(dirname "$DATA_DIR")"
  mkdir -p "$lock_parent"
  LOCK_DIR_TO_CLEAN="${DATA_DIR}.install.lock"
  if mkdir "$LOCK_DIR_TO_CLEAN" 2>/dev/null; then
    printf '%s\n' "$$" > "${LOCK_DIR_TO_CLEAN}/pid"
    return 0
  fi
  lock_pid="$(sed -n '1p' "${LOCK_DIR_TO_CLEAN}/pid" 2>/dev/null || true)"
  if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
    printf 'Another Agent Lite install operation is already running: %s\n' "$LOCK_DIR_TO_CLEAN" >&2
    return 1
  fi
  rm -rf "$LOCK_DIR_TO_CLEAN"
  mkdir "$LOCK_DIR_TO_CLEAN"
  printf '%s\n' "$$" > "${LOCK_DIR_TO_CLEAN}/pid"
}

download_release() {
  release_target="$1"
  release_output_dir="$2"
  release_channel="stable"
  [ "$BRANCH" = "debug" ] && release_channel="debug"
  release_manifest="${release_output_dir}/manifest.json"
  download_to "$(manifest_url "$release_channel")" "$release_manifest"
  if [ "$(manifest_string "$release_manifest" project)" != "agent-lite" ]; then
    printf 'Invalid Agent Lite manifest.\n' >&2
    return 1
  fi
  release_tag="$(manifest_string "$release_manifest" tag)"
  release_asset="$(select_asset "$release_manifest" "$release_target")"
  release_expected_sha="$(extract_asset_sha "$release_manifest" "$release_asset")"
  if [ -z "$release_tag" ] || [ -z "$release_asset" ] || [ -z "$release_expected_sha" ]; then
    printf 'No verified Agent Lite asset for architecture %s.\n' "$release_target" >&2
    return 1
  fi
  release_archive_url="https://github.com/${RELEASE_REPO}/releases/download/${release_tag}/${release_asset}"
  download_to "$release_archive_url" "${release_output_dir}/${release_asset}"
  release_actual_sha="$(sha256_file "${release_output_dir}/${release_asset}")"
  if [ "$release_actual_sha" != "$release_expected_sha" ]; then
    printf 'SHA256 mismatch for %s: got %s, expected %s\n' \
      "$release_asset" "$release_actual_sha" "$release_expected_sha" >&2
    return 1
  fi
  printf '%s\n' "${release_output_dir}/${release_asset}"
}

install_or_update() {
  ensure_dependencies
  resolve_install_layout
  if [ "$INSTALL_STYLE" = "service" ] && [ "$(current_uid)" != "0" ]; then
    printf 'The existing service installation requires a root shell.\n' >&2
    return 1
  fi
  acquire_install_lock
  selfupdate_status "checking_latest" "0.08" "checking latest Agent Lite release" "true" ""
  TMP_DIR_TO_CLEAN="$(mktemp -d "${TMPDIR:-/tmp}/cffinder-agent-lite-install.XXXXXX")"
  install_target="$(detect_arch)"
  printf 'Installing CFFinder Agent Lite (%s, %s, %s)\n' "$BRANCH" "$install_target" "$INSTALL_STYLE"
  selfupdate_status "downloading" "0.18" "downloading Agent Lite package" "true" ""
  install_archive="$(download_release "$install_target" "$TMP_DIR_TO_CLEAN")"
  install_extracted="${TMP_DIR_TO_CLEAN}/extracted"
  mkdir -p "$install_extracted"
  tar -xzf "$install_archive" -C "$install_extracted"
  install_candidate="${install_extracted}/cf-finder-agent-lite"
  install_inner_checksum="${install_extracted}/cf-finder-agent-lite.sha256"
  [ -f "$install_candidate" ] || { printf 'Release archive does not contain cf-finder-agent-lite.\n' >&2; return 1; }
  [ -f "$install_inner_checksum" ] || { printf 'Release archive does not contain the binary checksum.\n' >&2; return 1; }
  install_expected_inner="$(awk '{print $1; exit}' "$install_inner_checksum")"
  install_actual_inner="$(sha256_file "$install_candidate")"
  selfupdate_status "verifying" "0.5" "verifying Agent Lite package" "true" ""
  if [ -z "$install_expected_inner" ] || [ "$install_actual_inner" != "$install_expected_inner" ]; then
    printf 'Agent Lite binary checksum mismatch inside the release archive.\n' >&2
    return 1
  fi
  chmod 0755 "$install_candidate"
  "$install_candidate" version >/dev/null

  mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$RUNTIME_DIR"
  if [ ! -f "$CONFIG_PATH" ]; then
    write_config
  else
    printf 'Keeping existing config: %s\n' "$CONFIG_PATH"
    if [ "$WRITE_CONFIG" = "1" ]; then
      printf 'Connection and identity arguments are only used to initialize a new config.\n'
    fi
  fi

  install_contract="${DATA_DIR}/install-contract.json"
  install_contract_backup="${install_contract}.bak"
  install_had_contract=0
  if [ -f "$install_contract" ]; then
    cp -f "$install_contract" "$install_contract_backup"
    install_had_contract=1
  fi
  write_install_contract

  install_backup="${BIN_PATH}.bak"
  install_had_previous=0
  if [ -f "$BIN_PATH" ]; then
    cp -f "$BIN_PATH" "$install_backup"
    install_had_previous=1
  fi
  selfupdate_status "installing" "0.72" "installing Agent Lite" "true" ""
  cp -f "$install_candidate" "${BIN_PATH}.new.$$"
  chmod 0755 "${BIN_PATH}.new.$$"
  mv -f "${BIN_PATH}.new.$$" "$BIN_PATH"

  if [ "$INSTALL_STYLE" = "service" ]; then
    selfupdate_status "waiting_restart" "0.92" "restarting Agent Lite service" "true" ""
    if ! start_service; then
      printf 'Agent Lite service failed to start; restoring the previous binary.\n' >&2
      if [ "$install_had_previous" = "1" ]; then
        mv -f "$install_backup" "$BIN_PATH"
        start_service || true
      else
        rm -f "$BIN_PATH"
        remove_service
      fi
      if [ "$install_had_contract" = "1" ]; then
        mv -f "$install_contract_backup" "$install_contract"
      else
        rm -f "$install_contract" "$install_contract_backup"
      fi
      return 1
    fi
    rm -f "$install_backup" "$install_contract_backup"
    selfupdate_status "completed" "1" "updated and restarted" "false" ""
    show_status
    return 0
  fi

  rm -f "$install_backup" "$install_contract_backup"
  selfupdate_status "completed" "1" "portable installation completed" "false" ""
  printf 'Portable installation ready.\n'
  printf 'Binary: %s\nConfig: %s\nData:   %s\n' "$BIN_PATH" "$CONFIG_PATH" "$DATA_DIR"
  printf "Run: '%s' run -config '%s'\n" "$BIN_PATH" "$CONFIG_PATH"
  if [ "$RUN_FOREGROUND" = "1" ] && [ "$NO_START" = "0" ]; then
    cleanup
    trap - EXIT HUP INT TERM
    exec "$BIN_PATH" run -config "$CONFIG_PATH"
  fi
}

uninstall_keep_data() {
  resolve_install_layout
  if [ "$INSTALL_STYLE" = "service" ] && [ "$(current_uid)" != "0" ]; then
    printf 'Removing the existing service installation requires root.\n' >&2
    return 1
  fi
  remove_service
  rm -f "$BIN_PATH" "${BIN_PATH}.bak"
  if [ "$INSTALL_STYLE" = "portable" ]; then
    printf 'Any running foreground process must be stopped by its container or process supervisor.\n'
  fi
  printf 'Removed Agent Lite program files. Config/data preserved: %s\n' "$DATA_DIR"
}

purge_all() {
  resolve_install_layout
  if [ "$INSTALL_STYLE" = "service" ] && [ "$(current_uid)" != "0" ]; then
    printf 'Purging the existing service installation requires root.\n' >&2
    return 1
  fi
  remove_service
  rm -f "$BIN_PATH" "${BIN_PATH}.bak"
  rm -rf "$DATA_DIR"
  printf 'Removed Agent Lite program files, config, and data.\n'
}

show_status() {
  resolve_install_layout
  printf 'Install style: %s\nBinary: %s\nConfig: %s\nData: %s\n' \
    "$INSTALL_STYLE" "$BIN_PATH" "$CONFIG_PATH" "$DATA_DIR"
  if [ -x "$BIN_PATH" ]; then
    printf 'Version: '
    "$BIN_PATH" version || true
  else
    printf 'Binary is not installed.\n'
  fi
  case "$SERVICE_MANAGER" in
    systemd) systemctl --no-pager status "$SERVICE_NAME" || true ;;
    openrc) rc-service "$SERVICE_NAME" status || true ;;
    none) printf "Foreground command: '%s' run -config '%s'\n" "$BIN_PATH" "$CONFIG_PATH" ;;
  esac
}

interactive_menu() {
  printf 'CFFinder Agent Lite installer\n'
  printf '1) Install or update\n2) Uninstall and keep data\n3) Purge\n4) Status\n'
  printf 'Choose: '
  read -r menu_choice
  case "$menu_choice" in
    1)
      printf 'Branch main/debug (Enter keeps %s): ' "$BRANCH"
      read -r menu_branch
      BRANCH="${menu_branch:-$BRANCH}"
      if [ "$BRANCH" != "main" ] && [ "$BRANCH" != "debug" ]; then
        printf 'Branch must be main or debug.\n' >&2
        return 1
      fi
      resolve_install_layout
      if [ ! -f "$CONFIG_PATH" ]; then
        printf 'Hub URL: '; read -r HUB_URL
        printf 'Agents token: '; read -r AGENTS_TOKEN
        printf 'Agent ID (optional): '; read -r AGENT_ID
        printf 'Agent secret (optional): '; read -r AGENT_SECRET
        printf 'Name (optional): '; read -r NAME
        WRITE_CONFIG=1
      fi
      install_or_update
      ;;
    2) uninstall_keep_data ;;
    3) purge_all ;;
    4) show_status ;;
    *) printf 'Cancelled.\n' ;;
  esac
}

if [ "${CFFINDER_INSTALLER_LIB_ONLY:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

if [ "$BRANCH" != "main" ] && [ "$BRANCH" != "debug" ]; then
  printf '%s\n' '--branch must be main or debug.' >&2
  exit 1
fi

if [ -z "$ACTION" ]; then
  if [ -t 0 ]; then
    ACTION="interactive"
  else
    ACTION="install"
  fi
fi

case "$ACTION" in
  install) install_or_update ;;
  uninstall) uninstall_keep_data ;;
  purge) purge_all ;;
  status) show_status ;;
  interactive) interactive_menu ;;
  *) usage; exit 1 ;;
esac
