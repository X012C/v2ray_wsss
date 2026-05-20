# 等待1秒, 避免curl下载脚本的打印与脚本本身的显示冲突, 吃掉了提示用户按回车继续的信息
sleep 1

echo -e "                     _ ___                   \n ___ ___ __ __ ___ _| |  _|___ __ __   _ ___ \n|-_ |_  |  |  |-_ | _ |   |- _|  |  |_| |_  |\n|___|___|  _  |___|___|_|_|___|  _  |___|___|\n        |_____|               |_____|        "
red='\e[91m'
green='\e[92m'
yellow='\e[93m'
magenta='\e[95m'
cyan='\e[96m'
none='\e[0m'

error() {
    echo -e "\n$red 输入错误! $none\n"
}

is_valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

sanitize_node_name() {
    echo -n "$1" | tr ' /#?&' '_____' | sed -E 's/[^A-Za-z0-9._-]/_/g; s/_+/_/g; s/^_//; s/_$//'
}

detect_node_location() {
    local lookup_ip="$1"
    local geo_json
    local country_code
    local city
    local region

    [ -z "$lookup_ip" ] && return

    geo_json=$(curl -4s --max-time 4 "https://ipapi.co/${lookup_ip}/json/" 2>/dev/null)
    country_code=$(echo "$geo_json" | sed -n 's/.*"country_code"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
    city=$(echo "$geo_json" | sed -n 's/.*"city"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
    region=$(echo "$geo_json" | sed -n 's/.*"region_code"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)

    if [[ -z "$country_code" ]]; then
        geo_json=$(curl -4s --max-time 4 "https://ipinfo.io/${lookup_ip}/json" 2>/dev/null)
        country_code=$(echo "$geo_json" | sed -n 's/.*"country"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
        city=$(echo "$geo_json" | sed -n 's/.*"city"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
        region=$(echo "$geo_json" | sed -n 's/.*"region"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
    fi

    country_code=$(echo -n "$country_code" | tr '[:lower:]' '[:upper:]')
    city=$(sanitize_node_name "$city")
    region=$(sanitize_node_name "$region")

    if [[ -n "$country_code" && -n "$city" ]]; then
        echo "${country_code}-${city}"
    elif [[ -n "$country_code" && -n "$region" ]]; then
        echo "${country_code}-${region}"
    elif [[ -n "$country_code" ]]; then
        echo "${country_code}"
    fi
}

install_dns01_cert_if_configured() {
    if [[ -z "$CF_Token" || -z "$CF_Zone_ID" ]]; then
        return 0
    fi

    echo
    echo -e "$yellow检测到 Cloudflare DNS-01 配置, 使用 DNS 验证申请证书$none"
    echo "----------------------------------------------------------------"

    if [[ ! -x "$HOME/.acme.sh/acme.sh" ]]; then
        curl https://get.acme.sh | sh -s email=admin@example.com
    fi

    if [[ ! -x "$HOME/.acme.sh/acme.sh" ]]; then
        echo -e "$red acme.sh 安装失败, 请检查网络后重试$none"
        exit 1
    fi

    export CF_Token
    export CF_Zone_ID

    "$HOME/.acme.sh/acme.sh" --set-account-conf --accountconf "$HOME/.acme.sh/account.conf" --name CF_Token --value "$CF_Token"
    "$HOME/.acme.sh/acme.sh" --set-account-conf --accountconf "$HOME/.acme.sh/account.conf" --name CF_Zone_ID --value "$CF_Zone_ID"

    "$HOME/.acme.sh/acme.sh" --issue --dns dns_cf -d "$domain" --server letsencrypt

    mkdir -p "/etc/caddy/certs/$domain"
    "$HOME/.acme.sh/acme.sh" --install-cert -d "$domain" \
        --key-file "/etc/caddy/certs/$domain/key.pem" \
        --fullchain-file "/etc/caddy/certs/$domain/fullchain.pem" \
        --reloadcmd "systemctl reload caddy 2>/dev/null || true"

    chown -R caddy:caddy /etc/caddy/certs
    chmod 600 "/etc/caddy/certs/$domain/key.pem"
    chmod 644 "/etc/caddy/certs/$domain/fullchain.pem"

    caddy_tls_line="tls /etc/caddy/certs/$domain/fullchain.pem /etc/caddy/certs/$domain/key.pem"
}

warn() {
    echo -e "\n$yellow $1 $none\n"
}

pause() {
    read -rsp "$(echo -e "按 $green Enter 回车键 $none 继续....或按 $red Ctrl + C $none 取消.")" -d $'\n'
    echo
}

# 确保有 curl 和 wget
apt-get -y install curl wget -qq

# 说明
echo
echo -e "$yellow此脚本仅兼容于Debian 10+系统. 如果你的系统不符合,请Ctrl+C退出脚本$none"
echo -e "可以去 ${cyan}https://github.com/crazypeace/v2ray_wss${none} 查看脚本整体思路和关键命令, 以便针对你自己的系统做出调整."
echo -e "有问题加群 ${cyan}https://t.me/+q5WPfGjtwukyZjhl${none}"
echo "本脚本支持带参数执行, 在参数中输入域名, 网络栈, UUID, path, 本机监听端口, 外部端口, 节点名称. 详见GitHub."
echo "----------------------------------------------------------------"

# 本机 IP
InFaces=($(ls /sys/class/net/ | grep -E '^(eth|ens|eno|esp|enp|venet|vif)'))     # 查本机的网卡

for i in "${InFaces[@]}"; do  # 从网口循环获取IP
    # 增加超时时间, 以免在某些网络环境下请求IPv6等待太久
    Public_IPv4=$(curl -4s --interface "$i" -m 2 https://www.cloudflare.com/cdn-cgi/trace | grep -oP "ip=\K.*$")
    Public_IPv6=$(curl -6s --interface "$i" -m 2 https://www.cloudflare.com/cdn-cgi/trace | grep -oP "ip=\K.*$")

    if [[ -n "$Public_IPv4" ]]; then  # 检查是否获取到IP地址
        IPv4="$Public_IPv4"
    fi
    if [[ -n "$Public_IPv6" ]]; then  # 检查是否获取到IP地址            
        IPv6="$Public_IPv6"
    fi
done

# 通过IP, host, 时区, 生成UUID. 重装脚本不改变, 不改变节点信息, 方便个人使用
uuidSeed=${IPv4}${IPv6}$(cat /proc/sys/kernel/hostname)$(timedatectl | awk '/Time zone/ {print $3}')
default_uuid=$(curl -sL https://www.uuidtools.com/api/generate/v3/namespace/ns:dns/name/${uuidSeed} | grep -oP '[^-]{8}-[^-]{4}-[^-]{4}-[^-]{4}-[^-]{12}')

# 如果你想使用纯随机的UUID
# default_uuid=$(cat /proc/sys/kernel/random/uuid)

# 随机的端口
default_port=$(shuf -i20001-65535 -n1)
default_web_port=443
has_args=0

# 执行脚本带参数
if [ $# -ge 1 ]; then
    has_args=1

    # 第1个参数是域名
    domain=${1}

    # 第2个参数是搭在ipv4还是ipv6上
    case ${2} in
    4)
        netstack=4
        ;;
    6)
        netstack=6
        ;;    
    *) # initial
        netstack="i"
        ;;    
    esac

    #第3个参数是UUID
    v2ray_id=${3}
    if [[ -z $v2ray_id ]]; then
        v2ray_id=${default_uuid}
    fi
        
    v2ray_port=${default_port}

    #第4个参数是path
    path=${4}
    if [[ -z $path ]]; then 
        path=$(echo -n $v2ray_id | tail -c 12)
    fi

    # 第5个参数是Caddy本机监听端口, 普通VPS默认443; NAT VPS可填内部映射端口, 如3000
    caddy_port=${5}
    if [[ -z $caddy_port ]]; then
        caddy_port=${default_web_port}
    elif ! is_valid_port "$caddy_port"; then
        echo -e "$red 本机监听端口错误Local listen port error: $caddy_port $none"
        exit 1
    fi

    # 第6个参数是客户端使用的外部端口, 普通VPS默认同本机监听端口; NAT VPS填商家分配的外部端口
    external_port=${6}
    if [[ -z $external_port ]]; then
        external_port=${caddy_port}
    elif ! is_valid_port "$external_port"; then
        echo -e "$red 外部端口错误External port error: $external_port $none"
        exit 1
    fi

    # 第7个参数是节点名称, 例如 US-NODE-01; 留空则根据IP地理库自动生成一个默认名称
    node_name=${7}

    proxy_site="https://zelikk.blogspot.com"

    echo -e "domain: ${domain}"
    echo -e "netstack: ${netstack}"
    echo -e "v2ray_id: ${v2ray_id}"
    echo -e "v2ray_port: ${v2ray_port}"
    echo -e "path: ${path}"
    echo -e "caddy_port: ${caddy_port}"
    echo -e "external_port: ${external_port}"
    echo -e "node_name: ${node_name}"
    echo -e "proxy_site: ${proxy_site}"
fi

pause

# 准备工作
apt update
apt install -y curl wget sudo jq qrencode net-tools lsof

# 指定安装V2ray v4.45.2版本
echo
echo -e "$yellow指定安装V2ray v4.45.2版本$none"
echo "----------------------------------------------------------------"
bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) --version 4.45.2

systemctl enable v2ray

# 更新 geoip.dat 和 geosite.dat
bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-dat-release.sh)

# 安装Caddy最新版本
echo
echo -e "$yellow安装Caddy最新版本$none"
echo "----------------------------------------------------------------"
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg --yes
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy

systemctl enable caddy

# 打开BBR
echo
echo -e "$yellow打开BBR$none"
echo "----------------------------------------------------------------"
sudo touch /etc/sysctl.d/99-bbr.conf
sudo sed -i '/^net\.core\.default_qdisc/d' /etc/sysctl.d/99-bbr.conf
sudo sed -i '/^net\.ipv4\.tcp_congestion_control/d' /etc/sysctl.d/99-bbr.conf
echo 'net.core.default_qdisc=fq' | sudo tee -a /etc/sysctl.d/99-bbr.conf
echo 'net.ipv4.tcp_congestion_control=bbr' | sudo tee -a /etc/sysctl.d/99-bbr.conf
echo 'tcp_bbr' | sudo tee /etc/modules-load.d/bbr.conf
sudo sysctl --system

# 旧写法
# sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
# sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
# echo "net.ipv4.tcp_congestion_control = bbr" >>/etc/sysctl.conf
# echo "net.core.default_qdisc = fq" >>/etc/sysctl.conf
# sysctl -p >/dev/null 2>&1

# 配置 VLESS_WebSocket_TLS 模式, 需要:域名, 分流path, 反代网站, V2ray内部端口, UUID
echo
echo -e "$yellow配置 VLESS_WebSocket_TLS 模式$none"
echo "----------------------------------------------------------------"

# UUID
if [[ -z $v2ray_id ]]; then
    while :; do
        echo -e "请输入 "$yellow"V2RayID"$none" "
        read -p "$(echo -e "(默认ID: ${cyan}${default_uuid}$none):")" v2ray_id
        [ -z "$v2ray_id" ] && v2ray_id=$default_uuid
        case $(echo -n $v2ray_id | sed -E 's/[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}//g') in
        "")
            echo
            echo
            echo -e "$yellow V2Ray ID = $cyan$v2ray_id$none"
            echo "----------------------------------------------------------------"
            echo
            break
            ;;
        *)
            error
            ;;
        esac
    done
fi

# V2ray内部端口
if [[ -z $v2ray_port ]]; then
    while :; do
        echo -e "请输入 "$yellow"V2Ray"$none" 端口 ["$magenta"1-65535"$none"], 不能选择 "$magenta"80"$none" 或 "$magenta"443"$none" 端口"
        read -p "$(echo -e "(默认端口port: ${cyan}${default_port}$none):")" v2ray_port
        [ -z "$v2ray_port" ] && v2ray_port=$default_port
        case $v2ray_port in
        80)
            echo
            echo " ...都说了不能选择 80 端口了咯....."
            error
            ;;
        443)
            echo
            echo " ..都说了不能选择 443 端口了咯....."
            error
            ;;
        [1-9] | [1-9][0-9] | [1-9][0-9][0-9] | [1-9][0-9][0-9][0-9] | [1-5][0-9][0-9][0-9][0-9] | 6[0-4][0-9][0-9][0-9] | 65[0-4][0-9][0-9] | 655[0-3][0-5])
            echo
            echo
            echo -e "$yellow 内部 V2Ray 端口Internal port = $cyan$v2ray_port$none"
            echo "----------------------------------------------------------------"
            echo
            break
            ;;
        *)
            error
            ;;
        esac
    done
