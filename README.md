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
bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/install.sh) 域名 网络栈 UUID path 本机监听端口 外部端口 节点名称
```

参数说明:

- `域名`: 例如 `example.com`
- `网络栈`: `4` 表示 IPv4, `6` 表示 IPv6, 留空则脚本自动判断
- `UUID`: 留空则使用脚本生成的默认 UUID
- `path`: WebSocket 分流路径, 不要带 `/`
- `本机监听端口`: Caddy 在 VPS 内部监听的端口, 普通 VPS 默认 `443`; 内外端口映射时可填内部端口, 例如 `3000`
- `外部端口`: 客户端节点里填写的端口, 普通 VPS 默认等于本机监听端口; 内外端口映射时填商家分配的外部端口
- `节点名称`: 客户端里显示的节点名, 例如 `US-NODE-01` 或 `CA-NODE-01`; 留空则脚本根据公网 IP 地理库粗略生成一个默认名称

注意: Caddy 申请公开 TLS 证书通常仍需要域名的 `80/443` 可访问。只有高位外部端口的 NAT VPS, 需要先确认服务商端口映射或证书方案可用。

注意: IP 地理库不一定等于真实机房地址。如果你知道 VPS 实际位置, 建议手动传入 `节点名称`。

例如 VPS 内部端口 `3000` 映射到外部端口 `12345`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/install.sh) example.com 4 "" mypath 3000 12345 CA-NODE-01
```

## NAT VPS + Cloudflare DNS-01

如果 NAT VPS 没有标准外部 `80/443` 端口, 可以用 Cloudflare DNS-01 自动申请证书。先在 Cloudflare 创建 API Token:

- 权限: `Zone - DNS - Edit`, `Zone - Zone - Read`
- 范围: 选择托管节点域名的 zone, 例如 `example.com`

然后在 VPS 上设置环境变量后安装:

```bash
export CF_Token="你的Cloudflare_API_Token"
export CF_Zone_ID="你的Cloudflare_Zone_ID"

bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/install.sh) node.example.com 4 "" mypath 3000 12345 CA-NODE-01
```

脚本检测到 `CF_Token` 和 `CF_Zone_ID` 后, 会自动安装 acme.sh, 通过 DNS-01 申请证书, 并让 Caddy 使用证书文件。不要把真实 API Token 写进公开仓库或发给别人。

## 卸载

交互确认后卸载:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/uninstall.sh)
```

跳过确认直接卸载:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/uninstall.sh) --yes
```

卸载后如果准备重装, 确认 NAT 内部端口已经空出来:

```bash
ss -lntp | grep ':3000'
```

如果最后一条没有输出, 可以重新安装。NAT VPS 示例:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/install.sh) node.example.com 4 "" mypath 3000 12345 CA-NODE-01
```

安装完成后检查 `3000` 应该由 Caddy 监听:

```bash
ss -lntp | grep ':3000'
systemctl status caddy --no-pager
```

## NVIDIA AIR 保活

如果 VPS 运行在 NVIDIA AIR simulation 上, 可以安装 `nvps` 定时延后 `sleep_at`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/X012C/v2ray_wsss/main/nvps.sh) install
```

安装时根据提示输入:

- `NVIDIA AIR API Key`
- `Simulation ID`

安装后可直接使用:

```bash
nvps status
nvps logs
nvps next
nvps run
nvps config
nvps uninstall
```

默认开机 5 分钟后运行一次, 之后每 12 小时运行一次, 每次把 simulation 的 `sleep_at` 推到 71 小时后。API Key 会保存到 `/etc/nvps.env`, 权限为 `600`。
