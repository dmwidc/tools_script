#!/bin/bash

# ============================================================================
# 脚本用途：这是一个用于Azure云服务器快速开启root ssh登录权限的脚本（含关闭SELinux）
# 系统要求：AlmaLinux 9/10
# ============================================================================

# 1. 权限检查
if [ "$EUID" -ne 0 ]; then
    echo "错误：请切换至 root 身份后再运行该脚本！"
    exit 1
fi

# 0. 操作系统版本判断
if [ -f /etc/os-release ]; then
    . /etc/os-release
    VERSION_ID_SHORT=$(echo $VERSION_ID | cut -d'.' -f1)
    if [[ "$ID" != "almalinux" ]] || [[ "$VERSION_ID_SHORT" != "9" && "$VERSION_ID_SHORT" != "10" ]]; then
        echo "错误：本脚本仅支持 AlmaLinux 9 或 10。当前系统：$ID $VERSION_ID"
        exit 1
    fi
else
    echo "无法获取系统发行版信息，退出。"
    exit 1
fi

echo "--- 系统检查通过：AlmaLinux $VERSION_ID_SHORT ---"

# 2. 设置密码（用于 root 和 azureuser）
echo "--- 步骤 2: 设置登录密码 ---"
while true; do
    # 强制从终端读取输入
    read -s -p "请输入要设置的root密码: " NEW_PASS < /dev/tty
    echo
    read -s -p "请再次输入确认root密码: " NEW_PASS_CONFIRM < /dev/tty
    echo
    if [ "$NEW_PASS" == "$NEW_PASS_CONFIRM" ] && [ -n "$NEW_PASS" ]; then
        break
    else
        echo "两次root密码不一致或密码为空，请重新输入。"
    fi
done

# 修改 root 密码
echo "root:$NEW_PASS" | chpasswd
echo "Root 密码设置成功！"

# 3. 同步 azureuser 密码
echo "--- 步骤 3: 同步默认用户密码 ---"
if id "azureuser" &>/dev/null; then
    echo "检测到 azureuser 用户，正在同步密码..."
    echo "azureuser:$NEW_PASS" | chpasswd
    AZURE_USER_STATUS="密码已同步"
else
    AZURE_USER_STATUS="未检测到该用户"
fi

# 4. 关闭 SELinux（RHEL 系特有，否则可能干扰登录/服务行为）
echo "--- 步骤 4: 关闭 SELinux ---"
SELINUX_CONF="/etc/selinux/config"
if command -v getenforce &>/dev/null; then
    CURRENT_SELINUX=$(getenforce)
    # 运行时立即切换为 permissive（disabled 状态需重启才能完全生效）
    if [ "$CURRENT_SELINUX" != "Disabled" ]; then
        setenforce 0 2>/dev/null
    fi
    # 持久化：写入配置文件，重启后保持 disabled
    if [ -f "$SELINUX_CONF" ]; then
        cp "$SELINUX_CONF" "${SELINUX_CONF}.bak"
        sed -i 's/^SELINUX=.*/SELINUX=disabled/g' "$SELINUX_CONF"
        SELINUX_STATUS="已关闭（运行时已设为 permissive，重启后永久 disabled）"
    else
        SELINUX_STATUS="运行时已设为 permissive（未找到配置文件，无法持久化）"
    fi
else
    SELINUX_STATUS="系统未启用 SELinux，无需处理"
fi

# 5. 修改 SSH 配置
echo "--- 步骤 5: 修改 SSH 配置 ---"
SSHD_CONF="/etc/ssh/sshd_config"
[ -f "$SSHD_CONF" ] && cp "$SSHD_CONF" "${SSHD_CONF}.bak"

# 确保配置项存在并正确设置（主配置文件）
# 允许密码登录
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' "$SSHD_CONF"
# 允许 root 登录
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' "$SSHD_CONF"

# 关键：RHEL/Azure 镜像通常通过 Include 引入 drop-in 配置，且“首次匹配优先”，
# 其中 cloud-init 往往写有 PasswordAuthentication no，会覆盖主配置。这里一并修正。
SSHD_CONF_DIR="/etc/ssh/sshd_config.d"
if [ -d "$SSHD_CONF_DIR" ]; then
    for f in "$SSHD_CONF_DIR"/*.conf; do
        [ -f "$f" ] || continue
        sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' "$f"
        sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' "$f"
    done
    # 再写一个排序最靠前的 drop-in 作为兜底，确保我们的设置优先生效
    cat > "$SSHD_CONF_DIR/00-enable-root-login.conf" <<'EOF'
PasswordAuthentication yes
PermitRootLogin yes
EOF
fi

# 6. 重启服务并输出结果
echo "--- 步骤 6: 重启 SSH 服务 ---"
# RHEL 系服务名为 sshd
systemctl restart sshd

echo "================================================"
echo "配置完成！详细信息如下："
echo "------------------------------------------------"
echo "操作系统：AlmaLinux $VERSION_ID"
echo "SSH 状态：已开启 root 密码登录"
echo "SELinux：$SELINUX_STATUS"
echo "Root 密码：$NEW_PASS"
echo "Azure 账户 (azureuser)：$AZURE_USER_STATUS"
if [[ "$AZURE_USER_STATUS" != "未检测到该用户" ]]; then
    echo "Azure 账户密码：$NEW_PASS"
fi
echo "================================================"
echo "提示：若需 SELinux 完全进入 disabled 状态，请重启系统（reboot）。"
