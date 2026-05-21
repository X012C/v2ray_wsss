#!/usr/bin/env bash
set -euo pipefail

NVPS_BIN="/usr/local/bin/nvps"
NVPS_ENV="/etc/nvps.env"
NVPS_SERVICE="/etc/systemd/system/nvps.service"
NVPS_TIMER="/etc/systemd/system/nvps.timer"
NVPS_SOURCE_URL="https://raw.githubusercontent.com/X012C/v2ray_wsss/main/nvps.sh"
DEFAULT_API_BASE="https://api.air-ngc.nvidia.com/api/v3"
DEFAULT_EXTEND_HOURS="71"

red='\e[91m'
green='\e[92m'
yellow='\e[93m'
cyan='\e[96m'
none='\e[0m'

usage() {
    cat <<'EOF'
nvps - NVIDIA AIR simulation keepalive helper

Usage:
  nvps install      Install or update the systemd timer
  nvps install --api-key KEY --simulation-id ID [--extend-hours 71]
  nvps uninstall    Disable and remove the timer, service, and config
  nvps status       Show timer/service status
  nvps logs         Show recent keepalive logs
  nvps run          Run keepalive once now
  nvps next         Show next scheduled run
  nvps config       Show saved config with API key masked
  nvps help         Show this help

First install from GitHub:
  bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/nvps.sh) install
EOF
}

