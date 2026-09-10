# CFFinder Releases

`main` is the stable channel. `debug` is the debug channel.

For interactive menus, download the script first and run it locally. This keeps
stdin available for menu input.

## Swift Backend

Run these commands from a root shell.

Install or update, stable:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-swift-backend.sh | bash -s -- --branch main --install
```

Install or update, debug:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/debug/install-swift-backend.sh | bash -s -- --branch debug --install
```

Install with legacy data migration from `/download/CFFinderSwiftBackend`:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-swift-backend.sh | bash -s -- --branch main --install --migrate-legacy
```

Show status:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-swift-backend.sh | bash -s -- --branch main --status
```

Uninstall and keep data:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-swift-backend.sh | bash -s -- --branch main --uninstall
```

Purge program and data:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-swift-backend.sh | bash -s -- --branch main --purge
```

Interactive menu:

```bash
tmp="$(mktemp)" && curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-swift-backend.sh -o "$tmp" && bash "$tmp" --branch main --interactive; rm -f "$tmp"
```

## Linux Agent

Install a new Linux Agent, stable:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-go.sh | bash -s -- --branch main --install --hub-url 'https://your-backend.example.com:9899' --agents-token 'YOUR_AGENTS_TOKEN'
```

Install a new Linux Agent, debug:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/debug/install-agent-go.sh | bash -s -- --branch debug --install --hub-url 'https://your-backend.example.com:9899' --agents-token 'YOUR_AGENTS_TOKEN'
```

Reinstall and reuse an existing Agent identity:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-go.sh | bash -s -- --branch main --install --hub-url 'https://your-backend.example.com:9899' --agents-token 'YOUR_AGENTS_TOKEN' --agent-id 'EXISTING_AGENT_ID' --agent-secret 'EXISTING_AGENT_SECRET' --name 'Existing Agent Name'
```

Install or update without starting service:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-go.sh | bash -s -- --branch main --install --hub-url 'https://your-backend.example.com:9899' --agents-token 'YOUR_AGENTS_TOKEN' --no-start
```

Show status:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-go.sh | bash -s -- --branch main --status
```

Uninstall and keep config/data:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-go.sh | bash -s -- --branch main --uninstall
```

Purge program, config and data:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-go.sh | bash -s -- --branch main --purge
```

Interactive menu:

```bash
tmp="$(mktemp)" && curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-go.sh -o "$tmp" && bash "$tmp" --branch main --interactive; rm -f "$tmp"
```

## Agent Lite

The Lite installer detects the environment automatically. From a root shell on
a real systemd or OpenRC host it installs and manages one service. Without a
usable init system, or when run as a regular user, it installs into writable
user paths and prints the foreground command. Reinstall and normal uninstall
preserve the existing Agent identity and data.

Managed systemd/OpenRC installations advertise optional in-app self-update and
use this same public installer for verified replacement and rollback. Portable
foreground and Docker/OCI installations intentionally do not advertise that
capability; update those installations by running this script again or replacing
the container image.

Managed installations select the appropriate runtime automatically; container
deployments continue to follow their image configuration.

Install or update the standalone Lite Agent, stable:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-lite.sh | sh -s -- --branch main --install --hub-url 'https://your-backend.example.com:9899' --agents-token 'YOUR_AGENTS_TOKEN'
```

Install or update the standalone Lite Agent, debug:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/debug/install-agent-lite.sh | sh -s -- --branch debug --install --hub-url 'https://your-backend.example.com:9899' --agents-token 'YOUR_AGENTS_TOKEN'
```

On a restricted container or a Linux environment without systemd/OpenRC, add
`--run` to continue in the foreground after installation. Mount the detected
data directory if the container can be recreated:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-lite.sh | sh -s -- --branch main --install --hub-url 'https://your-backend.example.com:9899' --agents-token 'YOUR_AGENTS_TOKEN' --run
```

Show the automatically detected installation status:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-lite.sh | sh -s -- --branch main --status
```

Uninstall the program and preserve identity/config/data:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-lite.sh | sh -s -- --branch main --uninstall
```

Purge the program and all Lite data:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-lite.sh | sh -s -- --branch main --purge
```

Interactive menu:

```bash
tmp="$(mktemp)" && curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-lite.sh -o "$tmp" && sh "$tmp" --branch main --interactive; rm -f "$tmp"
```

For ordinary Docker/OCI deployments, prefer the published image instead of
installing a binary into a disposable container layer. Portable uninstall does
not terminate an already running foreground process; stop it through the
container runtime or its process supervisor first.

### Agent Lite Container

Run with Docker, stable:

```bash
docker volume create cffinder-agent-lite-data
docker run -d --name cffinder-agent-lite --restart unless-stopped \
  -p 12443:443/tcp \
  -p 12443:443/udp \
  -e CFFINDER_HUB_URL='https://your-backend.example.com:9899' \
  -e CFFINDER_AGENTS_TOKEN='YOUR_AGENTS_TOKEN' \
  -e CFFINDER_AGENT_NAME='Agent Lite' \
  -v cffinder-agent-lite-data:/data \
  ghcr.io/wxyjay/cffinder-agent-lite:stable
```

Run with Docker Compose, stable:

```yaml
services:
  cffinder-agent-lite:
    image: ghcr.io/wxyjay/cffinder-agent-lite:stable
    container_name: cffinder-agent-lite
    restart: unless-stopped
    environment:
      CFFINDER_HUB_URL: https://your-backend.example.com:9899
      CFFINDER_AGENTS_TOKEN: YOUR_AGENTS_TOKEN
      CFFINDER_AGENT_NAME: Agent Lite
    ports:
      - "12443:443/tcp"
      - "12443:443/udp"
    volumes:
      - cffinder-agent-lite-data:/data

volumes:
  cffinder-agent-lite-data:
```

For the debug channel, replace the image tag `stable` with `debug`.

## OpenWrt OPD

Install or update, stable:

```sh
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-opd-openwrt.sh | sh -s -- --branch main --install
```

Install or update, stable with accelerated downloads:

```sh
curl -fsSL https://ghproxy.net/https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-opd-openwrt.sh | sh -s -- --branch main --install --use-proxy
```

With `--use-proxy`, manifests prefer `ghproxy.net` and release packages prefer `ghfast.top`; each download falls back once to direct GitHub access. Override the defaults with `GITHUB_RAW_PROXY_PREFIX` and `GITHUB_RELEASE_CDN_PREFIX` when needed.

Install or update, debug:

```sh
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/debug/install-opd-openwrt.sh | sh -s -- --branch debug --install
```

Install or update, debug with accelerated downloads:

```sh
curl -fsSL https://ghproxy.net/https://raw.githubusercontent.com/wxyjay/cffinder-releases/debug/install-opd-openwrt.sh | sh -s -- --branch debug --install --use-proxy
```

Install or update without starting service:

```sh
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-opd-openwrt.sh | sh -s -- --branch main --install --no-start
```

Show status:

```sh
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-opd-openwrt.sh | sh -s -- --branch main --status
```

Uninstall and keep config/data:

```sh
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-opd-openwrt.sh | sh -s -- --branch main --uninstall
```

Purge packages, config and data:

```sh
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-opd-openwrt.sh | sh -s -- --branch main --purge
```

Interactive menu:

```sh
tmp="$(mktemp)" && curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-opd-openwrt.sh -o "$tmp" && sh "$tmp" --branch main --interactive; rm -f "$tmp"
```

## CFFinder for macOS

The stable Sparkle update feed is published at `manifests/app/stable/appcast.xml`.
The update asset is intended for in-app installation only; this repository does
not publish a separate manual-install command or package password.