fi

# Caddy本机监听端口
if [[ -z $caddy_port ]]; then
    while :; do
        echo -e "请输入 "$yellow"Caddy 本机监听端口"$none" ["$magenta"1-65535"$none"]"
        echo -e "普通VPS直接回车使用 ${cyan}443${none}; 如果是内外端口映射, 请填VPS内部端口, 例如 ${cyan}3000${none}"
        read -p "$(echo -e "(默认listen port: ${cyan}${default_web_port}$none):")" caddy_port
        [ -z "$caddy_port" ] && caddy_port=$default_web_port
        if is_valid_port "$caddy_port"; then
            echo
            echo
            echo -e "$yellow Caddy 本机监听端口Local listen port = $cyan$caddy_port$none"
            echo "----------------------------------------------------------------"
            echo
            break
        else
            error
        fi
    done
fi

# 节点外部端口
if [[ -z $external_port ]]; then
    while :; do
        echo -e "请输入 "$yellow"节点外部端口"$none" ["$magenta"1-65535"$none"]"
        echo -e "普通VPS直接回车使用本机监听端口; 如果是内外端口映射, 请填客户端连接时看到的外部端口"
        read -p "$(echo -e "(默认external port: ${cyan}${caddy_port}$none):")" external_port
        [ -z "$external_port" ] && external_port=$caddy_port
        if is_valid_port "$external_port"; then
            echo
            echo
            echo -e "$yellow 节点外部端口External port = $cyan$external_port$none"
            echo "----------------------------------------------------------------"
            echo
            break
        else
            error
        fi
    done
