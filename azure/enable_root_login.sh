#!/bin/bash

# ============================================================================
# 脚本用途：这是一个用于Azure云服务器快速开启root ssh登录权限的脚本
# 系统要求：Debian12/13
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
    if [[ "$ID" != "debian" ]] || [[ "$VERSION_ID_SHORT" != "12" && "$VERSION_ID_SHORT" != "13" ]]; then
        echo "错误：本脚本仅支持 Debian 12 或 13。当前系统：$ID $VERSION_ID"
        exit 1
    fi
else
    echo "无法获取系统发行版信息，退出。"
    exit 1
fi

echo "--- 系统检查通过：Debian $VERSION_ID_SHORT ---"

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

# 3. 同步 azureuser 密码
echo "--- 步骤 3: 同步默认用户密码 ---"
if id "azureuser" &>/dev/null; then
    echo "检测到 azureuser 用户，正在同步密码..."
    echo "azureuser:$NEW_PASS" | chpasswd
    AZURE_USER_STATUS="密码已同步"
else
    AZURE_USER_STATUS="未检测到该用户"
fi

# 4. 修改 SSH 配置
echo "--- 步骤 4: 修改 SSH 配置 ---"
SSHD_CONF="/etc/ssh/sshd_config"
[ -f "$SSHD_CONF" ] && cp "$SSHD_CONF" "${SSHD_CONF}.bak"

# 确保配置项存在并正确设置
# 允许密码登录
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' "$SSHD_CONF"
# 允许 root 登录
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' "$SSHD_CONF"

# 5. 重启服务并输出结果
echo "--- 步骤 5: 重启 SSH 服务 ---"
systemctl restart ssh

echo "================================================"
echo "配置完成！详细信息如下："
echo "------------------------------------------------"
echo "操作系统：Debian $VERSION_ID"
echo "SSH 状态：已开启 root 密码登录"
echo "Root 密码：$NEW_PASS"
echo "Azure 账户 (azureuser)：$AZURE_USER_STATUS"
if [[ "$AZURE_USER_STATUS" != "未检测到该用户，跳过" ]]; then
    echo "Azure 账户密码：$NEW_PASS"
fi
echo "================================================"

