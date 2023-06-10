#!/bin/bash
#
# v2board.sh
# https://github.com/9d84/v2board.sh

# 检查当前用户是否为 root 用户
check_root() {
    [[ $(id -u) -eq 0 ]]
}

# 如果不是 root 用户，退出脚本
exit_if_not_root() {
    if ! check_root; then
        echo "请用root权限运行此脚本" >&2
        exit 1
    fi
}

# 检查依赖命令是否安装
check_depend() {
    # 需要检查的命令列表
    depends=("docker" "git")

    # 存储未找到的命令
    missing_depends=()

    # 检查每个命令是否存在
    for command in "${depends[@]}"; do
        if ! command -v "$command" &>/dev/null; then
            missing_depends+=("$command")
        fi
    done

    # 如果有命令未找到，则输出缺失的依赖信息并退出脚本
    if [ ${#missing_depends[@]} -gt 0 ]; then
        echo "缺少以下依赖:"
        for missing_command in "${missing_depends[@]}"; do
            echo "- $missing_command"
        done
        exit 1
    fi
}

# 初始化设置
init() {
    # 设置颜色
    color="\033[38;5;206m"
    reset_color="\033[0m"

    # 更新 git 子模块和重命名示例文件
    git submodule update --init
    git submodule update --remote
    find . -maxdepth 1 -type f -name "*.example" -exec bash -c 'newname="${1%.example}"; mv "$1" "$newname"' bash {} \;

    # 提示用户输入 mysql 密码
    echo -e "${color}请输入 mysql 密码（按 Enter 键生成默认密码）:${reset_color}"
    read -r mysql_password

    # 如果密码为空，则生成一个默认密码
    if [ -z "$mysql_password" ]; then
        mysql_password=$(openssl rand -base64 12)
    fi

    # 提示用户输入 mysql 数据库名称
    echo -e "${color}请输入 mysql 数据库名称（默认为 v2board）:${reset_color}"
    read -r mysql_database

    # 如果数据库名称为空，则设置为默认名称 v2board
    if [ -z "$mysql_database" ]; then
        mysql_database="v2board"
    fi

    # 更新 .env 文件中的 mysql 密码和数据库名称
    sed -i "s/MYSQL_ROOT_PASSWORD =.*/MYSQL_ROOT_PASSWORD = $mysql_password/" .env
    sed -i "s/MYSQL_DATABASE =.*/MYSQL_DATABASE = $mysql_database/" .env
}

# 获取用户输入
get_user_input() {
    read -p "$1" response
    echo "$response"
}

# 询问用户是否需要绑定域名
ask_domain_binding() {
    response=$(get_user_input "是否需要绑定域名？(Y/n): ")
    response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
    if [[ $response == "y" ]]; then
        return 0
    else
        return 1
    fi
}

# 询问用户要绑定的域名
ask_domain_name() {
    domain_name=$(get_user_input "请输入域名: ")
    domain_name=$(echo "$domain_name" | tr -d '[:space:]')
    echo "$domain_name"
}

# 替换文件中的文本
replace_text_in_file() {
    file_path="$1"
    old_text="$2"
    new_text="$3"
    sed -i "s|$old_text|$new_text|g" "$file_path"
}

# 提示用户输入邮箱地址，并将邮箱地址添加到 caddy.conf 文件
email() {
    echo "请输入您的邮箱地址："
    read email

    # 邮箱地址的正则表达式模式
    pattern="^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"

    # 检查输入的邮箱地址是否有效
    if [[ $email =~ $pattern ]]; then
        # 将邮箱地址添加到 caddy.conf 文件
        sed -i "0,/{/ s/{/{\ntls ${email}/" caddy.conf
    else
        echo "请输入有效的邮箱地址"
        exit 1
    fi
}

# 替换域名相关的配置信息
replace_domain_name() {
    bind_domain=false

    ask_domain_binding
    if [[ $? -eq 0 ]]; then
        bind_domain=true
        domain_name=$(ask_domain_name)
        replace_text_in_file "caddy.conf" ":80" "$domain_name"
    fi
}

# 启动 v2board 相关服务
launch() {
    docker compose up -d

    docker compose exec www bash -c \
        'wget https://getcomposer.org/download/latest-stable/composer.phar && \
php composer.phar install'

    echo 请在下方输入相关信息
    echo -e "
数据库地址： mysql
数据库名: $mysql_database
数据库用户名: root
数据库密码: $mysql_password
"

    docker compose exec www php artisan v2board:install
}

# 主函数
main() {
    exit_if_not_root
    check_depend
    init
    replace_domain_name
    email
    launch
}

# 调用主函数
main