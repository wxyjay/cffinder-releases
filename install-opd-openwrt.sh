#!/bin/sh
set -eu

SERVICE_NAME="cf-finder-opd"
RELEASE_REPO="${RELEASE_REPO:-wxyjay/cffinder-releases}"
BRANCH="main"
ACTION=""
NO_START=0

usage() {
  cat <<'EOF'
Usage:
  install-opd-openwrt.sh [--branch main|debug] [--install|--uninstall|--purge|--status|--interactive] [--no-start]

Actions:
  --install      Install or update OPD daemon and LuCI packages.
  --uninstall    Remove packages, preserving config/data.
  --purge        Remove packages plus config/data.
  --status       Show service status.
  --interactive  Show menu.
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
    --no-start) NO_START=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [ "$BRANCH" != "main" ] && [ "$BRANCH" != "debug" ]; then
  echo "--branch must be main or debug." >&2
  exit 1
fi

if [ -z "$ACTION" ]; then
  if [ -t 0 ]; then
    ACTION="interactive"
  else
    ACTION="install"
  fi
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }
}

detect_pkg_format() {
  if command -v apk >/dev/null 2>&1; then
    echo "apk"
  elif command -v opkg >/dev/null 2>&1; then
    echo "ipk"
  else
    echo "No supported package manager found: expected opkg or apk." >&2
    exit 1
  fi
}

detect_target() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *) echo "Unsupported OpenWrt architecture: $(uname -m)" >&2; exit 1 ;;
  esac
}

manifest_url() {
  channel="$1"
  printf 'https://raw.githubusercontent.com/%s/%s/manifests/opd/%s.json' "$RELEASE_REPO" "$BRANCH" "$channel"
}

extract_asset_names() {
  sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1"
}

extract_asset_sha() {
  manifest="$1"
  asset="$2"
  awk -v target="$asset" '
    match($0, /"name"[[:space:]]*:[[:space:]]*"([^"]+)"/, m) { current=m[1] }
    match($0, /"sha256"[[:space:]]*:[[:space:]]*"([^"]+)"/, m) && current == target { print m[1]; exit }
  ' "$manifest"
}

sha256_file() {
  file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return 0
  fi
  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file" | awk '{print $NF}'
    return 0
  fi
  echo "Missing sha256sum or openssl for package verification." >&2
  exit 1
}

select_asset() {
  manifest="$1"
  format="$2"
  target="$3"
  kind="$4"
  names="$(extract_asset_names "$manifest" | grep "\\.${format}$" || true)"
  case "$kind" in
    daemon)
      printf '%s\n' "$names" \
        | grep '^cf-finder-opd' \
        | grep -v '^luci-' \
        | grep -E "(_|-)$target\\.${format}$" \
        | head -n 1
      ;;
    luci)
      printf '%s\n' "$names" | grep '^luci-app-cf-finder-opd' | head -n 1
      ;;
    i18n)
      printf '%s\n' "$names" | grep '^luci-i18n-cf-finder-opd-zh-cn' | head -n 1
      ;;
  esac
}

download_one() {
  tag="$1"
  asset="$2"
  out_dir="$3"
  expected_sha="${4:-}"
  [ -n "$asset" ] || return 0
  url="https://github.com/${RELEASE_REPO}/releases/download/${tag}/${asset}"
  curl -fL "$url" -o "${out_dir}/${asset}"
  if [ -n "$expected_sha" ]; then
    actual_sha="$(sha256_file "${out_dir}/${asset}")"
    if [ "$actual_sha" != "$expected_sha" ]; then
      echo "SHA256 mismatch for ${asset}: got ${actual_sha}, expected ${expected_sha}" >&2
      exit 1
    fi
  fi
  printf '%s\n' "${out_dir}/${asset}"
}

