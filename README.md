# 一键安装
```
apt update
apt install -y curl
```
```
bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/install.sh)
```

## 带参数安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/install.sh) 域名 网络栈 UUID path 本机监听端口 外部端口
```

参数说明:

- `域名`: 例如 `example.com`
- `网络栈`: `4` 表示 IPv4, `6` 表示 IPv6, 留空则脚本自动判断
- `UUID`: 留空则使用脚本生成的默认 UUID
- `path`: WebSocket 分流路径, 不要带 `/`
- `本机监听端口`: Caddy 在 VPS 内部监听的端口, 普通 VPS 默认 `443`; 内外端口映射时可填内部端口, 例如 `3000`
- `外部端口`: 客户端节点里填写的端口, 普通 VPS 默认等于本机监听端口; 内外端口映射时填商家分配的外部端口

注意: Caddy 申请公开 TLS 证书通常仍需要域名的 `80/443` 可访问。只有高位外部端口的 NAT VPS, 需要先确认服务商端口映射或证书方案可用。

例如 VPS 内部端口 `3000` 映射到外部端口 `12345`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/install.sh) example.com 4 "" mypath 3000 12345
```

## 卸载

标准卸载:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) --remove
apt purge -y caddy
rm -f /etc/apt/sources.list.d/caddy-stable.list
rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg
apt autoremove -y
```

如果是空 VPS, 想清理后重新安装, 可以额外清掉旧配置和占用端口的旧进程:

```bash
systemctl stop caddy 2>/dev/null
systemctl stop v2ray 2>/dev/null
systemctl stop xray 2>/dev/null
pkill -f xray 2>/dev/null
pkill -f v2ray 2>/dev/null

rm -rf /etc/caddy
rm -rf /usr/local/etc/v2ray
rm -rf /usr/local/etc/xray
rm -rf /var/log/v2ray
rm -rf /var/log/xray

ss -lntp | grep ':3000'
```

如果最后一条没有输出, 表示 `3000` 端口已经空出来, 可以重新安装。NAT VPS 示例:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/install.sh) node.mailx.de5.net 4 "" x2050 3000 16423
```

安装完成后检查 `3000` 应该由 Caddy 监听:

```bash
ss -lntp | grep ':3000'
systemctl status caddy --no-pager
```
