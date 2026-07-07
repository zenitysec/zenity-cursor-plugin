# Zenity Inventory — Cursor MCP scanner

> A tiny, self-contained Cursor plugin that reports this device's **MCP servers**
> to Zenity AI Edge on each session start. Minimal by design — it scans MCP
> configs, scrubs secrets, and POSTs. Nothing else. macOS.

---

## Quick start

**GUI (zero terminal):** install the plugin and start a Cursor chat. On first
run you'll get two native dialogs — pick your **tenant** (`EU`/`US`) and paste
your **enrollment key**. Done; every later session reports automatically.

**Terminal (headless / CI):**
```bash
zenity-inventory/bin/zenityctl enroll      # tenant + key (hidden) + one-time login-password to pin silent reads
zenity-inventory/bin/zenityctl status      # tenant, endpoints, whether key/token exist (no secrets)
zenity-inventory/bin/zenityctl uninstall   # remove key + token + config
```

## How it works

```
Cursor sessionStart
        │
        ▼
hooks/zenity-inventory.sh ──► no key? → zenityctl enroll-gui (dialog)   ──► Keychain
        │ (skips background agents & remote workspaces; always exits 0)
        ▼
lib/scan.sh ── scan MCP configs ──► build v1.0.0 envelope ──► enroll (key→token) ──► POST
   (global + project + plugin mcp.json)        (device + Cursor agent + mcp_servers only)
```

| File | Role |
|---|---|
| `hooks/zenity-inventory.sh` | `sessionStart` hook. First-run onboarding, then scan + POST. Fail-open. |
| `lib/scan.sh` | The scan: read MCP configs, build the envelope, enroll, POST. |
| `lib/common.sh` | Shared Keychain / config / tenant / URL / JSON helpers. |
| `bin/zenityctl` | Onboarding (`enroll` / `enroll-gui`) + `uninstall` / `status`. |

Two-step bearer auth: the enrollment key is exchanged for a short-lived **device
token** at the manager endpoint (cached in the Keychain); inventory is POSTed
with `Authorization: Bearer <token>`.

## What it collects

A single Cursor agent record carrying **only `mcp_servers`** — each entry:

```json
{ "id": "<stable hash>", "name": "slack", "scope": "plugin",
  "config_path": "/Users/…/mcp.json", "configuration": { "url": "https://mcp.slack.com/mcp" } }
```

- `scope` is `global` (`~/.cursor/mcp.json`), `project` (`<repo>/.cursor/mcp.json`),
  or `plugin` (`~/.cursor/plugins/**/mcp.json`).
- `configuration` is `{ command, args }` for stdio servers or `{ url }` for remote.
- **Never included:** `env`, `headers`, `auth` (secrets are dropped at the source).

Device identity (`device_id`) is the raw `IOPlatformUUID` — the same key the
fleet's other Zenity instrumentation uses — so records land on the right device.

## Configuration

| Var | Meaning |
|---|---|
| `ZENITY_TENANT` | `eu` (default) or `us` — selects the endpoints |
| `ZENITY_MANAGER_URL` / `ZENITY_INVENTORY_URL` | override endpoints (tests/staging) |
| `ZENITY_TIMEOUT_SEC` | HTTP timeout (default 5) |

EU/US resolve to `edge-manager.{eu1,us1}.zenity.io` and
`edge-device-inventory.{eu1,us1}.zenity.io` (+ `/api/v1/devices`).

## Testing & observability

```bash
# see the exact payload without POSTing
CURSOR_VERSION=x bash -c '. zenity-inventory/lib/common.sh; . zenity-inventory/lib/scan.sh; \
  zen_build_envelope "$(zen_build_payload)"' | plutil -convert json -r -o - -

# by default the plugin writes NO log files — diagnostics go to stderr,
# which Cursor captures in its own hook log. To also keep a local breadcrumb
# while debugging, opt in with ZENITY_LOG:
ZENITY_LOG=~/.zenity/zenity.log <your test command>   # e.g. "MCP inventory sent (HTTP 200)"
```

`sessionStart` hooks only complete on a **settled** session — if you submit a
prompt the instant a chat opens (or the window churns), Cursor aborts *all*
sessionStart hooks at spawn. A normal session fires the scan in ~1s.

## Scope & limitations

- **macOS only.**
- MCP discovery reads files named **`mcp.json`** (global, project, plugin caches).
  Plugins that declare their server via the manifest `mcp` pointer to a
  **`.mcp.json`** dotfile (e.g. Atlassian) aren't covered yet.
- Inventory only — no prompt/tool evaluation.

## Requirements

macOS with base tools: `bash`, `curl`, `plutil`, `security`, `shasum`, `ioreg`.
