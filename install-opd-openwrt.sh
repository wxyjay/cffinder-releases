#!/bin/sh
set -eu

SERVICE_NAME="cf-finder-opd"
RELEASE_REPO="${RELEASE_REPO:-wxyjay/cffinder-releases}"
BRANCH="main"
ACTION=""
NO_START=0
USE_PROXY=0
GITHUB_RAW_PROXY_PREFIX="${GITHUB_RAW_PROXY_PREFIX:-https://ghproxy.net/}"
GITHUB_RELEASE_CDN_PREFIX="${GITHUB_RELEASE_CDN_PREFIX:-https://ghfast.top/}"
CURL_BIN="${CURL_BIN:-curl}"

selfupdate_status() {
  status_file="${CFFINDER_SELFUPDATE_STATUS_FILE:-}"
  [ -n "$status_file" ] || return 0
  phase="$1"
  progress="$2"
  message="$3"
  running="$4"
  error_message="${5:-}"
  now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  operation="${CFFINDER_SELFUPDATE_OPERATION:-updating}"
  current_version="${CFFINDER_SELFUPDATE_CURRENT_VERSION:-unknown}"
  current_release="${CFFINDER_SELFUPDATE_CURRENT_RELEASE:-1}"
  current_channel="${CFFINDER_SELFUPDATE_CURRENT_CHANNEL:-stable}"
  target_version="${CFFINDER_SELFUPDATE_TARGET_VERSION:-$current_version}"
  target_release="${CFFINDER_SELFUPDATE_TARGET_RELEASE:-$current_release}"
  target_channel="${CFFINDER_SELFUPDATE_TARGET_CHANNEL:-$current_channel}"
  update_available=true
  [ "$phase" = "completed" ] && update_available=false
  escaped_message="$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  escaped_error="$(printf '%s' "$error_message" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  mkdir -p "$(dirname "$status_file")"
  tmp_status="${status_file}.tmp.$$"
  cat > "$tmp_status" <<EOF
{
  "version": {
    "currentVersion": "$current_version",
    "currentPackageRelease": "$current_release",
    "currentChannel": "$current_channel",
    "latestVersion": "$target_version",
    "latestPackageRelease": "$target_release",
    "latestChannel": "$target_channel",
    "updateAvailable": $update_available,
    "lastCheckedAt": "$now"
  },
  "operation": "$operation",
  "phase": "$phase",
  "progress": $progress,
  "message": "$escaped_message",
  "isRunning": $running,
  "error": "$escaped_error",
  "targetVersion": "$target_version",
  "targetPackageRelease": "$target_release",
  "targetChannel": "$target_channel",
  "updatedAt": "$now"
}
EOF
  chmod 600 "$tmp_status"
  mv -f "$tmp_status" "$status_file"
}

usage() {
  cat <<'EOF'
Usage:
  install-opd-openwrt.sh [--branch main|debug] [--install|--uninstall|--purge|--status|--interactive] [--no-start] [--use-proxy]

Actions:
  --install      Install or update OPD daemon and LuCI packages.
  --uninstall    Remove packages, preserving config/data.
  --purge        Remove packages plus config/data.
  --status       Show service status.
  --interactive  Show menu.
  --use-proxy    Prefer proxy/CDN for manifests and release assets, then fall back to GitHub.
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
    --use-proxy|--proxy) USE_PROXY=1; shift ;;
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

manifest_direct_url() {
  channel="$1"
  printf 'https://raw.githubusercontent.com/%s/%s/manifests/opd/%s.json' "$RELEASE_REPO" "$BRANCH" "$channel"
}

raw_content_url() {
  raw_url="$1"
  if [ "$USE_PROXY" -eq 1 ] && [ -n "$GITHUB_RAW_PROXY_PREFIX" ]; then
    case "$GITHUB_RAW_PROXY_PREFIX" in
      */) printf '%s%s' "$GITHUB_RAW_PROXY_PREFIX" "$raw_url" ;;
      *) printf '%s/%s' "$GITHUB_RAW_PROXY_PREFIX" "$raw_url" ;;
    esac
  else
    printf '%s' "$raw_url"
  fi
}

manifest_url() {
  raw_content_url "$(manifest_direct_url "$1")"
}

release_asset_url() {
  raw_url="$1"
  if [ "$USE_PROXY" -eq 1 ]; then
    case "$GITHUB_RELEASE_CDN_PREFIX" in
      */) printf '%s%s' "$GITHUB_RELEASE_CDN_PREFIX" "$raw_url" ;;
      *) printf '%s/%s' "$GITHUB_RELEASE_CDN_PREFIX" "$raw_url" ;;
    esac
  else
    printf '%s' "$raw_url"
  fi
}

download_with_fallback() {
  preferred_url="$1"
  direct_url="$2"
  output_path="$3"
  if [ "$preferred_url" != "$direct_url" ]; then
    if "$CURL_BIN" -fsSL "$preferred_url" -o "$output_path"; then
      DOWNLOAD_USED_URL="$preferred_url"
      return 0
    fi
    echo "Proxy download failed; falling back to GitHub." >&2
  fi
  "$CURL_BIN" -fsSL "$direct_url" -o "$output_path"
  DOWNLOAD_USED_URL="$direct_url"
}

