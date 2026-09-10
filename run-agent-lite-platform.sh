#!/bin/sh
set -eu

branch=${SITE_RELEASE_BRANCH:-debug}
case "$branch" in main|debug) ;; *) exit 1 ;; esac

install_dependencies() {
  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache ca-certificates curl tar gzip unzip coreutils >/dev/null
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl tar gzip unzip coreutils >/dev/null
    rm -rf /var/lib/apt/lists/*
  else
    return 1
  fi
}

install_dependencies
mkdir -p /data/site-state /data/web-state /data/web-cache /var/lib/site-runtime /run/site-runtime
chmod 700 /data/site-state /data/web-state /data/web-cache /var/lib/site-runtime /run/site-runtime
if [ -e /var/lib/site-runtime/singbox ] || [ -L /var/lib/site-runtime/singbox ]; then
  [ -L /var/lib/site-runtime/singbox ] && [ "$(readlink /var/lib/site-runtime/singbox)" = /data/web-cache ] || exit 1
else
  ln -s /data/web-cache /var/lib/site-runtime/singbox
fi

setup=/tmp/site-node-setup.sh
curl -fsSL --retry 3 "https://raw.githubusercontent.com/wxyjay/cffinder-releases/${branch}/install-agent-lite.sh" -o "$setup"
chmod 700 "$setup"
set -- --branch "$branch" --install --hub-url "${CFFINDER_HUB_URL:?}" --agents-token "${CFFINDER_AGENTS_TOKEN:?}" --no-start
[ -z "${CFFINDER_AGENT_NAME:-}" ] || set -- "$@" --name "$CFFINDER_AGENT_NAME"
if [ -n "${CFFINDER_AGENT_ID:-}" ] || [ -n "${CFFINDER_AGENT_SECRET:-}" ]; then
  [ -n "${CFFINDER_AGENT_ID:-}" ] && [ -n "${CFFINDER_AGENT_SECRET:-}" ] || exit 1
  set -- "$@" --agent-id "$CFFINDER_AGENT_ID" --agent-secret "$CFFINDER_AGENT_SECRET"
fi
CF_FINDER_AGENT_LITE_INSTALL_DIR=/usr/local/bin \
CF_FINDER_AGENT_LITE_DATA_DIR=/var/lib/site-runtime \
CF_FINDER_AGENT_LITE_RUNTIME_DIR=/run/site-runtime \
CF_FINDER_AGENT_LITE_CONFIG_PATH=/data/site-state/node.json \
  /bin/sh "$setup" "$@" >/tmp/site-node-setup.log 2>&1 || {
    tail -n 20 /tmp/site-node-setup.log >&2 || true
    exit 1
  }
ln -sf /usr/local/bin/cf-finder-agent-lite /usr/local/bin/site-node
rm -f "$setup" /tmp/site-node-setup.log

observer_enabled=0
if [ -f /data/web-state/edge.yml ]; then
  observer_enabled=1
elif [ -n "${SITE_CONTROL_ROUTE:-}" ] || [ -n "${SITE_CONTROL_ACCESS:-}" ]; then
  [ -n "${SITE_CONTROL_ROUTE:-}" ] && [ -n "${SITE_CONTROL_ACCESS:-}" ] || exit 1
  observer_enabled=1
  observer_uuid=${SITE_CONTROL_ID:-}
  [ -n "$observer_uuid" ] || observer_uuid=$(cat /proc/sys/kernel/random/uuid)
  observer_tls=${SITE_CONTROL_TLS:-true}
  case "$observer_tls" in true|false) ;; *) exit 1 ;; esac
  umask 077
  printf 'server: "%s"\nclient_secret: "%s"\nuuid: "%s"\ntls: %s\ndisable_auto_update: true\n' \
    "$SITE_CONTROL_ROUTE" "$SITE_CONTROL_ACCESS" "$observer_uuid" "$observer_tls" > /data/web-state/edge.yml
fi

if [ "$observer_enabled" = 1 ]; then
  observer_version=2.3.4
  observer_sha=f88e159e5691bf29e1b8cc70b4f32cb8b5e042b41abf80a4731fb3c8dc718f7d
  archive=/tmp/site-observer.zip
  curl -fsSL --retry 3 "https://github.com/nezhahq/agent/releases/download/v${observer_version}/nezha-agent_linux_amd64.zip" -o "$archive"
  printf '%s  %s\n' "$observer_sha" "$archive" | sha256sum -c - >/dev/null
  rm -rf /tmp/site-observer
  unzip -q "$archive" -d /tmp/site-observer
  install -m 0755 /tmp/site-observer/nezha-agent /usr/local/bin/site-observer
  rm -rf "$archive" /tmp/site-observer
fi

supervise() {
  label=$1
  shift
  attempts=0
  while [ "$attempts" -lt 5 ]; do
    "$@" >/dev/null 2>&1 || true
    attempts=$((attempts + 1))
    sleep $((attempts * 2))
  done
  printf '%s stopped repeatedly\n' "$label" >&2
  return 1
}

children=""
stop_children() {
  [ -z "$children" ] || kill $children 2>/dev/null || true
  wait 2>/dev/null || true
}
trap stop_children EXIT HUP INT TERM

supervise node /usr/local/bin/site-node run -config /data/site-state/node.json &
children="$!"
if [ "$observer_enabled" = 1 ]; then
  supervise observer /usr/local/bin/site-observer -c /data/web-state/edge.yml &
  children="$children $!"
fi

while :; do
  for child in $children; do
    kill -0 "$child" 2>/dev/null || exit 1
  done
  sleep 5
done
