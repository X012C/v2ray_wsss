#!/usr/bin/env bash
set -e

red='\e[91m'
green='\e[92m'
yellow='\e[93m'
cyan='\e[96m'
none='\e[0m'

echo -e "$yellow卸载 V2Ray/Xray/Caddy 并清理本脚本生成的配置$none"
echo "----------------------------------------------------------------"

if [[ "${1:-}" != "--yes" ]]; then
    read -r -p "$(echo -e "这会删除 /etc/caddy、/usr/local/etc/v2ray、/usr/local/etc/xray 和相关日志。继续请输入 ${cyan}YES${none}: ")" confirm
    if [[ "$confirm" != "YES" ]]; then
        echo -e "$yellow已取消$none"
        exit 0
    fi
fi

systemctl stop caddy 2>/dev/null || true
systemctl stop v2ray 2>/dev/null || true
systemctl stop xray 2>/dev/null || true
systemctl disable caddy 2>/dev/null || true
systemctl disable v2ray 2>/dev/null || true
systemctl disable xray 2>/dev/null || true

pkill -f xray 2>/dev/null || true
pkill -f v2ray 2>/dev/null || true

if command -v curl >/dev/null 2>&1; then
    bash <(curl -fsSL https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) --remove || true
fi

apt purge -y caddy 2>/dev/null || true
apt remove -y caddy 2>/dev/null || true
rm -f /etc/apt/sources.list.d/caddy-stable.list
rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg
apt autoremove -y 2>/dev/null || true

rm -rf /etc/caddy
rm -rf /usr/local/etc/v2ray
rm -rf /usr/local/etc/xray
rm -rf /var/log/v2ray
rm -rf /var/log/xray

systemctl daemon-reload 2>/dev/null || true

echo
echo -e "$green卸载清理完成$none"
echo "如果准备重装, 请确认 NAT 内部端口已经空出来, 例如:"
echo -e "${cyan}ss -lntp | grep ':3000'${none}"