fi

# 节点名称
auto_node_location=$(detect_node_location "$ip")
if [[ -z "$auto_node_location" ]]; then
    auto_node_location=$(detect_node_location "$IPv4")
fi
if [[ -z "$auto_node_location" ]]; then
    auto_node_name="VLESS_WSS_${domain}"
else
    auto_node_name="${auto_node_location}-WSS"
fi

if [[ -z $node_name && "$has_args" == "1" ]]; then
    node_name=$auto_node_name
    echo -e "$yellow 节点名称Node name = ${cyan}${node_name}$none"
elif [[ -z $node_name ]]; then
    while :; do
        echo -e "请输入 "$yellow"节点名称"$none" , 例如 ${cyan}US-NODE-01${none} 或 ${cyan}CA-NODE-01${none}"
        echo "Input node name. It only changes the display name in clients."
        echo -e "脚本会根据公网IP粗略猜测地理位置, 但IP库可能不准; 不确定时建议手动填写。"
        read -p "$(echo -e "(默认node name: [${cyan}${auto_node_name}${none}]):")" node_name
        [[ -z $node_name ]] && node_name=$auto_node_name
        node_name=$(sanitize_node_name "$node_name")

        case $node_name in
        "")
            error
            ;;
        *)
            echo
            echo
            echo -e "$yellow 节点名称Node name = ${cyan}${node_name}$none"
            echo "----------------------------------------------------------------"
            echo
            break
            ;;
        esac
    done
