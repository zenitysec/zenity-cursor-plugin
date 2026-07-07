#!/usr/bin/env bash
# common.sh — shared Keychain / config / tenant / URL / JSON helpers used by
# bin/zenityctl (onboarding) and lib/scan.sh (the MCP scan + POST).
# macOS, base tools only (security/plutil/curl/shasum/ioreg).

if [ -n "${__ZEN_COMMON_LOADED:-}" ]; then return 0; fi
__ZEN_COMMON_LOADED=1

ZEN_SERVICE="zenity-cursor-inventory"              # Keychain service for the enrollment key
ZEN_TOKEN_SERVICE="zenity-cursor-inventory-token"  # Keychain service for the device token
ZEN_ACCOUNT="${USER:-$(id -un)}"
ZEN_HOME="${ZENITY_HOME:-$HOME/.zenity}"
ZEN_CONFIG="$ZEN_HOME/config.json"                 # { "tenant": "eu" } (non-secret)
ZEN_TOKEN_CACHE="$ZEN_HOME/cursor.json"            # legacy 0600 token file (pre-Keychain); cleared on uninstall

# Logs to stderr only (captured by Cursor's own hook log) — the plugin writes no
# log files in production. Set ZENITY_LOG=<path> to also append a breadcrumb
# there when debugging; unset (the default) means stderr-only, no file on disk.
zen_log() {
  printf '[zenity-inventory] %s\n' "$*" >&2
  local lf="${ZENITY_LOG:-}"
  [ -n "$lf" ] || return 0
  { mkdir -p "$(dirname "$lf")" 2>/dev/null && printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$lf"; } 2>/dev/null || true
}

# ---- JSON ------------------------------------------------------------------
zen_json_esc() {
  local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}
zen_json_str() { if [ -z "${1:-}" ]; then printf 'null'; else printf '"%s"' "$(zen_json_esc "$1")"; fi; }

# ---- Tenant + endpoints (status display; mirrors vendor cursor_config) ------
zen_tenant() {
  if [ -n "${ZENITY_TENANT:-}" ]; then printf '%s' "$ZENITY_TENANT"; return; fi
  local t=""
  [ -f "$ZEN_CONFIG" ] && t="$(plutil -extract tenant raw -o - "$ZEN_CONFIG" 2>/dev/null || true)"
  printf '%s' "${t:-eu}"
}
# env overrides (ZENITY_MANAGER_URL / ZENITY_INVENTORY_URL) win, for tests/staging.
zen_manager_url()   { local b="${ZENITY_MANAGER_URL:-https://edge-manager.$(zen_tenant)1.zenity.io}";        printf '%s/api/v1/devices' "${b%/}"; }
zen_inventory_url() { local b="${ZENITY_INVENTORY_URL:-https://edge-device-inventory.$(zen_tenant)1.zenity.io}"; printf '%s/api/v1/devices' "${b%/}"; }

# ---- Config (non-secret) ----------------------------------------------------
zen_write_config() {  # $1 = tenant
  mkdir -p "$ZEN_HOME" 2>/dev/null || true
  chmod 700 "$ZEN_HOME" 2>/dev/null || true
  local tmp="$ZEN_CONFIG.$$"
  printf '{"tenant":%s}\n' "$(zen_json_str "$1")" > "$tmp"
  chmod 600 "$tmp" 2>/dev/null || true
  mv "$tmp" "$ZEN_CONFIG"
}

# ---- Keychain ---------------------------------------------------------------
zen_keychain_store() {  # $1 = enrollment key
  security add-generic-password -s "$ZEN_SERVICE" -a "$ZEN_ACCOUNT" -T /usr/bin/security -U -w "$1"
}
zen_keychain_read()   { security find-generic-password -s "$ZEN_SERVICE" -w 2>/dev/null || true; }
zen_keychain_delete() { security delete-generic-password -s "$ZEN_SERVICE" >/dev/null 2>&1 || true; }

# Authorize silent reads by Apple-signed tools. $1 = service; rest passed
# through (e.g. -k <login-password>). Prompts once for the login password.
zen_keychain_pin_partition() {
  local svc="$1"; shift
  security set-generic-password-partition-list -S 'apple-tool:,apple:' -s "$svc" -a "$ZEN_ACCOUNT" "$@" >/dev/null 2>&1
}

# ---- Device token (Keychain; same item the vendored producer caches into) ---
zen_token_read()  { security find-generic-password -s "$ZEN_TOKEN_SERVICE" -w 2>/dev/null || true; }
zen_token_clear() {
  security delete-generic-password -s "$ZEN_TOKEN_SERVICE" >/dev/null 2>&1 || true
  rm -f "$ZEN_TOKEN_CACHE" 2>/dev/null || true
}