need_root() {
    if [[ "$(id -u)" != "0" ]]; then
        echo -e "$red This command must run as root.$none" >&2
        exit 1
    fi
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

load_env() {
    if [[ -f "$NVPS_ENV" ]]; then
        # shellcheck disable=SC1090
        source "$NVPS_ENV"
    fi

    NVIDIA_AIR_API_BASE="${NVIDIA_AIR_API_BASE:-$DEFAULT_API_BASE}"
    NVPS_EXTEND_HOURS="${NVPS_EXTEND_HOURS:-$DEFAULT_EXTEND_HOURS}"
}

write_env() {
    local api_key="$1"
    local simulation_id="$2"
    local api_base="$3"
    local extend_hours="$4"

    umask 077
    cat >"$NVPS_ENV" <<EOF
NVIDIA_AIR_API_BASE="$api_base"
NVIDIA_AIR_API_KEY="$api_key"
SIMULATION_ID="$simulation_id"
NVPS_EXTEND_HOURS="$extend_hours"
EOF
    chmod 600 "$NVPS_ENV"
    chown root:root "$NVPS_ENV"
}

write_units() {
    cat >"$NVPS_SERVICE" <<EOF
[Unit]
Description=NVIDIA AIR simulation keepalive
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=$NVPS_ENV
ExecStart=$NVPS_BIN run
EOF

    cat >"$NVPS_TIMER" <<'EOF'
[Unit]
Description=Run NVIDIA AIR simulation keepalive periodically

[Timer]
OnBootSec=5min
OnUnitActiveSec=12h
Persistent=true
RandomizedDelaySec=10min

[Install]
WantedBy=timers.target
EOF
}

install_self() {
    local current
    current="$(readlink -f "$0")"

    if [[ "$current" == "$NVPS_BIN" ]]; then
        chmod 755 "$NVPS_BIN"
    elif [[ -f "$current" && "$current" != /proc/*/fd/* && "$current" != /dev/fd/* ]]; then
        install -m 755 "$current" "$NVPS_BIN"
    else
        curl -fsSL "$NVPS_SOURCE_URL" -o "$NVPS_BIN"
        chmod 755 "$NVPS_BIN"
    fi
}

install_cmd() {
    need_root

    local api_key
    local simulation_id
    local api_base
    local extend_hours
    local run_now="n"

    load_env

    api_key="${NVIDIA_AIR_API_KEY:-}"
    simulation_id="${SIMULATION_ID:-}"
    api_base="$NVIDIA_AIR_API_BASE"
    extend_hours="$NVPS_EXTEND_HOURS"

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --api-key)
            api_key="${2:-}"
            shift 2
            ;;
        --simulation-id)
            simulation_id="${2:-}"
            shift 2
            ;;
        --api-base)
            api_base="${2:-}"
            shift 2
            ;;
        --extend-hours)
            extend_hours="${2:-}"
            shift 2
            ;;
        --run-now)
            run_now="y"
            shift
            ;;
        *)
            echo -e "$red Unknown install option: $1 $none" >&2
            exit 1
            ;;
        esac
    done

    echo -e "$yellow Install or update NVIDIA AIR keepalive timer $none"
    echo "----------------------------------------------------------------"
    echo "The API key will be stored in $NVPS_ENV with 600 permissions."
    echo

    if [[ -z "$api_key" ]]; then
        read -r -s -p "NVIDIA AIR API Key: " api_key
        echo
    fi
    if [[ -z "$simulation_id" ]]; then
        read -r -p "Simulation ID: " simulation_id
    fi
    if [[ -z "$api_base" ]]; then
        read -r -p "API base [$NVIDIA_AIR_API_BASE]: " api_base
    fi
    if [[ -z "$extend_hours" ]]; then
        read -r -p "Extend hours [$NVPS_EXTEND_HOURS]: " extend_hours
    fi

    api_base="${api_base:-$NVIDIA_AIR_API_BASE}"
    extend_hours="${extend_hours:-$NVPS_EXTEND_HOURS}"

    if [[ -z "$api_key" || -z "$simulation_id" ]]; then
        echo -e "$red API key and Simulation ID are required.$none" >&2
        exit 1
    fi

    if ! [[ "$extend_hours" =~ ^[0-9]+$ ]] || [[ "$extend_hours" -lt 1 || "$extend_hours" -gt 720 ]]; then
        echo -e "$red Extend hours must be an integer between 1 and 720.$none" >&2
        exit 1
    fi

    install_self
    write_env "$api_key" "$simulation_id" "$api_base" "$extend_hours"
    write_units

    systemctl daemon-reload
    systemctl enable --now nvps.timer

    echo
    echo -e "$green Installed nvps timer.$none"
    echo "Run once now to verify:"
    echo -e "  ${cyan}nvps run${none}"
    echo "Check status:"
    echo -e "  ${cyan}nvps status${none}"

    if [[ "$run_now" == "y" ]]; then
        "$NVPS_BIN" run
    fi
}

uninstall_cmd() {
    need_root

    local assume_yes="${1:-}"
    local remove_bin="n"

    if [[ "$assume_yes" != "--yes" ]]; then
        read -r -p "Remove nvps timer/service/config? Type YES to continue: " confirm
        if [[ "$confirm" != "YES" ]]; then
            echo -e "$yellow Canceled.$none"
            exit 0
        fi
        read -r -p "Also remove $NVPS_BIN? [y/N]: " remove_bin
    else
        remove_bin="y"
    fi

    systemctl disable --now nvps.timer 2>/dev/null || true
    systemctl stop nvps.service 2>/dev/null || true

    rm -f "$NVPS_SERVICE" "$NVPS_TIMER" "$NVPS_ENV"
    if [[ "$remove_bin" =~ ^[yY]$ ]]; then
        rm -f "$NVPS_BIN"
    fi

    systemctl daemon-reload 2>/dev/null || true

    echo -e "$green nvps uninstalled.$none"
}

status_cmd() {
    systemctl status nvps.timer --no-pager || true
    echo
    systemctl status nvps.service --no-pager || true
}

logs_cmd() {
    journalctl -u nvps.service -n "${1:-100}" --no-pager
}

next_cmd() {
    systemctl list-timers nvps.timer --no-pager || true
}

config_cmd() {
    load_env

    echo "config_file=$NVPS_ENV"
    echo "NVIDIA_AIR_API_BASE=${NVIDIA_AIR_API_BASE:-}"
    echo "NVIDIA_AIR_API_KEY=$(mask_secret "${NVIDIA_AIR_API_KEY:-}")"
    echo "SIMULATION_ID=${SIMULATION_ID:-}"
    echo "NVPS_EXTEND_HOURS=${NVPS_EXTEND_HOURS:-}"
}

run_cmd() {
    load_env

    : "${NVIDIA_AIR_API_KEY:?missing NVIDIA_AIR_API_KEY}"
    : "${SIMULATION_ID:?missing SIMULATION_ID}"
    : "${NVIDIA_AIR_API_BASE:?missing NVIDIA_AIR_API_BASE}"
    : "${NVPS_EXTEND_HOURS:?missing NVPS_EXTEND_HOURS}"

    if ! [[ "$NVPS_EXTEND_HOURS" =~ ^[0-9]+$ ]]; then
        echo "NVPS_EXTEND_HOURS must be an integer." >&2
        exit 1
    fi

    local target_sleep_at
    local payload
    local before_body
    local after_body
    local simulation_url
    local before_code
    local after_code
    local before_sleep_at
    local after_sleep_at

    target_sleep_at="$(
        python3 - "$NVPS_EXTEND_HOURS" <<'PY'
from datetime import datetime, timedelta, timezone
import sys

hours = int(sys.argv[1])
target = datetime.now(timezone.utc) + timedelta(hours=hours)
print(target.replace(microsecond=0).isoformat().replace("+00:00", "Z"))
PY
    )"

    payload="$(mktemp)"
    before_body="$(mktemp)"
    after_body="$(mktemp)"
    trap 'rm -f "$payload" "$before_body" "$after_body"' RETURN

    printf '{"sleep_at":"%s"}' "$target_sleep_at" >"$payload"
    simulation_url="${NVIDIA_AIR_API_BASE%/}/simulations/${SIMULATION_ID}/"

    echo "target_sleep_at=$target_sleep_at"
    echo "simulation_url=$simulation_url"

    before_code="$(
        curl --ipv4 -sS -w '%{http_code}' \
            -H 'Accept: application/json' \
            -H 'Content-Type: application/json' \
            -H 'User-Agent: air-sdk/1.3.1' \
            -H 'X-Air-Sdk-Version: 1.3.1' \
            -H "Authorization: Bearer $NVIDIA_AIR_API_KEY" \
            -o "$before_body" \
            "$simulation_url"
    )"

    echo "before_http_code=$before_code"

    if [[ "$before_code" != "200" ]]; then
        echo "GET failed: HTTP $before_code" >&2
        echo "response body:" >&2
        cat "$before_body" >&2
        echo >&2
        exit 1
    fi

    before_sleep_at="$(
        python3 - "$before_body" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)

print(data.get("sleep_at") or "")
PY
    )"

    echo "before_sleep_at=$before_sleep_at"

    after_code="$(
        curl --ipv4 -sS -w '%{http_code}' -X PATCH \
            -H 'Accept: application/json' \
            -H 'Content-Type: application/json' \
            -H 'User-Agent: air-sdk/1.3.1' \
            -H 'X-Air-Sdk-Version: 1.3.1' \
            -H "Authorization: Bearer $NVIDIA_AIR_API_KEY" \
            --data @"$payload" \
            -o "$after_body" \
            "$simulation_url"
    )"

    echo "after_http_code=$after_code"

    if [[ "$after_code" != "200" ]]; then
        echo "PATCH failed: HTTP $after_code" >&2
        echo "response body:" >&2
        cat "$after_body" >&2
        echo >&2
        exit 1
    fi

    after_sleep_at="$(
        python3 - "$after_body" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)

print(data.get("sleep_at") or "")
PY
    )"

    echo "after_sleep_at=$after_sleep_at"

    if [[ "$after_sleep_at" != "$target_sleep_at" ]]; then
        echo "verify failed: expected=$target_sleep_at actual=$after_sleep_at" >&2
        echo "response body:" >&2
        cat "$after_body" >&2
        echo >&2
        exit 1
    fi

    echo "ok"
}

cmd="${1:-help}"
shift || true

case "$cmd" in
install)
    install_cmd "$@"
    ;;
uninstall|remove)
    uninstall_cmd "$@"
    ;;
status)
    status_cmd
    ;;
logs|log)
    logs_cmd "$@"
    ;;
run|once)
    run_cmd
    ;;
next)
    next_cmd
    ;;
config)
    config_cmd
    ;;
help|-h|--help)
    usage
    ;;
*)
    echo -e "$red Unknown command: $cmd $none" >&2
    usage
    exit 1
    ;;
esac
