#!/bin/sh
set -eu

XRAY_BIN="/usr/local/bin/xray"
XRAY_DIR="/etc/xray"
XRAY_CONFIG="$XRAY_DIR/config.json"
XRAY_LINK="$HOME/_xray_reality_url_"
XRAY_LOG="/var/log/xray.log"
XRAY_SERVICE="/etc/init.d/xray"
DEFAULT_PORT="443"
DEFAULT_NODE_NAME="ALPINE-REALITY"
DEFAULT_SNI="www.microsoft.com"

red="$(printf '\033[91m')"
green="$(printf '\033[92m')"
yellow="$(printf '\033[93m')"
cyan="$(printf '\033[96m')"
none="$(printf '\033[0m')"

usage() {
    cat <<'EOF'
alpine-reality - minimal Xray VLESS Reality installer for tiny Alpine VPS

Install:
  curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/extras/alpine-reality.sh | sh -s [PORT] [NODE_NAME] [SNI]

Examples:
  curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/extras/alpine-reality.sh | sh -s 443 US-ALPINE-01
  curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/extras/alpine-reality.sh | sh -s install 443 US-ALPINE-01 www.microsoft.com

Commands:
  install [PORT] [NODE_NAME] [SNI]  Install or reinstall Reality node
  uninstall                         Remove service, config, and xray binary
  status                            Show service/process status
  logs                              Show recent xray log
  link                              Print saved Reality share link
  help                              Show this help

Environment:
  SERVER_ADDR=1.2.3.4               Address used in the share link, default auto-detect IPv4
  UUID=xxxxxxxx-xxxx-....           Optional fixed UUID
  SHORT_ID=0123456789abcdef         Optional fixed Reality shortId
  XRAY_VERSION=v25.4.30             Optional pinned Xray-core version

This script is for Alpine/OpenRC or tiny Alpine containers. It does not install
Caddy, ACME certificates, Cloudflare DNS-01, or NVIDIA keepalive.
EOF
}

die() {
    echo "${red}$1${none}" >&2
    exit 1
}

need_root() {
    [ "$(id -u)" = "0" ] || die "This script must run as root."
}

valid_port() {
    case "$1" in
    ''|*[!0-9]*)
        return 1
        ;;
    *)
        [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
        ;;
    esac
}

sanitize_node_name() {
    echo "$1" | sed 's/[^A-Za-z0-9._-]/_/g; s/_\{1,\}/_/g; s/^_//; s/_$//'
}

valid_hostname() {
    echo "$1" | grep -Eq '^[A-Za-z0-9.-]+$'
}

detect_asset() {
    arch="$(uname -m)"
    case "$arch" in
    x86_64|amd64)
        echo "Xray-linux-64.zip"
        ;;
    aarch64|arm64)
        echo "Xray-linux-arm64-v8a.zip"
        ;;
    armv7l|armv7)
        echo "Xray-linux-arm32-v7a.zip"
        ;;
    *)
        die "Unsupported architecture: $arch"
        ;;
    esac
}

download_url() {
    asset="$1"
    if [ -n "${XRAY_VERSION:-}" ]; then
        echo "https://github.com/XTLS/Xray-core/releases/download/$XRAY_VERSION/$asset"
    else
        echo "https://github.com/XTLS/Xray-core/releases/latest/download/$asset"
    fi
}

install_packages() {
    apk update
    apk add --no-cache ca-certificates curl unzip openssl
    update-ca-certificates >/dev/null 2>&1 || true
}

install_xray() {
    asset="$(detect_asset)"
    url="$(download_url "$asset")"
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT

    echo "${yellow}Downloading Xray-core: $asset${none}"
    curl -fL "$url" -o "$tmp_dir/xray.zip"
    unzip -o "$tmp_dir/xray.zip" -d "$tmp_dir/xray" >/dev/null

    install -m 755 "$tmp_dir/xray/xray" "$XRAY_BIN"
    mkdir -p /usr/local/share/xray
    [ -f "$tmp_dir/xray/geoip.dat" ] && install -m 644 "$tmp_dir/xray/geoip.dat" /usr/local/share/xray/geoip.dat
    [ -f "$tmp_dir/xray/geosite.dat" ] && install -m 644 "$tmp_dir/xray/geosite.dat" /usr/local/share/xray/geosite.dat
}

