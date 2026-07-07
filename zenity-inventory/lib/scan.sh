#!/usr/bin/env bash
# scan.sh — the "stupid scan": collect ONLY Cursor MCP servers and POST them to
# Zenity AI Edge in the v1.0.0 envelope. Self-contained (our own code, no
# external producer). macOS, base tools only (security/curl/plutil/shasum/ioreg).
#
# Requires common.sh (Keychain/config/tenant/URL/JSON helpers) to be sourced first.

if [ -n "${__ZEN_SCAN_LOADED:-}" ]; then return 0; fi
__ZEN_SCAN_LOADED=1

ZEN_SCHEMA_VERSION="1.0.0"
ZEN_DEVICE_AGENT_VERSION="cursor-mcp-scan-bash-0.3.0"
ZEN_HTTP_TIMEOUT="${ZENITY_TIMEOUT_SEC:-5}"

# ---- identity / device facts (match the digester's device schema) ----------
zen_sha256() { shasum -a 256 | awk '{print $1}'; }
# Raw IOPlatformUUID — the device key the digester uses (and what the org's
# official hook reports), so our data lands on the same device. Fallbacks:
# sha256(serial) -> sha256(hostname).
zen_device_id() {
  local uuid serial
  uuid="$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformUUID/{print $4; exit}')"
  [ -n "$uuid" ] && { printf '%s' "$uuid"; return; }
  serial="$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformSerialNumber/{print $4; exit}')"
  [ -n "$serial" ] && { printf '%s' "$serial" | zen_sha256; return; }
  printf 'hostname:%s' "$(uname -n 2>/dev/null)" | zen_sha256   # match reference fallback (uname -n)
}
zen_device_name()  { scutil --get ComputerName 2>/dev/null || hostname 2>/dev/null; }
zen_os_version()   { sw_vers -productVersion 2>/dev/null; }
zen_privilege()    { id -Gn 2>/dev/null | grep -qw admin && printf 'LocalAdmin' || printf 'Standard'; }
zen_install_path() { local p; for p in "/Applications/Cursor.app" "$HOME/Applications/Cursor.app"; do [ -d "$p" ] && { printf '%s' "$p"; return; }; done; printf '/Applications/Cursor.app'; }
zen_now_iso()      { date -u +%Y-%m-%dT%H:%M:%S.000Z; }

# ---- device token (Keychain write; read/clear live in common.sh) -----------
zen_token_write() {  # $1 = device token
  security add-generic-password -s "$ZEN_TOKEN_SERVICE" -a "$ZEN_ACCOUNT" \
    -T /usr/bin/security -U -w "$1" >/dev/null 2>&1
}

# ---- HTTP (prints "<body>\n<status>"; split with the helpers) --------------
zen_post_json() {
  local url="$1" body="$2" bearer="${3:-}"
  local args=(--silent --show-error --max-time "$ZEN_HTTP_TIMEOUT"
              -H "Content-Type: application/json" -w '\n%{http_code}' --data-binary @-)
  [ -n "$bearer" ] && args+=(-H "Authorization: Bearer $bearer")
  printf '%s' "$body" | curl "${args[@]}" "$url" 2>/dev/null
}
zen_http_status() { printf '%s' "${1##*$'\n'}"; }
zen_http_body()   { printf '%s' "${1%$'\n'*}"; }

# ---- enrollment (key from Keychain -> device token, cached in Keychain) -----
zen_enroll() {
  local key url body out status resp token tmp
  key="$(zen_keychain_read)"; [ -n "$key" ] || { zen_log "no enrollment key"; return 1; }
  url="$(zen_manager_url)"
  body="$(printf '{"deviceId":%s,"enrollmentKey":%s}' "$(zen_json_str "$(zen_device_id)")" "$(zen_json_str "$key")")"
  out="$(zen_post_json "$url" "$body")"; status="$(zen_http_status "$out")"
  case "$status" in 2*) : ;; *) zen_log "enroll HTTP $status: $(zen_http_body "$out" | tr -d '\n' | cut -c1-200)"; return 1 ;; esac
  resp="$(zen_http_body "$out")"; tmp="$(mktemp)"; printf '%s' "$resp" > "$tmp"
  token="$(plutil -extract accessToken raw -o - "$tmp" 2>/dev/null || true)"; rm -f "$tmp"
  [ -n "$token" ] || { zen_log "enroll: no accessToken"; return 1; }
  zen_token_write "$token"; printf '%s' "$token"
}
zen_current_token() {
  local t; t="$(zen_token_read)"
  if [ -n "$t" ]; then printf '%s' "$t"; return 0; fi
  zen_enroll
}

