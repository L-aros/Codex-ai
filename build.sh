#!/usr/bin/env bash
# -*- coding: utf-8 -*-

set -euo pipefail

########################################
# Codex-AI 一键部署脚本
# 适用环境：
# - Linux / CentOS Stream 9 / AlmaLinux 9 / Rocky 9 / RHEL 9 系
# - 已安装 Docker
# - 域名已解析到当前服务器
# - 安全组/防火墙已放行 80 / 443 / 22（至少 80 用于签发证书）
########################################

DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-}"
API_KEY="${API_KEY:-}"
MANAGEMENT_SECRET="${MANAGEMENT_SECRET:-}"

IMAGE="${IMAGE:-eceasy/cli-proxy-api-plus:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-codex-ai}"

APP_DIR="${APP_DIR:-/app/internal/codex-ai}"
CONFIG_FILE="${CONFIG_FILE:-${APP_DIR}/config.yaml}"
AUTH_DIR="${AUTH_DIR:-${APP_DIR}/auths}"
CERT_DIR="${CERT_DIR:-${APP_DIR}/certs}"
CERTBOT_WEBROOT="${CERTBOT_WEBROOT:-/var/www/certbot}"

APP_PORT="${APP_PORT:-8317}"
PUBLIC_HTTP_PORT="${PUBLIC_HTTP_PORT:-80}"
PUBLIC_HTTPS_PORT="${PUBLIC_HTTPS_PORT:-443}"

green() { echo -e "\033[32m[INFO]\033[0m $*"; }
yellow() { echo -e "\033[33m[WARN]\033[0m $*"; }
red() { echo -e "\033[31m[ERR ]\033[0m $*" >&2; }

fail() {
  red "$*"
  exit 1
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || fail "请使用 root 用户运行此脚本"
}

check_cmd() {
  command -v "$1" >/dev/null 2>&1
}

prompt_if_empty() {
  local var_name="$1"
  local prompt_text="$2"
  local secret="${3:-false}"
  local input=""

  if [[ -z "${!var_name:-}" ]]; then
    if [[ "$secret" == "true" ]]; then
      read -r -s -p "$prompt_text: " input
      echo
    else
      read -r -p "$prompt_text: " input
    fi
    export "$var_name"="$input"
  fi

  [[ -n "${!var_name:-}" ]] || fail "$var_name 不能为空"
}

write_app_config() {
  green "写入应用配置: ${CONFIG_FILE}"

  cat > "${CONFIG_FILE}" <<EOF
# UTF-8 编码
# 此文件由 deploy_codex_ai.sh 自动生成
# 如需手工修改，请修改后重启容器：docker restart ${CONTAINER_NAME}

host: '127.0.0.1'
port: ${APP_PORT}

tls:
  enable: false

remote-management:
  allow-remote: false
  # 这里可直接填写明文密码，程序启动时会自动转为哈希
  secret-key: '${MANAGEMENT_SECRET}'
  disable-control-panel: false
  panel-github-repository: 'https://github.com/router-for-me/Cli-Proxy-API-Management-Center'

auth-dir: '/root/.cli-proxy-api'

api-keys:
  - '${API_KEY}'

debug: false

pprof:
  enable: false
  addr: '127.0.0.1:8136'

commercial-mode: false
incognito-browser: true
logging-to-file: true
logs-max-total-size-mb: 100
error-logs-max-files: 10
usage-statistics-enabled: true
proxy-url: ''
force-model-prefix: false
passthrough-headers: false
request-retry: 3
max-retry-credentials: 0
max-retry-interval: 30

quota-exceeded:
  switch-project: true
  switch-preview-model: true

routing:
  strategy: 'round-robin'

ws-auth: false
nonstream-keepalive-interval: 0
EOF
}

write_nginx_http_conf() {
  green "写入 Nginx 临时 HTTP 配置（用于申请证书）"

  cat > "/etc/nginx/conf.d/${DOMAIN}.conf" <<EOF
server {
    listen ${PUBLIC_HTTP_PORT};
    listen [::]:${PUBLIC_HTTP_PORT};
    server_name ${DOMAIN};

    client_max_body_size 20m;

    location /.well-known/acme-challenge/ {
        root ${CERTBOT_WEBROOT};
    }

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }
}
EOF
}

