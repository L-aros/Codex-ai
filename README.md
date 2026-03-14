# Codex-AI

一个适用于 Linux 服务器的 `CLIProxyAPI Plus + Docker + Nginx + Let's Encrypt` 一键部署脚本与中文配置说明项目
本项目的目标是帮助用户快速在自己的服务器上部署一个带有以下服务的 Codex-AI 服务环境

- Docker 容器运行
- Nginx 反向代理
- HTTPS 证书自动签发与续期
- 中文注释配置文件
- 可自定义域名与端口



---

## 功能特性

- 一键部署 `CLIProxyAPI-Plus`
- 自动生成基础 `config.yaml`
- 自动创建部署目录结构
- 自动安装并配置 Nginx
- 自动申请 Let's Encrypt 证书
- 自动配置证书续期
- 支持用户自定义域名
- 支持自定义应用端口与对外端口
- 提供中文注释版配置示例文件

---

## 目录说明

建议仓库包含以下文件：

```text
.
├── build.sh
├── config.zh-CN.example.yaml
├── README.md
└── 操作教程.md
````

部署完成后，服务器默认目录结构如下：

```text
/app/internal/codex-ai/
├── config.yaml
├── auths/
└── certs/
```

---

## 环境要求

使用本项目之前，请确认：

* 你有一台 Linux 服务器
* 域名已经解析到该服务器
* 服务器已开放 80、443、22 端口
* 已安装 Docker
* 具备 root 权限

---

## Docker 说明

本项目脚本**不会自动安装 Docker**。

如果服务器未安装 Docker，脚本会直接提示并退出。
推荐先使用 LinuxMirrors 的开源脚本安装 Docker：

```bash
bash <(curl -sSL https://linuxmirrors.cn/docker.sh)
```

---

## 快速开始

### 1. 赋予脚本执行权限

```bash
chmod +x build.sh
```

### 2. 交互式运行

```bash
./build.sh
```

执行时会提示输入：

* 要绑定的域名
* Let's Encrypt 邮箱
* 对外访问 API Key
* management 管理密码

### 3. 使用环境变量运行

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

## 可配置环境变量

| 变量名                 | 说明                 | 默认值                                  |
| ------------------- | ------------------ | ------------------------------------ |
| `DOMAIN`            | 要绑定的域名             | 无                                    |
| `EMAIL`             | Let's Encrypt 通知邮箱 | 无                                    |
| `API_KEY`           | 对外访问 API Key       | 无                                    |
| `MANAGEMENT_SECRET` | 管理密码（明文）           | 无                                    |
| `IMAGE`             | Docker 镜像          | `eceasy/cli-proxy-api-plus:latest`   |
| `CONTAINER_NAME`    | 容器名称               | `codex-ai`                           |
| `APP_DIR`           | 应用目录               | `/app/internal/codex-ai`             |
| `CONFIG_FILE`       | 配置文件路径             | `/app/internal/codex-ai/config.yaml` |
| `AUTH_DIR`          | 认证目录               | `/app/internal/codex-ai/auths`       |
| `CERT_DIR`          | 证书目录               | `/app/internal/codex-ai/certs`       |
| `CERTBOT_WEBROOT`   | Certbot 校验目录       | `/var/www/certbot`                   |
| `APP_PORT`          | 后端应用监听端口           | `8317`                               |
| `PUBLIC_HTTP_PORT`  | Nginx 外部 HTTP 端口   | `80`                                 |
| `PUBLIC_HTTPS_PORT` | Nginx 外部 HTTPS 端口  | `443`                                |

---

## 端口说明

### APP_PORT

后端应用实际监听的端口。
默认绑定到本机 `127.0.0.1`，只允许本机访问，由 Nginx 负责对外代理。

### PUBLIC_HTTP_PORT

Nginx 对外开放的 HTTP 端口。

### PUBLIC_HTTPS_PORT

Nginx 对外开放的 HTTPS 端口。

---

## 证书说明

本项目默认使用：

* Nginx
* Certbot
* webroot
* HTTP-01 challenge

来申请和续期 Let's Encrypt 证书。

### 注意

如果你使用默认方式自动签发证书：

* 公网通常必须能访问 **80 端口**
* 推荐保持 `PUBLIC_HTTP_PORT=80`
* 推荐保持 `PUBLIC_HTTPS_PORT=443`

如果把对外 HTTP 端口改成非 80，证书自动签发与续期可能失败。

---

## 测试接口

### 获取模型列表

```bash
curl -sS https://api.example.com/v1/models \
  -H "Authorization: Bearer sk-your-api-key"
```

### 测试聊天接口

```bash
curl -sS https://api.example.com/v1/chat/completions \
  -H "Authorization: Bearer sk-your-api-key" \
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

## 自动续期

脚本会自动写入：

```text
/etc/cron.d/certbot-renew
```

用于定时执行证书续期，并在续期成功后自动重载 Nginx。

---

## 配置文件说明

仓库中提供：

```text
config.zh-CN.example.yaml
```

这是基于官方示例配置文件整理的中文注释版本，方便理解各字段含义。

---

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

---

## 项目声明

1. 本项目仅提供部署脚本、配置示例和文档说明，便于用户在自己的服务器环境中进行学习、研究和自建部署。
2. 本项目不提供任何第三方账号、密钥、授权服务或付费接口资源。
3. 使用者应自行确保其部署、调用和使用行为符合所在地法律法规，以及相关上游服务提供商的协议与政策。
4. 因服务器环境、网络策略、域名解析、安全组、防火墙、证书申请限制、上游接口变动等原因导致的问题，需要由使用者自行排查与承担相关责任。
5. 本项目为开源辅助部署项目，不对因使用本项目造成的任何直接或间接损失承担责任。
6. 若本项目中涉及的第三方名称、镜像、工具、服务或配置示例存在版权、商标或协议要求，请使用者自行遵守对应条款。

