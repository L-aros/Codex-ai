# 操作教程

本文档用于指导你从零开始在 Linux 服务器上部署 Codex-AI。

---

## 一、准备工作

在开始之前，请确认以下内容已经准备好：

### 1. 服务器环境

建议系统：

- CentOS Stream 9
- AlmaLinux 9
- Rocky Linux 9
- RHEL 9
- 其他兼容环境

### 2. 域名解析

请提前准备好一个域名，并将其解析到服务器公网 IP。

例如：

```text
api.example.com -> 你的服务器公网IP
````

### 3. 安全组/防火墙

至少需要开放以下端口：

* `22`：SSH 登录
* `80`：HTTP 及证书签发
* `443`：HTTPS 对外访问

### 4. Docker

本项目脚本不会自动安装 Docker。
如果没有安装 Docker，请先执行：

```bash
bash <(curl -sSL https://linuxmirrors.cn/docker.sh)
```

安装完成后建议验证：

```bash
docker -v
systemctl status docker --no-pager
```

---

## 二、获取项目文件

将你的项目仓库克隆到服务器：

```bash
git clone https://github.com/L-aros/Codex-ai.git
cd Codex-ai
```

或者你也可以直接把脚本上传到服务器。

---

## 三、给脚本执行权限

```bash
chmod +x build.sh
```

---

## 四、执行部署脚本

### 方式 1：交互式部署

```bash
./build.sh
```

脚本会依次提示你输入：

* 域名
* Let's Encrypt 邮箱
* API Key
* management 管理密码

### 方式 2：环境变量部署

```bash
DOMAIN=api.example.com \
EMAIL=your@email.com \
API_KEY='sk-your-api-key' \
MANAGEMENT_SECRET='your-admin-password' \
APP_PORT=8317 \
PUBLIC_HTTP_PORT=80 \
PUBLIC_HTTPS_PORT=443 \
bash build.sh
```

---

## 五、脚本执行后会做什么

脚本会自动完成以下操作：

### 1. 检测 Docker 是否已安装

* 如果未安装，会提示并退出
* 不会自动安装 Docker

### 2. 安装基础组件

如果未安装，会自动安装：

* Nginx
* Python3
* curl
* Certbot

### 3. 创建部署目录

默认目录：

```text
/app/internal/codex-ai/
├── config.yaml
├── auths/
└── certs/
```

### 4. 自动生成配置文件

配置文件路径：

```text
/app/internal/codex-ai/config.yaml
```

### 5. 启动 Docker 容器

默认容器名称：

```text
codex-ai
```

### 6. 写入 Nginx 配置

先生成 HTTP 配置，用于证书校验；
证书申请成功后，再切换为最终 HTTPS 配置。

### 7. 自动申请 HTTPS 证书

使用 Let's Encrypt 证书自动签发。

### 8. 自动配置证书续期

写入：

```text
/etc/cron.d/certbot-renew
```

---

## 六、部署完成后检查

### 1. 检查容器状态

```bash
docker ps
```

确认 `codex-ai` 容器处于运行状态。

### 2. 检查 Nginx 状态

```bash
systemctl status nginx --no-pager
```

### 3. 检查域名访问

如果你使用默认 443 端口：

```bash
curl -I http://你的域名
curl -Ik https://你的域名
```

如果你改了 HTTPS 端口，例如 `8443`：

```bash
curl -Ik https://你的域名:8443
```

---

## 七、验证 API 是否可用

### 1. 获取模型列表

```bash
curl -sS https://你的域名/v1/models \
  -H "Authorization: Bearer 你的API_KEY"
```

如果你使用了非默认 HTTPS 端口，例如 8443：

```bash
curl -sS https://你的域名:8443/v1/models \
  -H "Authorization: Bearer 你的API_KEY"
```

### 2. 测试聊天接口

```bash
curl -sS https://你的域名/v1/chat/completions \
  -H "Authorization: Bearer 你的API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-5.2-codex",
    "messages": [
      {
        "role": "user",
        "content": "你好，介绍下你自己"
      }
    ]
  }'
