#!/usr/bin/env bash
set -euo pipefail

REPO_RAW_BASE="https://raw.githubusercontent.com/X012C/v2ray_wsss/main"
DEFAULT_NVPS_EXTEND_HOURS="71"

red='\e[91m'
green='\e[92m'
yellow='\e[93m'
cyan='\e[96m'
none='\e[0m'

usage() {
    cat <<'EOF'
nvpss - integrated VLESS/WSS/Caddy + NVIDIA AIR keepalive installer

Usage:
  bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/nvpss.sh) \
    DOMAIN NETSTACK UUID PATH LOCAL_PORT EXTERNAL_PORT NODE_NAME \
    ACME_EMAIL CF_TOKEN CF_ZONE_ID NVIDIA_AIR_API_KEY SIMULATION_ID [EXTEND_HOURS]

Example:
  bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/nvpss.sh) \
    node.example.com 4 "" mypath 3000 12345 US-NODE-01 \
    your-email@gmail.com "$CF_Token" "$CF_Zone_ID" "$NVIDIA_AIR_API_KEY" "$SIMULATION_ID"

Notes:
  DOMAIN          Node domain.
  NETSTACK        4 or 6.
  UUID            Empty string uses install.sh default UUID.
  PATH            WebSocket path without leading slash.
  LOCAL_PORT      Caddy listen port on VPS, e.g. 3000.
  EXTERNAL_PORT   Public/NAT external port, e.g. 12345.
  NODE_NAME       Display name in clients.
  ACME_EMAIL      Let's Encrypt contact email. Do not use example.com.
  CF_TOKEN        Cloudflare token with DNS edit permission.
  CF_ZONE_ID      Cloudflare zone id, not account id.
  NVIDIA_AIR_API_KEY and SIMULATION_ID are used by nvps keepalive.
  EXTEND_HOURS    Optional, default 71.

Environment overrides:
  NVPS_EXTEND_HOURS=71
  NVPS_RUN_NOW=y        Run keepalive once after installing timer. Default y.
  V2RAY_RUN_TESTS=y     Run install tests after node deployment. Default y.
  V2RAY_INSTALL_WARP=n  Skip WARP prompt/install. Default n.

This script intentionally leaves install.sh and nvps.sh usable on their own.
EOF
}

need_root() {
    if [[ "$(id -u)" != "0" ]]; then
        echo -e "$red This command must run as root.$none" >&2
        exit 1
    fi
}

is_valid_email() {
    [[ "$1" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] && [[ ! "$1" =~ @example\. ]]
}

is_valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -ge 1 && "$1" -le 65535 ]]
}

script_path() {
    local name="$1"
    local source_dir
    local local_path
    local tmp_path="$2/$name"

    source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P || true)"
    local_path="$source_dir/$name"

    if [[ -f "$local_path" ]]; then
        echo "$local_path"
        return 0
    fi

    curl -fsSL "$REPO_RAW_BASE/$name" -o "$tmp_path"
    chmod 755 "$tmp_path"
    echo "$tmp_path"
}

