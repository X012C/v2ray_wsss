# v2ray_wsss

VLESS / VMesss over WebSocket + TLS 一键部署脚本，默认使用 Caddy 作为前置反代。

## 安装

```bash
apt update
apt install -y curl
bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/install.sh)
```

带参数安装:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/install.sh) 域名 网络栈 UUID path 本机监听端口 外部端口 节点名称
```

参数:

- `域名`: 节点域名
- `网络栈`: `4` / `6`, 留空自动判断
- `UUID`: 留空使用脚本默认值
- `path`: WebSocket 路径, 不带 `/`
- `本机监听端口`: Caddy 在本机监听的端口, 默认 `443`
- `外部端口`: 客户端连接端口, NAT 场景可与本机监听端口不同
- `节点名称`: 客户端显示名称, 留空时按公网 IP 粗略生成

NAT 示例:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/install.sh) node.example.com 4 "" mypath 3000 12345 CA-NODE-01
```

## DNS-01 证书

如果机器没有可用的公网 `80/443`, 可提前配置 Cloudflare DNS-01:

```bash
export CF_Token="Cloudflare_API_Token"
export CF_Zone_ID="Cloudflare_Zone_ID"
```

Token 需要具备当前 zone 的 DNS 编辑权限。脚本检测到以上变量后，会通过 acme.sh 申请证书，并让 Caddy 使用本地证书文件。

## Cloudflare CDN

NAT 高位端口可以通过 Cloudflare Origin Rule 回源:

```text
客户端:443 -> Cloudflare -> 外部端口 -> 本机监听端口 -> Caddy -> V2Ray
```

要点:

- 源站证书建议使用 DNS-01
- Cloudflare SSL/TLS 使用 `Full (strict)`
- DNS 记录开启橙云
- Origin Rule 将回源端口改为实际外部端口
- 客户端端口改为 `443`, `SNI` / `Host` / `Path` 保持原值

不建议使用 `Flexible`，它不适合源站已经启用 HTTPS / WSS 的场景。

## 卸载

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/uninstall.sh)
```

跳过确认:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/uninstall.sh) --yes
```

## NVIDIA AIR 保活

可选安装 `nvps`，用于定时延后 NVIDIA AIR simulation 的 `sleep_at`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/nvps.sh) install
```

常用命令:

```bash
nvps status
nvps logs
nvps next
nvps run
nvps config
nvps uninstall
```

默认开机后运行一次，之后每 12 小时运行一次。配置保存在 `/etc/nvps.env`。
