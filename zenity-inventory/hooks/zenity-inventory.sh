#!/usr/bin/env bash
# zenity-inventory.sh — Cursor `sessionStart` hook (fire-and-forget).
#
# The scan: collect ONLY the device's Cursor MCP servers and POST them
# to Zenity AI Edge. Self-contained — no external/vendored producer. Credentials
# come from the macOS Keychain (onboarded via zenityctl). FAIL-OPEN: any error
# logs to stderr and the script still exits 0; it must never disrupt a session.

set -uo pipefail
trap 'exit 0' EXIT INT TERM

STDIN_JSON="$(cat 2>/dev/null || true)"   # Cursor's sessionStart JSON; we only need is_background_agent
case "$STDIN_JSON" in
  *'"is_background_agent":true'*|*'"is_background_agent": true'*) IS_BG=true ;;
  *) IS_BG=false ;;
esac

ROOT="${CURSOR_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=../lib/common.sh
. "$ROOT/lib/common.sh" 2>/dev/null || exit 0
# shellcheck source=../lib/scan.sh
. "$ROOT/lib/scan.sh" 2>/dev/null || exit 0

main() {
  # Skip background agents (fire sessionStart per task — would flood the edge)
  # and remote workspaces (would describe the local box, not the workspace).
  [ "$IS_BG" = "true" ] && { zen_log "skip: background agent"; return 0; }
  [ "${CURSOR_CODE_REMOTE:-}" = "true" ] && { zen_log "skip: remote workspace"; return 0; }

  # First-run onboarding (zero-terminal): tenant + key dialog, stored in the
  # Keychain. No-op without a GUI session / for background agents.
  if [ -z "$(zen_keychain_read)" ] && [ "$IS_BG" != "true" ]; then
    "$ROOT/bin/zenityctl" enroll-gui >/dev/null 2>&1 || true
  fi
  if [ -z "$(zen_keychain_read)" ]; then
    printf '%s\n' '{"additional_context":"Zenity inventory is not configured. Run `zenityctl enroll` in a terminal (or reopen Cursor with a GUI session)."}'
    return 0
  fi

  local token url payload out status
  token="$(zen_current_token)" || { zen_log "no device token"; return 0; }
  [ -n "$token" ] || { zen_log "no device token"; return 0; }

  url="$(zen_inventory_url)"
  payload="$(zen_build_envelope "$(zen_build_payload)")"
  out="$(zen_post_json "$url" "$payload" "$token")"; status="$(zen_http_status "$out")"
  case "$status" in
    2*) zen_log "MCP inventory sent (HTTP $status)" ;;
    401|403)
      zen_token_clear
      token="$(zen_current_token)" || token=""
      [ -n "$token" ] && zen_post_json "$url" "$payload" "$token" >/dev/null
      zen_log "re-enrolled and retried (was HTTP $status)" ;;
    *) zen_log "MCP inventory POST returned HTTP $status" ;;
  esac
}

main
exit 0