write_nginx_https_conf() {
  green "写入 Nginx 最终 HTTPS 配置"

  local redirect_target=""
  if [[ "${PUBLIC_HTTPS_PORT}" == "443" ]]; then
    redirect_target="https://\$host\$request_uri"
  else
    redirect_target="https://\$host:${PUBLIC_HTTPS_PORT}\$request_uri"
  fi

  cat > "/etc/nginx/conf.d/${DOMAIN}.conf" <<EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen ${PUBLIC_HTTP_PORT};
    listen [::]:${PUBLIC_HTTP_PORT};
    server_name ${DOMAIN};

    client_max_body_size 20m;

    location /.well-known/acme-challenge/ {
        root ${CERTBOT_WEBROOT};
    }

    location / {
        return 301 ${redirect_target};
    }
}
EOF

  if [[ "${PUBLIC_HTTPS_PORT}" == "443" ]]; then
    cat >> "/etc/nginx/conf.d/${DOMAIN}.conf" <<EOF

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    client_max_body_size 20m;

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;

        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }
}
EOF
  else
    cat >> "/etc/nginx/conf.d/${DOMAIN}.conf" <<EOF

server {
    listen ${PUBLIC_HTTPS_PORT} ssl http2;
    listen [::]:${PUBLIC_HTTPS_PORT} ssl http2;
    server_name ${DOMAIN};

    client_max_body_size 20m;

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;

        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }
}
EOF
  fi
}