```

---

## 八、重要配置说明

### 1. 域名

脚本不会内置任何个人域名。
每次部署时都由用户自己输入域名。

### 2. management 密码

你输入的是**明文密码**，程序运行时会自动转换为哈希并保存。
你不需要提前手动生成 bcrypt 哈希。

### 3. APP_PORT

后端应用监听端口，默认 `8317`。
容器只绑定到本机 `127.0.0.1`，不直接暴露公网。

### 4. PUBLIC_HTTP_PORT

Nginx 对外 HTTP 端口，默认 `80`。

### 5. PUBLIC_HTTPS_PORT

Nginx 对外 HTTPS 端口，默认 `443`。

---

## 九、推荐端口配置

推荐保持以下默认值：

```text
APP_PORT=8317
PUBLIC_HTTP_PORT=80
PUBLIC_HTTPS_PORT=443
```

原因：

* 80 端口更适合 Let’s Encrypt 自动签发证书
* 443 是 HTTPS 的标准端口
* 8317 只给后端服务内部使用

---

## 十、修改配置后如何重启

如果你手动修改了配置文件：

```text
/app/internal/codex-ai/config.yaml
```

可以执行：

```bash
docker restart codex-ai
```

如果你修改了 Nginx 配置：

```bash
nginx -t
systemctl reload nginx
```

---

## 十一、证书续期检查

### 1. 查看自动续期任务

```bash
cat /etc/cron.d/certbot-renew
```

### 2. 手动测试续期流程

```bash
certbot renew --dry-run
```

如果输出正常，说明续期机制可用。

---

## 十二、常见问题排查

### 1. Docker 未安装

现象：脚本直接退出并提示未安装 Docker。

处理方式：

```bash
bash <(curl -sSL https://linuxmirrors.cn/docker.sh)
```

---

### 2. 域名无法签发证书

请检查：

* 域名是否已经正确解析
* 80 端口是否放行
* Nginx 是否已启动
* 服务器是否能被公网正常访问

---

### 3. HTTPS 能打开，但根路径返回 404

这通常表示：

* Nginx 正常
* HTTPS 正常
* 后端服务正常
* 根路径没有默认页面

继续访问 `/v1/models` 等接口即可。

---

### 4. `/v1/models` 返回 `Missing API key`

说明接口是通的，但你没有传 Bearer Token。

示例：

```bash
curl -sS https://你的域名/v1/models \
  -H "Authorization: Bearer 你的API_KEY"
```

---

### 5. 聊天接口返回模型错误

请检查：

* 请求方法是否为 `POST`
* JSON 是否正确
* `model` 名称是否拼写正确
* 后端是否已配置可用上游

---

## 十三、建议的维护方式

建议你保留以下内容：

* 项目仓库中的部署脚本
* 中文配置示例文件
* 当前服务器实际使用的 `config.yaml`
* 已申请的域名与证书信息
* Nginx 配置文件备份

---

## 十四、升级建议

后续如果你想升级：

1. 先备份当前配置文件
2. 拉取新的脚本或镜像
3. 重新运行部署脚本或手动替换镜像
4. 检查容器日志与接口可用性

查看容器日志：

```bash
docker logs --tail 100 codex-ai
```

---

## 十五、总结

一个完整的成功部署流程应当满足：

* 域名已解析
* Docker 已安装
* Nginx 已运行
* HTTPS 已签发
* `/v1/models` 可正常返回
* `/v1/chat/completions` 可正常调用
* 自动续期已配置完成

做到这些，就说明你的部署已经基本完成。


## 常见问题

### 1. 脚本提示未安装 Docker

请先安装 Docker，再重新执行脚本。

### 2. 证书申请失败

请检查：

* 域名是否已解析到当前服务器
* 80 端口是否开放
* Nginx 是否正常运行

### 3. `https://你的域名/` 返回 404

这通常表示：

* Nginx 反代成功
* 后端服务正常响应
* 根路径 `/` 没有提供页面

这不一定是错误，可以继续测试 `/v1/models` 等接口。

### 4. `/v1/models` 返回 `Missing API key`

说明服务正常，但请求未携带 Bearer Token。
