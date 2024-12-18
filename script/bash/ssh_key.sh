#!/bin/bash


VERSION=1.0

RED='\033[0;91m'
GREEN='\033[0;92m'
CYAN='\033[0;96m'
PLAIN='\033[0m'

_red() { echo -e "${RED}$@${PLAIN}"; }
_green() { echo -e "${GREEN}$@${PLAIN}"; }
_cyan() { echo -e "${CYAN}$@${PLAIN}"; }
INFO() { _green '[INFO]' $@ ; }
EROR() { _red '[EROR]' $@ ; }

[ $EUID -ne 0 ] && SUDO=sudo;

# 默认变量==================
github_id=fyczx
ssh_port=54222

# =========================

_get_github_key() {
    if [[ -z "${github_id}" ]]; then
        read -t 10 -p "请输入github账户:" github_id
        [[ -z "${github_id}" ]] && (EROR "无效输入!" && _get_github_key)
    fi
    INFO "GitHub 账户: ${github_id}"
    INFO "通过 GitHub 获取密钥..."

    if [[ $EUID -eq 0 ]]; then
        pub_key="$(curl --max-time 2 -fsSL https://github.com/${github_id}.keys | sed -n '1p')"
    else
        pub_key="$(curl --max-time 2 -fsSL https://github.com/${github_id}.keys | sed -n '2p' )"
    fi

    if [[ "$pub_key" == 'Not Found' ]]; then
        EROR "未找到 GitHub 账户 -->${github_id}"
        exit 1
    elif [[ -z "$pub_key" ]]; then
        EROR "此账户 ssh 密钥不存在,请检查账户！"
        exit 1
    else
        INFO "获取到公钥:$pub_key"
    fi
}

_install_key() {
    [[ -z $pub_key ]] && (EROR "ssh 密钥不存在" && exit 1)

    if [[ ! -f "${HOME}/.ssh/authorized_keys" ]]; then
        INFO "${HOME}/.ssh/authorized_keys 不存在"
        INFO "创建 ${HOME}/.ssh/authorized_keys ..."

        mkdir -p ${HOME}/.ssh/
        touch ${HOME}/.ssh/authorized_keys
        if [ ! -f "${HOME}/.ssh/authorized_keys" ]; then
            EROR "${ERROR} 创建 SSH 密钥文件失败."
        else
            INFO "${INFO} 已创建密钥文件，继续..."
        fi
    fi

    INFO "写入SSH 密钥..."
    echo "$pub_key" >"${HOME}/.ssh/authorized_keys"

    chmod 700 "${HOME}/.ssh/"
    chmod 600 "${HOME}/.ssh/authorized_keys"

    [[ $(grep "${pub_key}" "${HOME}/.ssh/authorized_keys") ]] &&
        INFO "SSH Key 安装成功!" || {
        EROR "SSH Key 安装失败!"
        exit 1
    }
}

_enableSecuritySettings() {
    INFO "启用一些SSH安全设置..."

    $SUDO sed -i "s|.*\(Port \).*|\1${ssh_port}|" /etc/ssh/sshd_config && {
        INFO "√ 配置:SSH端口${ssh_port}"
    } || {
        EROR "SSH端口:${ssh_port} 修改失败！"
        return 1
    }
    $SUDO sed -i "s|.*\(PermitRootLogin \).*|\1prohibit-password|" /etc/ssh/sshd_config && {
        INFO "√ 配置:root用户只允许密钥登录,普通用于可以密码登录"
    } || {
        EROR "root用户只允许密钥登录普通用于可以密码登录 配置失败！"
        return 1
    }
    $SUDO sed -i "s|.*\(PasswordAuthentication \).*|\1no|" /etc/ssh/sshd_config && {
        INFO "√ 配置:禁用所有用户的密码登录，包括普通用户"
    } || {
        EROR "禁用所有用户的密码登录，包括普通用户 配置失败！"
        return 1
    }
    $SUDO sed -i "s|.*\(MaxAuthTries \).*|\1 3|" /etc/ssh/sshd_config && {
        INFO "√ 配置:限制每个连接尝试的最大认证次数为 3 次"
    } || {
        EROR "限制每个连接尝试的最大认证次数为 3 次 配置失败！"
        return 1
    }
    $SUDO sed -i "s|.*\(ClientAliveInterval \).*|\1 300|" /etc/ssh/sshd_config && \
        $SUDO sed -i "s|.*\(ClientAliveCountMax \).*|\1 3|" /etc/ssh/sshd_config && {
            INFO "√ 配置:每5分钟一次心跳包, 3次失败就断开"
        } || {
            EROR "每5分钟一次心跳包, 3次失败就断开 配置失败"
            return 1
        }
}

setSsh() {
    INFO "开始进行SSH配置..."

    _get_github_key
    _install_key
    $SUDO cp "/etc/ssh/sshd_config" "/etc/ssh/sshd_config.bak"
    if [[ "$?" -ne 0 ]]; then
        EROR "备份shhd_config配置文件失败了,为了安全退出设置"
        exit 1
    fi
    _enableSecuritySettings
    if [[ "$?" -ne 0 ]]; then
        EROR "配置出现错误,为了安全不进行设置并恢复原来设置，手动排查。"
        cp "/etc/ssh/sshd_config.bak" "/etc/ssh/sshd_config"
        exit 1
    fi
    $SUDO systemctl restart sshd
    if [[ "$?" -ne 0 ]]; then
        EROR "重启ssh失败,请检查错误后重试..."
        EROR "sudo systemctl restart sshd"
    fi

    INFO "SSH 配置完成！"
    INFO "现在请勿退出终端，请测试可否成功登录在进行退出！"
}

enableUfw() {
    if [[ which ufw >/dev/null -ne 0 ]];then
        INFO "ufw 不存在，开始安装..."
        $SUDO apt install -y ufw >/dev/null
    fi

    if [[ "$($SUDO ufw status)" =~ ^Status:\ active$ ]]; then
        INFO "ufw 已经启用，不进行操作了"
        INFO "当前UFW-->"
        $SUDO ufw status verbose
        return
    fi

    $SUDO ufw enable
    $SUDO systemctl enable ufw

    # 默认阻止入站（不会立即切断你的 SSH 连接，因为防火墙尚未启用）
    $SUDO ufw default deny incoming

    # 默认允许出站
    $SUDO ufw default allow outgoing

    # 默认启用ssh
    $SUDO ufw allow $ssh_port

    INFO "当前UFW-->"
    $SUDO ufw status verbose
}

setSsh
enableUfw