generate_uuid() {
    if [ -n "${UUID:-}" ]; then
        echo "$UUID"
    elif [ -r /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        hexdump -n 16 -e '4/4 "%08X" 1 "\n"' /dev/urandom | sed 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/' | tr 'A-F' 'a-f'
    fi
}

generate_short_id() {
    if [ -n "${SHORT_ID:-}" ]; then
        echo "$SHORT_ID"
    else
        openssl rand -hex 8
    fi
}

generate_reality_keys() {
    if ! keys="$("$XRAY_BIN" x25519 2>&1)"; then
        echo "$keys" >&2
        die "Failed to run: $XRAY_BIN x25519"
    fi

    private_key="$(
        printf '%s\n' "$keys" |
            sed -n \
                -e 's/^[Pp]rivate[Kk]ey:[[:space:]]*//p' \
                -e 's/^[Pp]rivate[[:space:]]*[Kk]ey:[[:space:]]*//p' |
            head -n 1
    )"
    public_key="$(
        printf '%s\n' "$keys" |
            sed -n \
                -e 's/^[Pp]ublic[Kk]ey:[[:space:]]*//p' \
                -e 's/^[Pp]ublic[[:space:]]*[Kk]ey:[[:space:]]*//p' \
                -e 's/^[Pp]assword[[:space:]]*(Public[Kk]ey):[[:space:]]*//p' \
                -e 's/^[Pp]assword[[:space:]]*(Public[[:space:]]*[Kk]ey):[[:space:]]*//p' |
            head -n 1
    )"

    if [ -z "$private_key" ] || [ -z "$public_key" ]; then
        echo "Unexpected xray x25519 output:" >&2
        printf '%s\n' "$keys" >&2
    fi
    [ -n "$private_key" ] || die "Failed to generate Reality private key."
    [ -n "$public_key" ] || die "Failed to generate Reality public key."
}

detect_server_addr() {
    if [ -n "${SERVER_ADDR:-}" ]; then
        echo "$SERVER_ADDR"
        return 0
    fi

    addr="$(curl -4s --max-time 8 https://api.ipify.org || true)"
    [ -n "$addr" ] || addr="$(curl -4s --max-time 8 https://ifconfig.me || true)"
    [ -n "$addr" ] || die "Cannot detect public IPv4. Set SERVER_ADDR manually."
    echo "$addr"
}

