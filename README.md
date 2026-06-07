# CFFinder Releases

`main` is the stable channel. `debug` is the debug channel.

For interactive menus, download the script first and run it locally. This keeps
stdin available for menu input.

## Swift Backend

Install or update, stable:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-swift-backend.sh | sudo bash -s -- --branch main --install
```

Install or update, debug:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/debug/install-swift-backend.sh | sudo bash -s -- --branch debug --install
```

Install with legacy data migration from `/download/CFFinderSwiftBackend`:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-swift-backend.sh | sudo bash -s -- --branch main --install --migrate-legacy
```

Show status:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-swift-backend.sh | sudo bash -s -- --branch main --status
```

Uninstall and keep data:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-swift-backend.sh | sudo bash -s -- --branch main --uninstall
```

Purge program and data:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-swift-backend.sh | sudo bash -s -- --branch main --purge
```

Interactive menu:

```bash
tmp="$(mktemp)" && curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-swift-backend.sh -o "$tmp" && sudo bash "$tmp" --branch main --interactive; rm -f "$tmp"
```

## Linux Agent

Install a new Linux Agent, stable:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-go.sh | sudo bash -s -- --branch main --install --hub-url 'https://your-backend.example.com:9899' --agents-token 'YOUR_AGENTS_TOKEN'
```

Install a new Linux Agent, debug:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/debug/install-agent-go.sh | sudo bash -s -- --branch debug --install --hub-url 'https://your-backend.example.com:9899' --agents-token 'YOUR_AGENTS_TOKEN'
```

Reinstall and reuse an existing Agent identity:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-go.sh | sudo bash -s -- --branch main --install --hub-url 'https://your-backend.example.com:9899' --agents-token 'YOUR_AGENTS_TOKEN' --agent-id 'EXISTING_AGENT_ID' --agent-secret 'EXISTING_AGENT_SECRET' --name 'Existing Agent Name'
```

Install or update without starting service:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-go.sh | sudo bash -s -- --branch main --install --hub-url 'https://your-backend.example.com:9899' --agents-token 'YOUR_AGENTS_TOKEN' --no-start
```

Show status:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-go.sh | sudo bash -s -- --branch main --status
```

Uninstall and keep config/data:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-go.sh | sudo bash -s -- --branch main --uninstall
```

Purge program, config and data:

```bash
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-go.sh | sudo bash -s -- --branch main --purge
```

Interactive menu:

```bash
tmp="$(mktemp)" && curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-agent-go.sh -o "$tmp" && sudo bash "$tmp" --branch main --interactive; rm -f "$tmp"
```

## OpenWrt OPD

Install or update, stable:

```sh
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/main/install-opd-openwrt.sh | sh -s -- --branch main --install
```

Install or update, debug:

```sh
curl -fsSL https://raw.githubusercontent.com/wxyjay/cffinder-releases/debug/install-opd-openwrt.sh | sh -s -- --branch debug --install
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