mask_secret() {
    local value="${1:-}"
    local length=${#value}

    if [[ "$length" -le 8 ]]; then
        echo "***"
    else
        echo "${value:0:4}****${value: -4}"
    fi
}

if [[ "${1:-}" == "help" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

need_root

if [[ $# -lt 12 ]]; then
    echo -e "$red Missing required arguments.$none" >&2
    usage
    exit 1
fi

domain="$1"
netstack="$2"
uuid="$3"
ws_path="$4"
local_port="$5"
external_port="$6"
node_name="$7"
acme_email="$8"
cf_token="$9"
cf_zone_id="${10}"
nvidia_air_api_key="${11}"
simulation_id="${12}"
extend_hours="${13:-${NVPS_EXTEND_HOURS:-$DEFAULT_NVPS_EXTEND_HOURS}}"

if [[ -z "$domain" || -z "$ws_path" || -z "$node_name" ]]; then
    echo -e "$red DOMAIN, PATH, and NODE_NAME are required.$none" >&2
    exit 1
fi

if [[ "$netstack" != "4" && "$netstack" != "6" ]]; then
    echo -e "$red NETSTACK must be 4 or 6.$none" >&2
    exit 1
fi

if ! is_valid_port "$local_port" || ! is_valid_port "$external_port"; then
    echo -e "$red LOCAL_PORT and EXTERNAL_PORT must be valid ports.$none" >&2
    exit 1
fi

if ! is_valid_email "$acme_email"; then
    echo -e "$red ACME_EMAIL is invalid or uses a forbidden example.com domain.$none" >&2
    exit 1
fi

if [[ -z "$cf_token" || -z "$cf_zone_id" || -z "$nvidia_air_api_key" || -z "$simulation_id" ]]; then
    echo -e "$red CF_TOKEN, CF_ZONE_ID, NVIDIA_AIR_API_KEY, and SIMULATION_ID are required.$none" >&2
    exit 1
fi

if ! [[ "$extend_hours" =~ ^[0-9]+$ ]] || [[ "$extend_hours" -lt 1 || "$extend_hours" -gt 720 ]]; then
    echo -e "$red EXTEND_HOURS must be an integer between 1 and 720.$none" >&2
    exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

install_script="$(script_path install.sh "$tmp_dir")"
nvps_script="$(script_path nvps.sh "$tmp_dir")"

export ACME_EMAIL="$acme_email"
export CF_Token="$cf_token"
export CF_Zone_ID="$cf_zone_id"
export V2RAY_SWITCH_VMESS="${V2RAY_SWITCH_VMESS:-N}"
export V2RAY_RUN_TESTS="${V2RAY_RUN_TESTS:-y}"
export V2RAY_INSTALL_WARP="${V2RAY_INSTALL_WARP:-n}"

echo -e "$yellow Integrated deployment summary $none"
echo "----------------------------------------------------------------"
echo "domain=$domain"
echo "netstack=$netstack"
echo "uuid=${uuid:-<default>}"
echo "path=$ws_path"
echo "local_port=$local_port"
echo "external_port=$external_port"
echo "node_name=$node_name"
echo "acme_email=$acme_email"
echo "cf_token=$(mask_secret "$cf_token")"
echo "cf_zone_id=$cf_zone_id"
echo "nvidia_air_api_key=$(mask_secret "$nvidia_air_api_key")"
echo "simulation_id=$simulation_id"
echo "extend_hours=$extend_hours"
echo

echo -e "$yellow Step 1/2: deploy VLESS/WSS/Caddy node $none"
echo "----------------------------------------------------------------"
bash "$install_script" "$domain" "$netstack" "$uuid" "$ws_path" "$local_port" "$external_port" "$node_name"

echo
echo -e "$yellow Step 2/2: install NVIDIA AIR keepalive $none"
echo "----------------------------------------------------------------"
nvps_args=(
    install
    --api-key "$nvidia_air_api_key"
    --simulation-id "$simulation_id"
    --extend-hours "$extend_hours"
)

if [[ "${NVPS_RUN_NOW:-y}" == [yY] ]]; then
    nvps_args+=(--run-now)
fi

bash "$nvps_script" "${nvps_args[@]}"

echo
echo -e "$green Integrated deployment completed.$none"
echo "Node URL is saved in: $HOME/_v2ray_vless_url_"
echo "Install test commands are saved in: $HOME/_v2ray_test_commands_"
echo "Keepalive config: /etc/nvps.env"
echo "Useful commands:"
echo -e "  ${cyan}cat $HOME/_v2ray_vless_url_${none}"
echo -e "  ${cyan}nvps status${none}"
echo -e "  ${cyan}nvps logs${none}"
echo -e "  ${cyan}nvps run${none}"
