#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="cffinder-swift-backend"
DISPLAY_NAME="CFFinder Swift Backend"
RELEASE_REPO="${RELEASE_REPO:-wxyjay/cffinder-releases}"
INSTALL_DIR="${INSTALL_DIR:-/opt/cffinder-swift-backend}"
DATA_DIR="${DATA_DIR:-/var/lib/cffinder-swift-backend}"
UNIT_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
BRANCH="main"
ACTION=""

usage() {
  cat <<'EOF'
Usage:
  install-swift-backend.sh [--branch main|debug] [--install|--uninstall|--purge|--status|--interactive]

Actions:
  --install     Install or update service, preserving data.
  --uninstall   Stop service and remove program files, preserving data.
  --purge       Stop service and remove program files plus data.
  --status      Show systemd service status.
  --interactive Show menu.

Environment:
  RELEASE_REPO  Public release repo, default wxyjay/cffinder-releases.
  INSTALL_DIR   Program directory, default /opt/cffinder-swift-backend.
  DATA_DIR      Runtime data directory, default /var/lib/cffinder-swift-backend.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)
      BRANCH="${2:-}"
      shift 2
      ;;
    --install)
      ACTION="install"
      shift
      ;;
    --uninstall)
      ACTION="uninstall"
      shift
      ;;
    --purge)
      ACTION="purge"
      shift
      ;;
    --status)
      ACTION="status"
      shift
      ;;
    --interactive)
      ACTION="interactive"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$BRANCH" != "main" && "$BRANCH" != "debug" ]]; then
  echo "--branch must be main or debug." >&2
  exit 1
fi

require_root() {
  if [[ "$(id -u)" != "0" ]]; then
    echo "Please run as root, for example: curl -fsSL <script-url> | sudo bash -s -- --install" >&2
    exit 1
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
  esac
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }
}

manifest_url() {
  local channel="$1"
  printf 'https://raw.githubusercontent.com/%s/%s/manifests/swift-backend/%s.json' "$RELEASE_REPO" "$BRANCH" "$channel"
}

download_asset() {
  local arch="$1"
  local channel="stable"
  [[ "$BRANCH" == "debug" ]] && channel="debug"
  local tmp_dir="$2"
  local manifest="${tmp_dir}/manifest.json"
  local tag
  local asset

  curl -fsSL "$(manifest_url "$channel")" -o "$manifest"
  tag="$(sed -n 's/.*"tag"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n 1)"
  asset="$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*linux-'"${arch}"'\.tar\.gz\)".*/\1/p' "$manifest" | head -n 1)"
  if [[ -z "$tag" || -z "$asset" ]]; then
    echo "No swift-backend asset found for arch=${arch} in ${channel} manifest." >&2
    exit 1
  fi
  local url="https://github.com/${RELEASE_REPO}/releases/download/${tag}/${asset}"
  curl -fL "$url" -o "${tmp_dir}/${asset}"
  printf '%s\n' "${tmp_dir}/${asset}"
}

write_unit() {
  cat > "$UNIT_FILE" <<EOF
[Unit]
Description=${DISPLAY_NAME}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${DATA_DIR}
Environment=CFFINDER_BASE_DIR=${DATA_DIR}
ExecStart=${INSTALL_DIR}/CFFinderSwiftBackend
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

install_or_update() {
  require_root
  need_cmd curl
  need_cmd tar
  need_cmd systemctl

  local arch
  arch="$(detect_arch)"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  echo "Installing ${DISPLAY_NAME} (${BRANCH}, ${arch})"
  local archive
  archive="$(download_asset "$arch" "$tmp_dir")"

  mkdir -p "$INSTALL_DIR" "$DATA_DIR"
  if [[ -x "${INSTALL_DIR}/CFFinderSwiftBackend" ]]; then
    cp -f "${INSTALL_DIR}/CFFinderSwiftBackend" "${INSTALL_DIR}/CFFinderSwiftBackend.bak"
  fi
  tar -xzf "$archive" -C "$INSTALL_DIR"
  chmod +x "${INSTALL_DIR}/CFFinderSwiftBackend"
  if [[ ! -f "${DATA_DIR}/config.example.json" && -f "${INSTALL_DIR}/config.example.json" ]]; then
    cp -f "${INSTALL_DIR}/config.example.json" "${DATA_DIR}/config.example.json"
  fi
  write_unit
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"
  systemctl --no-pager status "$SERVICE_NAME" || true
}

uninstall_keep_data() {
  require_root
  need_cmd systemctl
  systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
  systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
  rm -f "$UNIT_FILE"
  systemctl daemon-reload
  rm -rf "$INSTALL_DIR"
  echo "Removed program files. Data preserved at ${DATA_DIR}."
}

purge_all() {
  uninstall_keep_data
  rm -rf "$DATA_DIR"
  echo "Removed data directory: ${DATA_DIR}"
}

show_status() {
  need_cmd systemctl
  systemctl --no-pager status "$SERVICE_NAME" || true
}

interactive_menu() {
  echo "${DISPLAY_NAME} installer"
  echo "1) Install or update"
  echo "2) Uninstall (keep data)"
  echo "3) Purge (remove data)"
  echo "4) Status"
  read -r -p "Choose: " choice
  case "$choice" in
    1)
      read -r -p "Branch main/debug (Enter keeps ${BRANCH}): " input_branch
      BRANCH="${input_branch:-$BRANCH}"
      install_or_update
      ;;
    2) uninstall_keep_data ;;
    3) purge_all ;;
    4) show_status ;;
    *) echo "Cancelled." ;;
  esac
}

if [[ -z "$ACTION" ]]; then
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