else
    node_name=$(sanitize_node_name "$node_name")
fi

# 域名
if [[ -z $domain ]]; then
    while :; do
        echo
        echo -e "请输入一个 ${magenta}正确的域名${none} Input your domain"
        read -p "(例如: mydomain.com): " domain
        [ -z "$domain" ] && error && continue
        echo
        echo
        echo -e "$yellow 你的域名Domain = $cyan$domain$none"
        echo "----------------------------------------------------------------"
        break
    done
fi

# 网络栈
if [[ -z $netstack ]]; then
    echo -e "如果你的小鸡是${magenta}双栈(同时有IPv4和IPv6的IP)${none}，请选择你把v2ray搭在哪个'网口'上"
    echo "如果你不懂这段话是什么意思, 请直接回车"
    read -p "$(echo -e "Input ${cyan}4${none} for IPv4, ${cyan}6${none} for IPv6:") " netstack
    if [[ $netstack == "4" ]]; then
        domain_resolve=$(curl -sH 'accept: application/dns-json' "https://cloudflare-dns.com/dns-query?name=$domain&type=A" | jq -r '.Answer[0].data')
    elif [[ $netstack == "6" ]]; then 
        domain_resolve=$(curl -sH 'accept: application/dns-json' "https://cloudflare-dns.com/dns-query?name=$domain&type=AAAA" | jq -r '.Answer[0].data')
    else
        domain_resolve=$(curl -sH 'accept: application/dns-json' "https://cloudflare-dns.com/dns-query?name=$domain&type=A" | jq -r '.Answer[0].data')
        if [[ "$domain_resolve" != "null" ]]; then
            netstack="4"
        else
            domain_resolve=$(curl -sH 'accept: application/dns-json' "https://cloudflare-dns.com/dns-query?name=$domain&type=AAAA" | jq -r '.Answer[0].data')            
            if [[ "$domain_resolve" != "null" ]]; then
                netstack="6"
            fi
        fi
    fi

    # 本机 IP
    # 在脚本的一开头就检测了本机IP
    if [[ $netstack == "4" ]]; then
        ip=$IPv4
    elif [[ $netstack == "6" ]]; then
        ip=$IPv6
    else
        ip=$IPv4,$IPv6
    fi

    if [[ $domain_resolve != $ip ]]; then
        echo
        echo -e "$red 域名解析错误Domain resolution error....$none"
        echo
        echo -e " 你的域名: $yellow$domain$none 未解析到: $cyan$ip$none"
        echo
        if [[ $domain_resolve != "null" ]]; then
            echo -e " 你的域名当前解析到: $cyan$domain_resolve$none"
        else
            echo -e " $red检测不到域名解析Domain not resolved $none "
        fi
        echo
        echo -e "备注...如果你的域名是使用$yellow Cloudflare $none解析的话... 在 DNS 设置页面, 请将$yellow代理状态$none设置为$yellow仅限DNS$none, 小云朵变灰."
        echo "Notice...If you use Cloudflare to resolve your domain, on 'DNS' setting page, 'Proxy status' should be 'DNS only' but not 'Proxied'."
        echo
        exit 1
    else
        echo
        echo
        echo -e "$yellow 域名解析 = ${cyan}我确定已经有解析了$none"
        echo "----------------------------------------------------------------"
        echo
    fi