main() {
  require_root

  prompt_if_empty DOMAIN "请输入要绑定的域名（例如 api.example.com）"
  prompt_if_empty EMAIL "请输入 Let's Encrypt 通知邮箱"
  prompt_if_empty API_KEY "请输入对外访问使用的 API Key（例如 sk-xxxx）" true
  prompt_if_empty MANAGEMENT_SECRET "请输入 management 管理密码（明文，程序启动时会自动转为哈希）" true

  if [[ "${PUBLIC_HTTP_PORT}" != "80" ]]; then
    yellow "当前 PUBLIC_HTTP_PORT=${PUBLIC_HTTP_PORT}"
    yellow "使用 Certbot webroot + HTTP-01 自动签发/续期时，公网通常仍需可访问 TCP 80。"
  fi

  if ! check_cmd docker; then
    red "检测到当前系统未安装 Docker"
    echo
    echo "请先手动安装 Docker 后再重新运行本脚本。"
    echo "推荐使用 LinuxMirrors 的开源 Docker 安装与换源脚本："
    echo
    echo "  bash <(curl -sSL https://linuxmirrors.cn/docker.sh)"
    echo
    echo "项目地址："
    echo "  https://github.com/SuperManito/LinuxMirrors"
    echo
    exit 1
  fi

  green "Docker 已安装"
  systemctl enable --now docker || true

  if ! check_cmd nginx; then
    green "安装 Nginx"
    dnf -y install nginx
  else
    green "Nginx 已安装"
  fi

  if ! check_cmd python3; then
    green "安装 Python3"
    dnf -y install python3
  fi

  if ! check_cmd curl; then
    green "安装 curl"
    dnf -y install curl
  fi

  if [[ ! -x /usr/local/bin/certbot ]]; then
    green "安装 Certbot 到 /opt/certbot"
    python3 -m venv /opt/certbot
    /opt/certbot/bin/pip install --upgrade pip
    /opt/certbot/bin/pip install certbot
    ln -sf /opt/certbot/bin/certbot /usr/local/bin/certbot
  else
    green "Certbot 已安装"
  fi

  green "创建目录结构"
  mkdir -p "${APP_DIR}" "${AUTH_DIR}" "${CERT_DIR}" "${CERTBOT_WEBROOT}/.well-known/acme-challenge"
  chmod -R 755 "${CERTBOT_WEBROOT}"

  write_app_config

  green "重建 Docker 容器: ${CONTAINER_NAME}"
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

  docker run -d \
    --name "${CONTAINER_NAME}" \
    --restart unless-stopped \
    -p "127.0.0.1:${APP_PORT}:${APP_PORT}" \
    -v "${CONFIG_FILE}:/CLIProxyAPI/config.yaml" \
    -v "${AUTH_DIR}:/root/.cli-proxy-api" \
    -v "${CERT_DIR}:/app/internal/codex-ai/certs" \
    "${IMAGE}"

  sleep 3

  green "当前容器状态"
  docker ps --filter "name=${CONTAINER_NAME}"

  write_nginx_http_conf

  green "测试并启动 Nginx"
  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx

  if [[ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    green "开始申请 Let's Encrypt 证书"
    certbot certonly \
      --webroot \
      -w "${CERTBOT_WEBROOT}" \
      -d "${DOMAIN}" \
      --agree-tos \
      -m "${EMAIL}" \
      --no-eff-email
  else
    yellow "检测到现有证书，跳过首次签发"
  fi

  write_nginx_https_conf

  green "测试并重载 Nginx"
  nginx -t
  systemctl reload nginx

  green "配置自动续期"
  cat > /etc/cron.d/certbot-renew <<'EOF'
0 3,15 * * * root /usr/local/bin/certbot renew -q --deploy-hook "systemctl reload nginx"
EOF
  chmod 644 /etc/cron.d/certbot-renew

  echo
  green "基础检查"
  echo "===== Docker 容器 ====="
  docker ps --filter "name=${CONTAINER_NAME}"
  echo

  echo "===== Nginx 状态 ====="
  systemctl status nginx --no-pager | sed -n '1,12p'
  echo

  echo "===== 本地后端 ====="
  curl -I "http://127.0.0.1:${APP_PORT}" || true
  echo

  echo "===== HTTP 检查 ====="
  curl -I "http://${DOMAIN}" || true
  echo

  if [[ "${PUBLIC_HTTPS_PORT}" == "443" ]]; then
    echo "===== HTTPS 检查 ====="
    curl -Ik "https://${DOMAIN}" || true
    echo
    echo "===== 模型接口检查（带 API Key） ====="
    curl -sS "https://${DOMAIN}/v1/models" \
      -H "Authorization: Bearer ${API_KEY}" || true
  else
    echo "===== HTTPS 检查 ====="
    curl -Ik "https://${DOMAIN}:${PUBLIC_HTTPS_PORT}" || true
    echo
    echo "===== 模型接口检查（带 API Key） ====="
    curl -sS "https://${DOMAIN}:${PUBLIC_HTTPS_PORT}/v1/models" \
      -H "Authorization: Bearer ${API_KEY}" || true
  fi
  echo
  echo

  green "部署完成"
  echo "域名: ${DOMAIN}"
  echo "应用端口(APP_PORT): ${APP_PORT}"
  echo "外部 HTTP 端口(PUBLIC_HTTP_PORT): ${PUBLIC_HTTP_PORT}"
  echo "外部 HTTPS 端口(PUBLIC_HTTPS_PORT): ${PUBLIC_HTTPS_PORT}"
  echo "配置文件: ${CONFIG_FILE}"
  echo "认证目录: ${AUTH_DIR}"
  echo "容器名称: ${CONTAINER_NAME}"
  echo
  echo "聊天接口测试示例："
  if [[ "${PUBLIC_HTTPS_PORT}" == "443" ]]; then
    cat <<EOF
curl -sS https://${DOMAIN}/v1/chat/completions \\
  -H "Authorization: Bearer ${API_KEY}" \\
  -H "Content-Type: application/json" \\
  -d '{
    "model": "gpt-5.2-codex",
    "messages": [
      {
        "role": "user",
        "content": "你好，介绍下你自己"
      }
    ]
  }'
EOF
  else
    cat <<EOF
curl -sS https://${DOMAIN}:${PUBLIC_HTTPS_PORT}/v1/chat/completions \\
  -H "Authorization: Bearer ${API_KEY}" \\
  -H "Content-Type: application/json" \\
  -d '{
    "model": "gpt-5.2-codex",
    "messages": [
      {
        "role": "user",
        "content": "你好，介绍下你自己"
      }
    ]
  }'
EOF
  fi
}

main "$@"