write_config() {
    mkdir -p "$XRAY_DIR"
    cat >"$XRAY_CONFIG" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $port,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$sni:443",
          "xver": 0,
          "serverNames": [
            "$sni"
          ],
          "privateKey": "$private_key",
          "shortIds": [
            "$short_id"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF
    chmod 600 "$XRAY_CONFIG"
}

write_service() {
    if command -v rc-service >/dev/null 2>&1 && [ -d /etc/init.d ]; then
        cat >"$XRAY_SERVICE" <<EOF
#!/sbin/openrc-run
name="xray"
description="Xray Reality"
command="$XRAY_BIN"
command_args="run -config $XRAY_CONFIG"
command_background=true
pidfile="/run/xray.pid"
output_log="$XRAY_LOG"
error_log="$XRAY_LOG"

depend() {
    need net
}
EOF
        chmod 755 "$XRAY_SERVICE"
        rc-update add xray default >/dev/null 2>&1 || true
        rc-service xray restart
    else
        stop_fallback
        mkdir -p /run
        nohup "$XRAY_BIN" run -config "$XRAY_CONFIG" >"$XRAY_LOG" 2>&1 &
        echo $! >/run/xray.pid
    fi
}

stop_fallback() {
    if [ -f /run/xray.pid ]; then
        kill "$(cat /run/xray.pid)" 2>/dev/null || true
        rm -f /run/xray.pid
    fi
    if command -v pkill >/dev/null 2>&1; then
        pkill -f "$XRAY_BIN run -config $XRAY_CONFIG" 2>/dev/null || true
    fi
}

restart_xray() {
    write_service
    sleep 1
}

save_link() {
    share_link="vless://$uuid@$server_addr:$port?encryption=none&security=reality&sni=$sni&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&flow=xtls-rprx-vision&spx=%2F#$node_name"
    echo "$share_link" >"$XRAY_LINK"
    chmod 600 "$XRAY_LINK"
}

show_result() {
    echo
    echo "${green}Xray Reality node installed.${none}"
    echo "----------------------------------------------------------------"
    echo "server=$server_addr"
    echo "port=$port"
    echo "sni=$sni"
    echo "uuid=$uuid"
    echo "public_key=$public_key"
    echo "short_id=$short_id"
    echo "node_name=$node_name"
    echo
    echo "VLESS Reality URL:"
    echo "${cyan}$share_link${none}"
    echo
    echo "Saved to: $XRAY_LINK"
    echo "Config: $XRAY_CONFIG"
    echo
    echo "Useful commands:"
    echo "  sh alpine-reality.sh status"
    echo "  sh alpine-reality.sh logs"
    echo "  sh alpine-reality.sh link"
}

install_cmd() {
    need_root

    port="${1:-$DEFAULT_PORT}"
    node_name="${2:-$DEFAULT_NODE_NAME}"
    sni="${3:-$DEFAULT_SNI}"
    node_name="$(sanitize_node_name "$node_name")"

    valid_port "$port" || die "Invalid port: $port"
    [ -n "$node_name" ] || die "Invalid node name."
    valid_hostname "$sni" || die "Invalid SNI hostname: $sni"

    install_packages
    install_xray

    server_addr="$(detect_server_addr)"
    uuid="$(generate_uuid)"
    short_id="$(generate_short_id)"
    generate_reality_keys
    write_config
    restart_xray
    save_link
    show_result
}

uninstall_cmd() {
    need_root

    if command -v rc-service >/dev/null 2>&1; then
        rc-service xray stop 2>/dev/null || true
        rc-update del xray default 2>/dev/null || true
    fi
    stop_fallback

    rm -f "$XRAY_SERVICE" "$XRAY_BIN" "$XRAY_LINK" "$XRAY_LOG"
    rm -rf "$XRAY_DIR"
    echo "${green}Xray Reality removed.${none}"
}

status_cmd() {
    if command -v rc-service >/dev/null 2>&1 && [ -f "$XRAY_SERVICE" ]; then
        rc-service xray status || true
    fi
    ps | grep '[x]ray' || true
    if command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null | grep ":${1:-$DEFAULT_PORT} " || true
    fi
}

logs_cmd() {
    if [ -f "$XRAY_LOG" ]; then
        tail -n 80 "$XRAY_LOG"
    else
        echo "No log file: $XRAY_LOG"
    fi
}

link_cmd() {
    if [ -f "$XRAY_LINK" ]; then
        cat "$XRAY_LINK"
    else
        die "No saved link found: $XRAY_LINK"
    fi
}

cmd="${1:-install}"
case "$cmd" in
install)
    [ "$#" -gt 0 ] && shift
    install_cmd "$@"
    ;;
uninstall|remove)
    uninstall_cmd
    ;;
status)
    shift || true
    status_cmd "$@"
    ;;
logs|log)
    logs_cmd
    ;;
link|url)
    link_cmd
    ;;
help|-h|--help)
    usage
    ;;
''|*[!0-9]*)
    if [ "$cmd" = "$DEFAULT_PORT" ]; then
        shift
        install_cmd "$cmd" "$@"
    else
        echo "${red}Unknown command: $cmd${none}" >&2
        usage
        exit 1
    fi
    ;;
*)
    install_cmd "$@"
    ;;
esac