fi

# 分流path
if [[ -z $path ]]; then
    default_path=$(echo -n $v2ray_id | tail -c 12)
    while :; do
        echo -e "请输入想要 ${magenta} 用来分流的路径 $none , 例如 /v2raypath , 那么只需要输入 v2raypath 即可"
        echo "Input the WebSocket path for V2ray"
        read -p "$(echo -e "(默认path: [${cyan}${default_path}$none]):")" path
        [[ -z $path ]] && path=$default_path

        case $path in
        *[/$]*)
            echo
            echo -e " 由于这个脚本太辣鸡了..所以分流的路径不能包含$red / $none或$red $ $none这两个符号.... "
            echo
            error
            ;;
        *)
            echo
            echo
            echo -e "$yellow 分流的路径Path = ${cyan}/${path}$none"
            echo "----------------------------------------------------------------"
            echo
            break
            ;;
        esac
    done
fi

# 反代伪装网站
if [[ -z $proxy_site ]]; then
    while :; do
        echo -e "请输入 ${magenta}一个正确的 $none ${cyan}网址$none 用来作为 ${cyan}网站的伪装$none , 例如 https://zelikk.blogspot.com"
        echo "Input a camouflage site. When GFW visit your domain, the camouflage site will display."
        read -p "$(echo -e "(默认site: [${cyan}https://zelikk.blogspot.com${none}]):")" proxy_site
        [[ -z $proxy_site ]] && proxy_site="https://zelikk.blogspot.com"

        case $proxy_site in
        *[#$]*)
            echo
            echo -e " 由于这个脚本太辣鸡了..所以伪装的网址不能包含$red # $none或$red $ $none这两个符号.... "
            echo
            error
            ;;
        *)
            echo
            echo
            echo -e "$yellow 伪装的网址camouflage site = ${cyan}${proxy_site}$none"
            echo "----------------------------------------------------------------"
            echo
            break
            ;;
        esac
    done
fi

# 配置 /usr/local/etc/v2ray/config.json
echo
echo -e "$yellow配置 /usr/local/etc/v2ray/config.json$none"
echo "----------------------------------------------------------------"
cat >/usr/local/etc/v2ray/config.json <<-EOF
{ // vless + WebSocket + TLS
    "log": {
        "access": "/var/log/v2ray/access.log",
        "error": "/var/log/v2ray/error.log",
        "loglevel": "warning"
    },
    "inbounds": [
        // [inbound] 如果你想使用其它翻墙服务端如(HY2或者NaiveProxy)对接v2ray的分流规则, 那么取消下面一段的注释, 并让其它翻墙服务端接到下面这个socks 1080端口
        // {
        //     "listen":"127.0.0.1",
        //     "port":1080,
        //     "protocol":"socks",
        //     "sniffing":{
        //         "enabled":true,
        //         "destOverride":[
        //             "http",
        //             "tls"
        //         ]
        //     },
        //     "settings":{
        //         "auth":"noauth",
        //         "udp":false
        //     }
        // },
        {
            "listen": "127.0.0.1",
            "port": $v2ray_port,             // ***
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$v2ray_id",             // ***
                        "level": 1,
                        "alterId": 0
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "ws"
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls"
                ]
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIP"
            },
            "tag": "direct"
        },
        // [outbound]
{
    "protocol": "freedom",
    "settings": {
        "domainStrategy": "UseIPv4"
    },
    "tag": "force-ipv4"
},
{
    "protocol": "freedom",
    "settings": {
        "domainStrategy": "UseIPv6"
    },
    "tag": "force-ipv6"
},
{
    "protocol": "socks",
    "settings": {
        "servers": [{
            "address": "127.0.0.1",
            "port": 40000 //warp socks5 port
        }]
     },
    "tag": "socks5-warp"
},
        {
            "protocol": "blackhole",
            "settings": {},
            "tag": "blocked"
        }
    ],
    "dns": {
        "servers": [
            "8.8.8.8",
            "1.1.1.1",
            "2001:4860:4860::8888",
            "2606:4700:4700::1111",
            "localhost"
        ]
    },
    "routing": {
        "domainStrategy": "IPOnDemand",
        "rules": [
            {
                "type": "field",
                "ip": [
                    "0.0.0.0/8",
                    "10.0.0.0/8",
                    "100.64.0.0/10",
                    "127.0.0.0/8",
                    "169.254.0.0/16",
                    "172.16.0.0/12",
                    "192.0.0.0/24",
                    "192.0.2.0/24",
                    "192.168.0.0/16",
                    "198.18.0.0/15",
                    "198.51.100.0/24",
                    "203.0.113.0/24",
                    "::1/128",
                    "fc00::/7",
                    "fe80::/10"
                ],
                "outboundTag": "blocked"
            },
// [routing-rule]
//{
//     "type": "field",
//     "domain": ["geosite:google", "geosite:openai"],  // ***
//     "outboundTag": "force-ipv6"  // force-ipv6 // force-ipv4 // socks5-warp
//},
//{
//     "type": "field",
//     "domain": ["geosite:cn"],  // ***
//     "outboundTag": "force-ipv6"  // force-ipv6 // force-ipv4 // socks5-warp // blocked
//},
//{
//     "type": "field",
//     "ip": ["geoip:cn"],  // ***
//     "outboundTag": "force-ipv6"  // force-ipv6 // force-ipv4 // socks5-warp // blocked
//},
            {
                "type": "field",
                "protocol": ["bittorrent"],
                "outboundTag": "blocked"
            }
        ]
    }
}
EOF

