#!/bin/bash
apt-get install curl wget net-tools unzip -y
mkdir -p /root/tmp/
mkdir -p /etc/xray/
mkdir -p /etc/caddy/
function get_latest_version() {
    local owner=$1
    local repository=$2
    local retries=5
    local counter=0
    while [ $counter -lt $retries ]; do
        local release_info=$(curl -s "https://api.github.com/repos/$owner/$repository/releases/latest")
        local tag_name=$(echo "$release_info" | grep -o '"tag_name": ".*"' | cut -d'"' -f4)

        if [ -n "$tag_name" ]; then
            echo "$tag_name"
            return 0
        fi
        counter=$((counter + 1))
        sleep 1
    done
    echo "无法获取最新版本号"
    exit 1
}
function downloadandinstallxray(){
version=$(get_latest_version "XTLS" "Xray-core")
echo $version
url="https://github.com/XTLS/Xray-core/releases/download/"$version"/Xray-linux-64.zip"
wget -O /root/tmp/Xray.zip $url
unzip -o /root/tmp/Xray.zip -d /etc/xray/
chmod +x /etc/xray/xray
}
function downloadandinstallcaddy(){
version=$(get_latest_version "caddyserver" "caddy")
version_1=${version//v}
echo "$version_1"
url="https://github.com/caddyserver/caddy/releases/download/"$version"/caddy_"$version_1"_linux_amd64.tar.gz"
echo url
wget -O /root/tmp/caddy.tar.gz $url
tar -xvf /root/tmp/caddy.tar.gz -C /etc/caddy/
chmod +x /etc/caddy/caddy
}
function configcaddyfile(){
cat << EOF > "/etc/caddy/Caddyfile"
$domain {
	@grpc {
		protocol grpc
		path /data/*
	}
	reverse_proxy @grpc 127.0.0.1:8797 {
		transport http {
			versions h2c
		}
	}
	root * /var/www
	file_server
}
EOF
mkdir -p /var/www
echo "hello world">/var/www/index.html
}
function installxrayservice(){
cat << EOF > "/lib/systemd/system/xray.service"
[Unit]
Description=xray
After=network.target
[Service]
ExecStart=/etc/xray/xray -c /etc/xray/config.json
Restart=always
[Install]
WantedBy=multi-user.target
EOF
}
function installcaddyservice(){
cat << EOF > "/lib/systemd/system/caddy.service"
[Unit]
Description=caddy
After=network.target
[Service]
ExecStart=/etc/caddy/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/etc/caddy/caddy reload --config /etc/caddy/Caddyfile --force
Restart=always
[Install]
WantedBy=multi-user.target
EOF
}

function xrayconf(){
UUID=$1
cat <<EOF > "/etc/xray/config.json"
{
  "log": {
    "loglevel": "none"
  },
  "inbounds": [
    {
      "protocol": "vless",
      "listen": "127.0.0.1",
      "port": 8797,
      "settings": {
        "clients": [
          {
            "id": "$UUID"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "data"
        },
        "security": "none"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF
}
echo "正在开启BBR"
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
echo "请查看BBR是否开启"
lsmod | grep bbr
sleep 3
read -p "请输入域名，例如123.com：" domain
if [ -z "$domain" ]; then
  echo "你需要输入一个域名"
  exit 2
fi
echo "你输入的域名是：$domain"
sleep 3
read -p "请输入uuid，例如66ec3610-f4aa-6464-d056-3406159ee48b： " uid
if [ -z "$uid" ]; then
  uid="66ec3610-f4aa-6464-d056-3406159ee48b"
fi
echo -e "正在安装xray\n"
sleep 1
downloadandinstallxray
echo -e "正在安装caddy\n"
sleep 1
downloadandinstallcaddy
sleep 1
echo -e "正在配置caddy\n"
configcaddyfile
echo -e "正在配置xray\n"
xrayconf $uid
echo -e "安装服务中\n"
installxrayservice
installcaddyservice
sleep 3
systemctl start xray
sleep 3
systemctl status xray
sleep 3
systemctl start caddy
sleep 3
systemctl status caddy
systemctl enable xray
systemctl enable caddy
rm -rf /root/tmp/
echo -e 'V2Ray/XRay 协议:vless\n服务器地址:'$domain'\n端口:443\nUUID:'$uid'\nVLESS 加密:none\n传输协议:grpc\nserviceName:data\nTLS:Ture\nTLS Host:'$domain