# ---- MCP scan (the only thing we collect) ----------------------------------
# zen_json_keys FILE KEYPATH — immediate child keys of the object at KEYPATH
# (CLT-free via plutil xml1 + awk). Limitation: keys containing '.' aren't re-addressable.
zen_json_keys() {
  local file="$1" keypath="${2:-}" tmp
  [ -f "$file" ] || return 0
  tmp="$(mktemp)" || return 0
  if [ -n "$keypath" ]; then plutil -extract "$keypath" xml1 -o "$tmp" "$file" 2>/dev/null || { rm -f "$tmp"; return 0; }
  else plutil -convert xml1 -o "$tmp" "$file" 2>/dev/null || { rm -f "$tmp"; return 0; }; fi
  awk '
    /<dict>|<array>/ { depth++ }
    /<key>/ { if (depth==1){ l=$0; sub(/.*<key>/,"",l); sub(/<\/key>.*/,"",l); print l } }
    /<\/dict>|<\/array>/ { depth-- }
  ' "$tmp"
  rm -f "$tmp"
}
zen_extract() { plutil -extract "$2" "$3" -o - "$1" 2>/dev/null || true; }

# zen_scan_mcp_file FILE DEVICE_ID — emit comma-prefixed mcp_server objects.
# Reads only structural fields (name/command/url/args); env/headers/auth are
# never read, so secrets are never emitted.
zen_scan_mcp_file() {
  local file="$1" dev="$2" scope="${3:-}" name id cmd url args cfg
  [ -f "$file" ] || return 0
  zen_json_keys "$file" mcpServers | while IFS= read -r name; do
    [ -n "$name" ] || continue
    cmd="$(zen_extract "$file" "mcpServers.$name.command" raw)"
    url="$(zen_extract "$file" "mcpServers.$name.url" raw)"
    args="$(zen_extract "$file" "mcpServers.$name.args" json)"; case "$args" in \[*) : ;; *) args='[]' ;; esac
    # configuration: { command, args } for stdio | { url } for remote (env/headers never read).
    if [ -n "$cmd" ]; then cfg="$(printf '{"command":%s,"args":%s}' "$(zen_json_str "$cmd")" "$args")"
    elif [ -n "$url" ]; then cfg="$(printf '{"url":%s}' "$(zen_json_str "$url")")"
    else cfg='{}'; fi
    id="$(printf '%s|%s|%s|%s' "$dev" "$(zen_install_path)" "$file" "$name" | zen_sha256)"
    printf ',{"id":%s,"name":%s,"scope":%s,"config_path":%s,"configuration":%s}' \
      "$(zen_json_str "$id")" "$(zen_json_str "$name")" "$(zen_json_str "$scope")" "$(zen_json_str "$file")" "$cfg"
  done
}
zen_arr() { local s; s="$(cat)"; printf '[%s]' "${s#,}"; }

# ---- envelope (device + Cursor agent carrying ONLY mcp_servers) ------------
zen_build_payload() {
  local dev proj mcp
  dev="$(zen_device_id)"; proj="${CURSOR_PROJECT_DIR:-$PWD}"
  # Cursor MCP servers live in three places: global, project, and plugin-provided
  # configs (e.g. ~/.cursor/plugins/cache/.../mcp.json). Scan all of them.
  mcp="$( { zen_scan_mcp_file "$HOME/.cursor/mcp.json" "$dev" "global"
            zen_scan_mcp_file "$proj/.cursor/mcp.json" "$dev" "project"
            find "$HOME/.cursor/plugins" -name mcp.json 2>/dev/null | while IFS= read -r f; do
              zen_scan_mcp_file "$f" "$dev" "plugin"
            done; } | zen_arr )"
  local ts ipath; ts="$(zen_now_iso)"; ipath="$(zen_install_path)"
  printf '{"device":{"device_id":%s,"device_name":%s,"os_name":"macOS","os_version":%s,"user_name":%s,"user_email":null,"privilege":%s},"agents":[{"name":"Cursor","agent_type_enum":"Cursor","version":%s,"created_at_utc":%s,"last_updated_at_utc":%s,"configuration":{"install_path":%s,"surfaces":["ide"],"plugins_enabled":true,"mcp_enabled":true,"terminal_access":true,"user_email":%s},"mcp_servers":%s,"hooks":[],"rules":[],"skills":[],"subagents":[],"credentials":[],"principals":[]}]}' \
    "$(zen_json_str "$dev")" "$(zen_json_str "$(zen_device_name)")" "$(zen_json_str "$(zen_os_version)")" \
    "$(zen_json_str "$ZEN_ACCOUNT")" "$(zen_json_str "$(zen_privilege)")" \
    "$(zen_json_str "${CURSOR_VERSION:-}")" "$(zen_json_str "$ts")" "$(zen_json_str "$ts")" \
    "$(zen_json_str "$ipath")" "$(zen_json_str "${CURSOR_USER_EMAIL:-}")" "$mcp"
}
zen_message_id() { printf '%s-%s-%s' "$$" "${RANDOM}${RANDOM}" "$(date -u +%s)" | zen_sha256 | cut -c1-32; }
zen_build_envelope() {
  local payload="$1" metadata
  metadata="$(printf '{"schema_version":%s,"device_agent_version":%s,"created_at_utc":%s,"content_type":"application/json"}' \
    "$(zen_json_str "$ZEN_SCHEMA_VERSION")" "$(zen_json_str "$ZEN_DEVICE_AGENT_VERSION")" "$(zen_json_str "$(zen_now_iso)")")"
  printf '{"message_id":%s,"message_type":"DATA","metadata":%s,"payload":%s}' \
    "$(zen_json_str "$(zen_message_id)")" "$metadata" "$payload"
}