# 配置 /etc/caddy/Caddyfile
echo
echo -e "$yellow配置 /etc/caddy/Caddyfile$none"
echo "----------------------------------------------------------------"
if [[ "$caddy_port" == "443" ]]; then
    caddy_site="$domain"
else
    caddy_site="${domain}:${caddy_port}"
fi
caddy_tls_line="tls Y3JhenlwZWFjZQ@gmail.com"
install_dns01_cert_if_configured
cat >/etc/caddy/Caddyfile <<-EOF
$caddy_site
{
    $caddy_tls_line
    encode gzip

#    多用户 多path
#    使用说明 https://zelikk.blogspot.com/2022/11/v2ray-vless-vmess-websocket-cdn-tls-caddy-v2.html
#    import Caddyfile.multiuser

    handle_path /$path {
        reverse_proxy localhost:$v2ray_port
    }
    handle {
        reverse_proxy $proxy_site {
            header_up Host {upstream_hostport}
        }
    }
}
EOF

# 多用户 多path
multiuser_path=""
user_number=10
while [ $user_number -gt 0 ]; do
    random_path=$(cat /proc/sys/kernel/random/uuid | tail -c 18)

    multiuser_path=${multiuser_path}"path /"${random_path}$'\n'

    user_number=$(($user_number - 1))
