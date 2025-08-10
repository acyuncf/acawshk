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

# === 2. 自动安装 unzip、zip、socat（含重试）===
echo "[INFO] 安装 unzip/zip/socat..."
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    for i in {1..5}; do
        apt-get install -y unzip zip socat && break
        echo "[WARN] apt 被锁定或失败，等待重试...($i/5)"
        sleep 5
    done
elif command -v yum >/dev/null 2>&1; then
    yum install -y epel-release
    yum install -y unzip zip socat
else
    echo "[ERROR] 未知的包管理器，无法自动安装必需依赖"
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

# === 2.1 开放本机防火墙端口（若存在防火墙）===
echo "[INFO] 开放 41243/tcp（如果启用防火墙）..."
if command -v ufw >/dev/null 2>&1; then
    ufw allow 41243/tcp || true
elif systemctl is-active --quiet firewalld 2>/dev/null; then
    firewall-cmd --permanent --add-port=41243/tcp || true
    firewall-cmd --reload || true
fi

# === 2.2 创建端口转发脚本与 systemd 服务 ===
echo "[INFO] 创建端口转发服务（0.0.0.0:41243 -> sg13.111165.xyz:41243）..."
cat >/usr/local/bin/port_forward_41243.sh <<'EOF'
#!/bin/bash
LOG="/var/log/port_forward_41243.log"
exec >> "$LOG" 2>&1
echo "[INFO] port_forward_41243 启动于 $(date)"
# 使用循环保证异常退出后自动重启
while true; do
    # -d -d 输出诊断日志；reuseaddr 避免 TIME_WAIT 绑定失败；fork 多并发
    socat -d -d TCP-LISTEN:41243,reuseaddr,fork TCP:sg13.111165.xyz:41243
    code=$?
    echo "[WARN] socat 退出（code=$code），2s 后重启 $(date)"
    sleep 2
done
EOF
chmod +x /usr/local/bin/port_forward_41243.sh

cat >/etc/systemd/system/port-forward-41243.service <<'EOF'
[Unit]
Description=TCP Forward 0.0.0.0:41243 -> sg13.111165.xyz:41243
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/port_forward_41243.sh
Restart=always
RestartSec=2
# 提高文件描述符上限，避免高并发报错
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now port-forward-41243

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
