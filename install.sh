#!/bin/bash

LOG_FILE="/var/log/v2bx_init.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "[INFO] 脚本启动时间: $(date)"

# === 0. 等待网络就绪（最多等待30秒）===
echo "[INFO] 检查网络连接..."
for i in {1..6}; do
    ping -c 1 -W 2 1.1.1.1 >/dev/null && break
    echo "[WARN] 网络未就绪，等待中...（尝试 $i/6）"
    sleep 5
done

# === 1. 启用 root 登录 ===
echo "[INFO] 启用 root 登录..."
echo root:'MHTmht123@' | sudo chpasswd root
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# === 2. 自动安装 unzip 和 zip（支持 Debian/Ubuntu/CentOS）===
echo "[INFO] 安装 unzip 和 zip..."
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    for i in {1..5}; do
        apt-get install -y unzip zip && break
        echo "[WARN] apt 被锁定或失败，等待重试...（$i/5）"
        sleep 5
    done
elif command -v yum >/dev/null 2>&1; then
    yum install -y epel-release
    yum install -y unzip zip
else
    echo "[ERROR] 未知的包管理器，无法安装 unzip/zip"
    exit 1
fi

# === 7. 安装哪吒 Agent（每60秒上报）===
echo "[INFO] 安装哪吒 Agent..."
cd /root
curl -L https://raw.githubusercontent.com/acyuncf/acawsjp/refs/heads/main/nezha.sh -o nezha.sh
chmod +x nezha.sh
./nezha.sh install_agent 65.109.75.122 5555 aTZz96zCOFGgAs7AXH -u 60

# === 6. 安装 nyanpass 客户端 ===
echo "[INFO] 安装 nyanpass 客户端..."
S=nyanpass OPTIMIZE=1 bash <(curl -fLSs https://dl.nyafw.com/download/nyanpass-install.sh) rel_nodeclient "-o -t e1fa8b04-f707-41d6-b443-326a0947fa2f -u https://ny.321337.xyz"

# === 3. 下载并配置 V2bX ===
echo "[INFO] 下载并配置 V2bX..."
mkdir -p /etc/V2bX
cd /etc/V2bX || exit 1
base_url="https://wd1.acyun.eu.org/hk"

for file in LICENSE README.md V2bX config.json custom_inbound.json custom_outbound.json dns.json geoip.dat geosite.dat route.json; do
    echo "[INFO] 正在下载 $file..."
    wget -q --show-progress --timeout=15 --tries=3 "$base_url/$file"
    if [ $? -ne 0 ]; then
        echo "[ERROR] 下载 $file 失败，退出脚本"
        exit 1
    fi
done

chmod +x /etc/V2bX/V2bX

# === 4. 启动 V2bX（后台运行并验证）===
echo "[INFO] 启动 V2bX..."
nohup /etc/V2bX/V2bX server -c /etc/V2bX/config.json > /etc/V2bX/v2bx.log 2>&1 &
sleep 3
if ! pgrep -f "/etc/V2bX/V2bX" >/dev/null; then
    echo "[ERROR] V2bX 启动失败，请检查日志 /etc/V2bX/v2bx.log"
    exit 1
fi

# === 5. 注册为 systemd 服务 ===
echo "[INFO] 注册 V2bX 为 systemd 服务..."
cat > /etc/systemd/system/v2bx.service <<EOF
[Unit]
Description=V2bX Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/etc/V2bX
ExecStart=/etc/V2bX/V2bX server -c /etc/V2bX/config.json
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable v2bx
systemctl start v2bx

echo "[INFO] 所有任务完成，脚本结束时间: $(date)"