done

cat >/etc/caddy/Caddyfile.multiuser <<-EOF
@ws_path {
$multiuser_path
}

handle @ws_path {
    uri path_regexp /.* /
    reverse_proxy localhost:$v2ray_port
}
EOF

# 重启 V2Ray
echo
echo -e "$yellow重启 V2Ray$none"
echo "----------------------------------------------------------------"
service v2ray restart

# 重启 CaddyV2
echo
echo -e "$yellow重启 CaddyV2$none"
echo "----------------------------------------------------------------"
service caddy restart

echo
echo
echo "---------- V2Ray 配置信息 -------------"
echo -e "$green ---提示..这是 VLESS 服务器配置--- $none"
echo -e "$yellow 地址 (Address) = $cyan${domain}$none"
echo -e "$yellow 端口 (Port) = ${cyan}${external_port}${none}"
echo -e "$yellow 本机监听端口 (Local listen port) = ${cyan}${caddy_port}${none}"
echo -e "$yellow 节点名称 (Node name) = ${cyan}${node_name}${none}"
echo -e "$yellow 用户ID (User ID / UUID) = $cyan${v2ray_id}$none"
echo -e "$yellow 流控 (Flow) = ${cyan}空${none}"
echo -e "$yellow 加密 (Encryption) = ${cyan}none${none}"
echo -e "$yellow 传输协议 (Network) = ${cyan}ws$none"
echo -e "$yellow 伪装类型 (header type) = ${cyan}none$none"
echo -e "$yellow 伪装域名 (host) = ${cyan}${domain}$none"
echo -e "$yellow 路径 (path) = ${cyan}/${path}$none"
echo -e "$yellow 底层传输安全 (TLS) = ${cyan}tls$none"
echo
echo "---------- V2Ray VLESS URL ----------"
v2ray_vless_url="vless://${v2ray_id}@${domain}:${external_port}?encryption=none&security=tls&type=ws&host=${domain}&path=%2F${path}#${node_name}"
echo -e "${cyan}${v2ray_vless_url}${none}"
echo
sleep 3
echo "以下两个二维码完全一样的内容"
qrencode -t UTF8 $v2ray_vless_url
qrencode -t ANSI $v2ray_vless_url
echo
echo "---------- END -------------"
echo "以上节点信息保存在 ~/_v2ray_vless_url_ 中"

# 节点信息保存到文件中
echo $v2ray_vless_url > ~/_v2ray_vless_url_
echo "以下两个二维码完全一样的内容" >> ~/_v2ray_vless_url_
qrencode -t UTF8 $v2ray_vless_url >> ~/_v2ray_vless_url_
qrencode -t ANSI $v2ray_vless_url >> ~/_v2ray_vless_url_