manifest_has_tag() {
  manifest="$1"
  sed -n 's/.*"tag"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | grep -q .
}

download_manifest_with_fallback() {
  channel="$1"
  output_path="$2"
  direct_url="$(manifest_direct_url "$channel")"
  preferred_url="$(manifest_url "$channel")"
  if [ "$preferred_url" != "$direct_url" ]; then
    if "$CURL_BIN" -fsSL "$preferred_url" -o "$output_path"; then
      if manifest_has_tag "$output_path"; then
        return 0
      fi
      echo "Proxy manifest validation failed; falling back to GitHub." >&2
    else
      echo "Proxy manifest download failed; falling back to GitHub." >&2
    fi
  fi
  "$CURL_BIN" -fsSL "$direct_url" -o "$output_path"
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
  direct_url="https://github.com/${RELEASE_REPO}/releases/download/${tag}/${asset}"
  url="$(release_asset_url "$direct_url")"
  download_with_fallback "$url" "$direct_url" "${out_dir}/${asset}"
  if [ -n "$expected_sha" ]; then
    actual_sha="$(sha256_file "${out_dir}/${asset}")"
    if [ "$actual_sha" != "$expected_sha" ] && [ "$DOWNLOAD_USED_URL" != "$direct_url" ]; then
      echo "Proxy package checksum mismatch; falling back to GitHub." >&2
      "$CURL_BIN" -fsSL "$direct_url" -o "${out_dir}/${asset}"
      DOWNLOAD_USED_URL="$direct_url"
      actual_sha="$(sha256_file "${out_dir}/${asset}")"
    fi
    if [ "$actual_sha" != "$expected_sha" ]; then
      echo "SHA256 mismatch for ${asset}: got ${actual_sha}, expected ${expected_sha}" >&2
      exit 1
    fi
  fi
  printf '%s\n' "${out_dir}/${asset}"
}

start_service_after_install() {
  if [ ! -x "/etc/init.d/$SERVICE_NAME" ]; then
    echo "OPD init script not found; package may not have been installed." >&2
    return 0
  fi
  /etc/init.d/$SERVICE_NAME stop >/dev/null 2>&1 || true
  /etc/init.d/$SERVICE_NAME start || true
}

show_status() {
  if [ ! -x "/etc/init.d/$SERVICE_NAME" ]; then
    echo "not installed"
    return 0
  fi
  if status_output="$(/etc/init.d/$SERVICE_NAME status 2>&1)"; then
    printf '%s\n' "$status_output"
    return 0
  fi
  if pidof "$SERVICE_NAME" >/dev/null 2>&1; then
    echo "running"
  else
    echo "not running"
  fi
}

install_or_update() {
  need_cmd "$CURL_BIN"
  selfupdate_status "checking_latest" 0.12 "checking update manifest" true
  format="$(detect_pkg_format)"
  target="$(detect_target)"
  channel="stable"
  [ "$BRANCH" = "debug" ] && channel="debug"
  tmp_dir="$(mktemp -d)"
  cleanup_install() {
    rc="$?"
    trap - EXIT
    if [ "$rc" -ne 0 ]; then
      selfupdate_status "failed" 1 "package installation failed" false "package installation failed"
    fi
    rm -rf "$tmp_dir"
    exit "$rc"
  }
  trap cleanup_install EXIT
  manifest="${tmp_dir}/manifest.json"

  echo "Installing CFFinder OPD (${BRANCH}, ${format}, ${target})"
  download_manifest_with_fallback "$channel" "$manifest"
  tag="$(sed -n 's/.*"tag"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n 1)"
  [ -n "$tag" ] || { echo "Invalid OPD manifest." >&2; exit 1; }
  selfupdate_status "downloading" 0.15 "downloading packages" true

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
  selfupdate_status "verifying" 0.55 "package checksums verified" true

  selfupdate_status "installing" 0.75 "installing packages" true
  /etc/init.d/$SERVICE_NAME stop >/dev/null 2>&1 || true
  set -- "$daemon_pkg"
  [ -n "$luci_pkg" ] && set -- "$@" "$luci_pkg"
  [ -n "$i18n_pkg" ] && set -- "$@" "$i18n_pkg"
  if [ "$format" = "apk" ]; then
    apk add --allow-untrusted --force-overwrite --upgrade "$@"
  else
    opkg install --force-reinstall "$@"
  fi
  /etc/init.d/rpcd restart >/dev/null 2>&1 || true
  /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
  /etc/init.d/$SERVICE_NAME enable >/dev/null 2>&1 || true
  selfupdate_status "waiting_restart" 0.95 "waiting for service restart" true
  if [ "$NO_START" -eq 0 ]; then
    start_service_after_install
  fi
  selfupdate_status "completed" 1 "updated and restarted" false
  show_status
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

if [ "${CFFINDER_INSTALLER_LIB_ONLY:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

case "$ACTION" in
  install) install_or_update ;;
  uninstall) uninstall_keep_data ;;
  purge) purge_all ;;
  status) show_status ;;
  interactive) interactive_menu ;;
  *) usage; exit 1 ;;
esac
