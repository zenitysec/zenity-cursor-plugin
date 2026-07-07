# Changelog

## [0.3.0] — unreleased

- **Self-contained MCP-only scanner.** Removed all vendored external code; the
  `sessionStart` hook now collects **only** Cursor MCP servers and POSTs them.
- **MCP discovery** across global (`~/.cursor/mcp.json`), project
  (`<repo>/.cursor/mcp.json`), and **plugin** (`~/.cursor/plugins/**/mcp.json`)
  configs, tagged with `scope`. Secrets (`env`/`headers`/`auth`) never read/sent.
- **Schema-conformant payload** (matches the digester contract): device block
  (`device_id`/`device_name`/`os_name`/`os_version`/`user_name`/`user_email`/`privilege`),
  `mcp_servers[].configuration` nesting (`{command,args}`|`{url}`), full agent
  `configuration` + empty entity arrays.
- **Device identity** = raw `IOPlatformUUID` (with `sha256(serial)` → `sha256("hostname:"+uname -n)`
  fallbacks) so records correlate to the same device as the fleet's other instrumentation.
- **Keychain-only credentials** (enrollment key + device token); onboarding via
  `zenityctl enroll` / `enroll-gui`. Fail-open.
- **Quiet by default** — the plugin writes no log files in production;
  diagnostics go to stderr (captured by Cursor's hook log). Opt in to a local
  breadcrumb file with `ZENITY_LOG=<path>` when debugging.
- Known scope: macOS only; MCP discovery covers `mcp.json` files (not manifest
  `mcp`→`.mcp.json` pointers yet); inventory only (no prompt/tool evaluation).

## [0.1.0] — superseded

- Initial plugin built on Zenity's vendored `device-instrumentation` producer
  (full inventory). Replaced by the minimal MCP-only scanner above.
