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
echo
if [ -f "$DATA_DIR/config" ]; then
    ylw "检测到已有配置："
    sed 's/^/    /' "$DATA_DIR/config"
    echo
    echo "  当前回源域名："
    "$BIN" list 2>/dev/null | sed 's/^/    /' || true
else
    echo "  下一步 —— 初始化（只需一次）："
    echo
    echo "    $BIN init <后台路径>"
    echo
    echo "  <后台路径> 是 XBoard 管理面板那段随机串。浏览器打开"
    echo "    https://你的域名/xxxxxxxx"
    echo "  里 xxxxxxxx 就是它。"
fi
echo
echo "  然后加回源域名："
echo "    $BIN add newsub.example.com"
echo
echo "  管后台白名单："
echo "    $BIN allow admin.example.com"
echo "    $BIN deny  admin.example.com"
echo "    $BIN allowlist"
echo
