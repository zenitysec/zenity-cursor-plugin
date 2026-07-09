<p align="center">
  <img src="zenity-inventory/logo.svg" alt="Zenity" width="180">
</p>

<h1 align="center">Zenity plugins for Cursor</h1>

<p align="center">
  A Cursor plugin marketplace for Zenity's AI security &amp; governance plugins.
  <br>
  <a href="https://zenity.io">zenity.io</a>
  ·
  <a href="zenity-inventory/">zenity-inventory</a>
  ·
  <a href="https://github.com/zenitysec/zenity-cursor-plugin/issues">Issues</a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
</p>

---

Zenity gives security teams visibility and governance over the AI agents and
tools running across their organization. This repo is the open-source home for
our **Cursor** plugins — published here in full so you can read exactly what
runs on your developers' machines and what leaves them.

## Plugins

### [zenity-inventory](zenity-inventory/)

Reports this device's Cursor **MCP servers** to Zenity AI Edge on session start,
so security teams get an accurate, continuously-updated inventory of which MCP
tools are configured across the fleet. Minimal and **self-contained** — our own
scan, no external framework.

## What leaves your device — and what never does

This is a security tool, so transparency about data flow comes first.

**Sent** — a single Cursor agent record listing your configured MCP servers.
Each entry carries only structural metadata:

```json
{ "id": "<stable hash>", "name": "slack", "scope": "plugin",
  "config_path": "/Users/…/mcp.json", "configuration": { "url": "https://mcp.slack.com/mcp" } }
```

**Never sent** — MCP secrets. `env`, `headers`, and `auth` are dropped *at the
source*, before anything is serialized or transmitted. They never leave the
device.

**Credentials** — your enrollment key and the short-lived device token live in
the macOS Keychain, never in plaintext files.

**Fail-open** — the scan runs as a `sessionStart` hook and always exits cleanly;
it never blocks or interrupts your Cursor session.

See **[zenity-inventory/README.md](zenity-inventory/README.md)** for the complete
picture — exactly what it collects, how identity is derived, configuration, and
current limitations.

## Install

Add this repo as a marketplace in Cursor and install **zenity-inventory**. On the
first session you'll get two native dialogs — tenant (`EU`/`US`) and your
enrollment key — no terminal needed.

Headless or over SSH? Enroll from a terminal instead:

```bash
zenity-inventory/bin/zenityctl enroll
```

## Repository layout

```
.cursor-plugin/marketplace.json   # marketplace manifest (lists the plugins)
zenity-inventory/                 # the zenity-inventory plugin — see its README
LICENSE                           # MIT
```

Manifests follow the [`cursor/plugins`](https://github.com/cursor/plugins) spec.
Because the plugin reports device inventory off-device, it's best distributed via
a **team / private marketplace** with central governance. Submit for review at
[cursor.com/marketplace/publish](https://cursor.com/marketplace/publish).

> **Testing note.** Loading a plugin from a local directory is unreliable on
> Cursor ≥ 3.5 (you'll see `userLocal=false` in the plugin log). Install from a
> marketplace source instead — that's the path customers use, and it loads
> correctly. To iterate on the hook alone, register it directly in
> `~/.cursor/hooks.json`.

## Support

- **Bugs & feature requests** — [open an issue](https://github.com/zenitysec/zenity-cursor-plugin/issues).
- **Customers** — reach out through your usual Zenity support channel or
  [plugins@zenity.io](mailto:plugins@zenity.io).

## License

[MIT](LICENSE) © Zenity
