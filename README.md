# xboard-domain

> XBoard 挂 CDN 时，回源域名接不住、后台敞着，就两个命令的事。

XBoard 通常用 docker 跑在 `127.0.0.1:7001`，前面套 CDN。回源走 80 到 nginx，nginx 靠 `server_name` 认域名。这套配置有两个常见坑，这个脚本把它们一起管了。

---

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/Assute/xboard-domain/main/install.sh | sudo bash
```

装到 `/usr/local/sbin/xboard-domain`。

---

## 它解决什么

### 坑一：新域名回源收到 nginx 欢迎页

DNS 指到 CDN、CDN 回源配好、浏览器打开却是 nginx 默认页 —— 因为源站没有对应的 `server_name`，请求落到了 `0.default.conf`：

```
server_name _;
root /www/server/nginx/html;   ← 那个 58 KB 的 Welcome to nginx
```

看起来像"打不开"，实际上是没接住。加个 vhost 就好：

```bash
xboard-domain add newsub.example.com
```

### 坑二：后台路径对所有回源域名开放

XBoard 的管理面板是一段随机路径（`secure_path`），例如 `/a1b2c3d4`。只要有人知道这段路径，任何一个指向源站的域名都能打开它 —— 包括那些只打算做分发用的子域。

这个脚本把后台路径抽到一个单独的 include 文件里做 Host 白名单，所有回源 vhost 共用：

```nginx
location ^~ /a1b2c3d4 {
    if ($host !~ ^(admin\.example\.com)$) {
        return 404;
    }
    proxy_pass http://127.0.0.1:7001;
    ...
}
```

改一次白名单，全局生效：

```bash
xboard-domain allow admin.example.com     # 只有它能进
xboard-domain deny  admin.example.com     # 撤销
xboard-domain allowlist                   # 看当前谁可以进
```

---

## 用法

### 初始化

```bash
xboard-domain init <后台路径> [上游]
```

后台路径就是 XBoard 管理面板那段随机串。浏览器里打开 `https://你的域名/a1b2c3d4`，`a1b2c3d4` 就是它。

```bash
xboard-domain init a1b2c3d4
```

上游默认 `127.0.0.1:7001`，容器映射到别的端口就写别的。

初始化会做三件事：写 `/etc/xboard-domain/config`、生成 ACL include、给所有已存在的回源 vhost 接上这个 include。

### 加回源域名

```bash
xboard-domain add newsub.example.com
```

```
已生成 /www/server/panel/vhost/nginx/newsub.example.com.conf
已 reload
  本机测试  /  -> 200
  后台路径  -> 404

CDN 面板填：
  回源地址   源站 IP（本机）
  回源端口   80
  回源协议   HTTP
  回源 Host   newsub.example.com      ← 必须填域名，不能填 IP
```

需要源站也监听 443（想绕开 CDN 直连）时，多给一个证书目录名：

```bash
xboard-domain add newsub.example.com example.com
```

第二个参数是 `/www/server/panel/vhost/cert/` 下的目录名。

### 管后台白名单

```bash
xboard-domain allow admin.example.com      # 放行
xboard-domain allow a.example.com b.example.com   # 一次多个
xboard-domain deny admin.example.com       # 撤销
xboard-domain allowlist                    # 当前白名单
```

白名单为空时，**任何域名都进不了后台**：

```
白名单为空——所有域名都进不了后台
```

这是刻意的默认值 —— 忘了配就是全关，不会因为漏配而敞着。

### 看整体状态

```bash
xboard-domain list
```

```
回源域名(vhost)                    后台
--------------------------------------------------------------------
admin.example.com                  已接入
    admin.example.com              放行
api.example.com                    已接入
    api.example.com                禁止
    api2.example.com               禁止
www.example.com                    已接入
    www.example.com                禁止

  共 3 个回源 vhost
  后台路径  /a1b2c3d4

  可访问后台的域名：
    admin.example.com
```

一个 vhost 里有多个 `server_name` 时会逐个列出来。

---

## CDN 面板配置

每个回源域名都按这张表填：

| 项目 | 值 |
|---|---|
| 回源地址 | 源站 IP |
| 回源端口 | `80` |
| 回源协议 | `HTTP` |
| 回源 Host | **域名本身** |

**回源 Host 是最容易填错的一格。** 填成 IP 的话，nginx 收到的 Host 是 IP，匹配不到任何 `server_name`，所有域名一起落到默认站点。

回源协议选 HTTP 就够了 —— 用户到 CDN 那段用 CDN 的证书，CDN 到源站明文即可，源站不需要证书。

---

## 数据结构

```
/etc/xboard-domain/config             上游地址、后台路径（600）
/etc/xboard-domain/admin-allow.list   允许访问后台的域名，一行一个
<nginx>/xboard-admin-acl.conf         生成的 include，勿手改
```

`config` 长这样：

```bash
UPSTREAM=127.0.0.1:7001
ADMIN_PATH=a1b2c3d4
```

改完 `config` 跑 `xboard-domain reload`。

---

## 排错

**回源域名打开是 nginx 欢迎页**

说明请求落到了 `0.default.conf`。检查：

```bash
xboard-domain test 你的域名
```

`/` 返回 200 但内容是欢迎页 → vhost 没生效，确认 `server_name` 拼写、以及有没有 `nginx -s reload`。

**后台 404，但你确实在白名单里**

```bash
xboard-domain allowlist          # 确认域名在里面
xboard-domain list               # 确认 vhost 显示"已接入"
```

`已接入` 表示该 vhost 里有 `include .../xboard-admin-acl.conf;`。没有的话重跑 `xboard-domain init` 会把已有 vhost 全部接上。

**改了白名单没生效**

```bash
xboard-domain reload
```

**看 nginx 实际加载的配置**

```bash
nginx -T | grep -A20 'xboard-admin-acl'
```

---

## 与 CDN 端口收敛的配合

如果打算把容器端口从 `0.0.0.0:7001` 收回到 `127.0.0.1:7001`（这样外部彻底无法直连容器），顺序很重要：

1. 先确认所有回源域名在 CDN 侧都改成回源 `80`
2. 确认 `nginx -T` 里每个域名都能正确定位到自己的 vhost
3. 再改 compose 的 `ports` 并 `docker compose up -d`
4. 最后把 iptables 里给容器端口单独开的放行规则删掉

顺序反了站点会直接 502 —— 因为 CDN 还在往容器端口上撞。

---

## 环境要求

- Linux + nginx（宝塔 / aaPanel 的目录结构）
- bash 4+
- python3（用于改写 vhost 文件，只在 `init` 时用到）
- root 权限

nginx 相关路径在脚本顶部，Debian/Ubuntu 原生 nginx 需要改：

```bash
CONF_DIR=/etc/nginx/conf.d
CERT_DIR=/etc/nginx/cert
LOG_DIR=/var/log/nginx
NGINX_BIN=/usr/sbin/nginx
```

---

## License

MIT