# 是否切换为vmess协议
echo 
echo -e "切换成${magenta}Vmess${none}协议吗? Switch to ${magenta}Vmess${none} protocol?"
echo "如果你不懂这段话是什么意思, 请直接回车"
read -p "$(echo -e "(${cyan}y/N${none} Default No):") " switchVmess
if [[ -z "$switchVmess" ]]; then
    switchVmess='N'
fi
if [[ "$switchVmess" == [yY] ]]; then
    echo "${red}注意, 切换为vmess协议后, 刚刚的vless链接就失效了.${none}"
    pause
    
    # config.json文件中, 替换vless为vmess
    sed -i "s/vless/vmess/g" /usr/local/etc/v2ray/config.json
    service v2ray restart
    
    #生成vmess链接和二维码
    echo "---------- V2Ray Vmess URL ----------"
    v2ray_vmess_url="vmess://$(echo -n '{
"v": "2",
"ps": "'${node_name}'",
"add": "'${domain}'",
"port": "'${external_port}'",
"id": "'${v2ray_id}'",
"aid": "0",
"net": "ws",
"type": "none",
"host": "'${domain}'",
"path": "/'${path}'",
"tls": "tls"
}' | base64 -w 0)"

    echo -e "${cyan}${v2ray_vmess_url}${none}"
    echo "以下两个二维码完全一样的内容"
    qrencode -t UTF8 $v2ray_vmess_url
    qrencode -t ANSI $v2ray_vmess_url

    echo
    echo "---------- END -------------"
    echo "以上节点信息保存在 ~/_v2ray_vmess_url_ 中"

    echo $v2ray_vmess_url > ~/_v2ray_vmess_url_
    echo "以下两个二维码完全一样的内容" >> ~/_v2ray_vmess_url_
    qrencode -t UTF8 $v2ray_vmess_url >> ~/_v2ray_vmess_url_
    qrencode -t ANSI $v2ray_vmess_url >> ~/_v2ray_vmess_url_
    
elif [[ "$switchVmess" == [nN] ]]; then
    echo
else
    error
fi

# 如果是 IPv6 小鸡，用 WARP 创建 IPv4 出站
if [[ $netstack == "6" ]]; then
    echo
    echo -e "$yellow这是一个 IPv6 小鸡，用 WARP 创建 IPv4 出站$none"
    echo "Telegram电报是直接访问IPv4地址的, 需要IPv4出站的能力"    
    echo "----------------------------------------------------------------"
    pause

    # 安装 WARP IPv4
    curl -LO https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh
    yes "" | bash menu.sh 4

    # 重启 V2Ray
    echo
    echo -e "$yellow重启 V2Ray$none"
    echo "----------------------------------------------------------------"
    service v2ray restart

    # 重启 CaddyV2
    echo
    echo -e "$yellow重启 CaddyV2$none"
    echo "----------------------------------------------------------------"
    service caddy restart

# 如果是 IPv4 小鸡，用 WARP 创建 IPv6 出站
elif  [[ $netstack == "4" ]]; then
    echo
    echo -e "$yellow这是一个 IPv4 小鸡，用 WARP 创建 IPv6 出站$none"
    echo -e "有些热门小鸡用原生的IPv4出站访问Google需要通过人机验证, 可以通过修改config.json指定google流量走WARP的IPv6出站解决"
    echo -e "群组: ${cyan} https://t.me/+q5WPfGjtwukyZjhl ${none}"
    echo -e "教程: ${cyan} https://zelikk.blogspot.com/2022/03/racknerd-v2ray-cloudflare-warp--ipv6-google-domainstrategy-outboundtag-routing.html ${none}"
    echo -e "视频: ${cyan} https://youtu.be/Yvvm4IlouEk ${none}"
    echo "----------------------------------------------------------------"
    pause

    # 安装 WARP IPv6    
    curl -LO https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh
    yes "" | bash menu.sh 6

    # 重启 V2Ray
    echo
    echo -e "$yellow重启 V2Ray$none"
    echo "----------------------------------------------------------------"
    service v2ray restart

    # 重启 CaddyV2
    echo
    echo -e "$yellow重启 CaddyV2$none"
    echo "----------------------------------------------------------------"
    service caddy restart

fi