install_or_update() {
  need_cmd curl
  format="$(detect_pkg_format)"
  target="$(detect_target)"
  channel="stable"
  [ "$BRANCH" = "debug" ] && channel="debug"
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  manifest="${tmp_dir}/manifest.json"

  echo "Installing CFFinder OPD (${BRANCH}, ${format}, ${target})"
  curl -fsSL "$(manifest_url "$channel")" -o "$manifest"
  tag="$(sed -n 's/.*"tag"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n 1)"
  [ -n "$tag" ] || { echo "Invalid OPD manifest." >&2; exit 1; }

  daemon_asset="$(select_asset "$manifest" "$format" "$target" daemon || true)"
  luci_asset="$(select_asset "$manifest" "$format" "$target" luci || true)"
  i18n_asset="$(select_asset "$manifest" "$format" "$target" i18n || true)"
  [ -n "$daemon_asset" ] || { echo "No OPD daemon package found for ${format}/${target}." >&2; exit 1; }

  daemon_sha="$(extract_asset_sha "$manifest" "$daemon_asset" || true)"
  luci_sha="$(extract_asset_sha "$manifest" "$luci_asset" || true)"
  i18n_sha="$(extract_asset_sha "$manifest" "$i18n_asset" || true)"

  daemon_pkg="$(download_one "$tag" "$daemon_asset" "$tmp_dir" "$daemon_sha")"
  luci_pkg="$(download_one "$tag" "$luci_asset" "$tmp_dir" "$luci_sha" || true)"
  i18n_pkg="$(download_one "$tag" "$i18n_asset" "$tmp_dir" "$i18n_sha" || true)"

  /etc/init.d/$SERVICE_NAME stop >/dev/null 2>&1 || true
  set -- "$daemon_pkg"
  [ -n "$luci_pkg" ] && set -- "$@" "$luci_pkg"
  [ -n "$i18n_pkg" ] && set -- "$@" "$i18n_pkg"
  if [ "$format" = "apk" ]; then
    apk update || true
    apk add --allow-untrusted "$@"
  else
    opkg update || true
    opkg install "$@"
  fi
  /etc/init.d/rpcd restart >/dev/null 2>&1 || true
  /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
  /etc/init.d/$SERVICE_NAME enable >/dev/null 2>&1 || true
  if [ "$NO_START" -eq 0 ]; then
    /etc/init.d/$SERVICE_NAME restart || /etc/init.d/$SERVICE_NAME start || true
  fi
  /etc/init.d/$SERVICE_NAME status || true
}

remove_packages() {
  format="$(detect_pkg_format)"
  /etc/init.d/$SERVICE_NAME stop >/dev/null 2>&1 || true
  /etc/init.d/$SERVICE_NAME disable >/dev/null 2>&1 || true
  if [ "$format" = "apk" ]; then
    apk del luci-i18n-cf-finder-opd-zh-cn luci-app-cf-finder-opd cf-finder-opd >/dev/null 2>&1 || true
  else
    opkg remove luci-i18n-cf-finder-opd-zh-cn luci-app-cf-finder-opd cf-finder-opd >/dev/null 2>&1 || true
  fi
  /etc/init.d/rpcd restart >/dev/null 2>&1 || true
  /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
}

uninstall_keep_data() {
  remove_packages
  echo "Removed OPD packages. Config/data preserved."
}

purge_all() {
  if [ -x /usr/share/cf-finder-opd/uninstall-cleanup.sh ]; then
    CF_FINDER_PURGE=1 /usr/share/cf-finder-opd/uninstall-cleanup.sh || true
  fi
  remove_packages
  rm -f /etc/config/cf-finder-opd
  rm -rf /etc/cf-finder-opd /var/run/cf-finder-opd
  echo "Removed OPD packages, config and data."
}

show_status() {
  /etc/init.d/$SERVICE_NAME status || true
}

interactive_menu() {
  echo "CFFinder OPD installer"
  echo "1) Install or update"
  echo "2) Uninstall (keep config/data)"
  echo "3) Purge (remove config/data)"
  echo "4) Status"
  printf 'Choose: '
  read choice
  case "$choice" in
    1)
      printf 'Branch main/debug (Enter keeps %s): ' "$BRANCH"
      read input_branch
      [ -n "$input_branch" ] && BRANCH="$input_branch"
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
