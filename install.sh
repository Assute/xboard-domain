#!/bin/bash
# ============================================================================
#  xboard-domain 安装脚本
#
#    curl -fsSL https://raw.githubusercontent.com/Assute/xboard-domain/main/install.sh | sudo bash
#
#  只做三件事：把主脚本放到 /usr/local/sbin、建数据目录、打印下一步。
#  不会自动改 nginx 配置——那需要先 init 指定后台路径。
# ============================================================================
set -eu

RAW_BASE="${XB_DOMAIN_RAW:-https://raw.githubusercontent.com/Assute/xboard-domain/main}"
BIN=/usr/local/sbin/xboard-domain
DATA_DIR=/etc/xboard-domain

red() { printf '\033[31m%s\033[0m\n' "$*"; }
grn() { printf '\033[32m%s\033[0m\n' "$*"; }
ylw() { printf '\033[33m%s\033[0m\n' "$*"; }

[ "$(id -u)" = "0" ] || { red "需要 root，请用 sudo 运行"; exit 1; }

command -v curl >/dev/null 2>&1 || { red "缺少 curl"; exit 1; }
command -v python3 >/dev/null 2>&1 || ylw "未找到 python3，init 时需要用到来改写 vhost"

NGINX_BIN=/www/server/nginx/sbin/nginx
if [ ! -x "$NGINX_BIN" ]; then
    red "找不到 $NGINX_BIN"
    echo "这个脚本按宝塔/aaPanel 的目录结构写的，原生 nginx 请改脚本顶部的路径变量。"
    exit 1
fi

grn "==> 下载主脚本"
tmp=$(mktemp)
if ! curl -fsSL --max-time 60 "$RAW_BASE/xboard-domain" -o "$tmp"; then
    red "下载失败: $RAW_BASE/xboard-domain"
    rm -f "$tmp"
    exit 1
fi

head -1 "$tmp" | grep -q '^#!/bin/bash' || { red "下载内容不是 bash 脚本"; rm -f "$tmp"; exit 1; }
bash -n "$tmp" || { red "脚本语法检查失败"; rm -f "$tmp"; exit 1; }

grn "==> 安装到 $BIN"
install -m 755 "$tmp" "$BIN"
rm -f "$tmp"

grn "==> 建数据目录 $DATA_DIR"
mkdir -p "$DATA_DIR"
chmod 700 "$DATA_DIR"
[ -f "$DATA_DIR/admin-allow.list" ] || : > "$DATA_DIR/admin-allow.list"

echo
grn "安装完成。"

if [ -f "$DATA_DIR/config" ]; then
    # 已初始化，直接进菜单（脚本化调用设 XB_NO_MENU=1 跳过）
    if [ -z "${XB_NO_MENU:-}" ] && [ -r /dev/tty ] && [ -t 1 ]; then
        sleep 1
        "$BIN" < /dev/tty || true
    else
        echo
        "$BIN" list 2>/dev/null | sed 's/^/  /' || true
        echo
        echo "  进菜单：$BIN"
    fi
else
    echo
    echo "  还没初始化，需要先指定 XBoard 后台路径。"
    echo
    echo "  后台路径就是管理面板那段随机串，例如打开"
    echo "    https://你的域名/a1b2c3d4"
    echo "  里的 a1b2c3d4。"
    echo
    printf '  现在初始化吗？输入后台路径（留空跳过）: '
    if [ -r /dev/tty ] && [ -t 1 ]; then
        read -r adminPath < /dev/tty || adminPath=""
    else
        adminPath=""
    fi
    if [ -n "$adminPath" ]; then
        "$BIN" init "$adminPath" || true
        echo
        if [ -z "${XB_NO_MENU:-}" ] && [ -r /dev/tty ] && [ -t 1 ]; then
            "$BIN" < /dev/tty || true
        fi
    else
        echo
        echo "  稍后手动初始化："
        echo "    $BIN init <后台路径>"
    fi
fi
echo
