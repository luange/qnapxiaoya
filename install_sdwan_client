#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Universal installer for Panabit IWAN / SD-WAN Linux client
# Supported init: systemd
# Supported arch: x86_64/amd64, aarch64/arm64
# Repository: https://github.com/luange/qnapxiaoya

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/luange/qnapxiaoya/main}"
INSTALL_DIR="${INSTALL_DIR:-/etc/sdwan}"
CONFIG_FILE="${CONFIG_FILE:-$INSTALL_DIR/iwan.conf}"
ENV_FILE="${ENV_FILE:-$INSTALL_DIR/client.env}"
ROUTE_FILE="${ROUTE_FILE:-$INSTALL_DIR/routes.conf}"
SERVICE_NAME="sdwan-client"
BIN_PATH="$INSTALL_DIR/linux_sdwan_client"

log() { printf '\033[1;32m[+] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*" >&2; }
die() { printf '\033[1;31m[x] %s\033[0m\n' "$*" >&2; exit 1; }

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "请使用 root 运行：sudo bash $0"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) REMOTE_BIN="linux_sdwand_x86" ;;
    aarch64|arm64) REMOTE_BIN="linux_sdwand_arm" ;;
    *) die "不支持的架构：$(uname -m)，当前仓库仅提供 x86_64 与 ARM64 客户端" ;;
  esac
}

prompt_default() {
  local __var="$1" __prompt="$2" __default="$3" __value
  read -r -p "$__prompt [$__default]: " __value
  printf -v "$__var" '%s' "${__value:-$__default}"
}

prompt_secret() {
  local __var="$1" __prompt="$2" __value
  read -r -s -p "$__prompt: " __value
  echo
  [[ -n "$__value" ]] || die "$__prompt 不能为空"
  printf -v "$__var" '%s' "$__value"
}

valid_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }
valid_ipv4_or_host() { [[ "$1" =~ ^[A-Za-z0-9._:-]+$ ]]; }

download_client() {
  local url="$REPO_RAW/$REMOTE_BIN"
  log "下载客户端：$url"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --connect-timeout 15 "$url" -o "$BIN_PATH.tmp"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$BIN_PATH.tmp" "$url"
  else
    die "需要 curl 或 wget"
  fi
  [[ -s "$BIN_PATH.tmp" ]] || die "客户端文件下载失败或为空"
  install -m 0755 "$BIN_PATH.tmp" "$BIN_PATH"
  rm -f "$BIN_PATH.tmp"
}

collect_config() {
  echo
  log "填写隧道参数"
  prompt_default TUN_NAME "虚拟网卡名称" "iwan0"
  prompt_default SERVER "服务端 IP 或域名" "1.2.3.4"
  prompt_default PORT "服务端 UDP 端口" "8000"
  prompt_default USERNAME "认证用户名" "branch01"
  prompt_secret PASSWORD "认证密码"
  prompt_default MTU "隧道 MTU" "1400"
  prompt_default ENCRYPT "隧道加密：0=关闭，1=开启" "0"
  prompt_default SRLINKS "SR 路径标签 srlinks" "1"
  prompt_default SRENCRYPTMODE "SR 加密：0=关闭，1=AES128" "0"

  SRPASSWORD=""
  if [[ "$SRENCRYPTMODE" != "0" ]]; then
    prompt_secret SRPASSWORD "SR 路径认证密钥 srpassword"
  fi

  prompt_default PIPEID "pipeid：0=不启用多路径管道" "0"
  PIPEIDX=""
  if [[ "$PIPEID" != "0" ]]; then
    prompt_default PIPEIDX "pipeidx：本端方向 0 或 1" "0"
  fi

  valid_ipv4_or_host "$SERVER" || die "server 格式不合法"
  for n in PORT MTU ENCRYPT SRLINKS SRENCRYPTMODE PIPEID; do
    valid_uint "${!n}" || die "$n 必须为整数"
  done
  (( PORT >= 1 && PORT <= 65535 )) || die "端口范围必须是 1-65535"
  (( MTU >= 576 && MTU <= 9000 )) || die "MTU 范围不合理"
  (( SRLINKS >= 1 && SRLINKS <= 65535 )) || die "srlinks 范围必须是 1-65535"
}

write_config() {
  umask 077
  cat > "$CONFIG_FILE" <<EOF
[$TUN_NAME]
server=$SERVER
username=$USERNAME
password=$PASSWORD
port=$PORT
mtu=$MTU
encrypt=$ENCRYPT
pipeid=$PIPEID
srlinks=$SRLINKS
srencryptmode=$SRENCRYPTMODE
EOF
  [[ -n "$PIPEIDX" ]] && echo "pipeidx=$PIPEIDX" >> "$CONFIG_FILE"
  [[ -n "$SRPASSWORD" ]] && echo "srpassword=$SRPASSWORD" >> "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"

  cat > "$ENV_FILE" <<EOF
TUN_NAME=$TUN_NAME
SERVER=$SERVER
CONFIG_FILE=$CONFIG_FILE
EOF
  chmod 600 "$ENV_FILE"
}

collect_routes() {
  echo
  cat <<'EOF'
路由接管模式：
  1) none  只建立隧道，不修改路由
  2) split 仅指定网段走 iwan
  3) full  全部 IPv4 默认流量走 iwan，并自动保留服务端直连逃生路由
EOF
  prompt_default ROUTE_MODE "请选择 none/split/full" "none"

  case "$ROUTE_MODE" in
    none)
      printf 'ROUTE_MODE=none\nROUTES=\n' > "$ROUTE_FILE"
      ;;
    split)
      read -r -p "输入目标网段，空格分隔，例如 192.168.8.0/24 10.20.0.0/16: " ROUTES
      [[ -n "$ROUTES" ]] || die "split 模式至少需要一个目标网段"
      printf 'ROUTE_MODE=split\nROUTES=%q\n' "$ROUTES" > "$ROUTE_FILE"
      ;;
    full)
      printf 'ROUTE_MODE=full\nROUTES=\n' > "$ROUTE_FILE"
      ;;
    *) die "未知路由模式：$ROUTE_MODE" ;;
  esac
  chmod 600 "$ROUTE_FILE"
}

write_route_helper() {
  cat > /usr/local/sbin/sdwan-route-manager <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

ACTION="${1:-up}"
source /etc/sdwan/client.env
source /etc/sdwan/routes.conf

STATE_DIR=/run/sdwan-client
STATE_FILE="$STATE_DIR/original-default.env"
mkdir -p "$STATE_DIR"

resolve_server_ipv4() {
  if [[ "$SERVER" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    printf '%s\n' "$SERVER"
  else
    getent ahostsv4 "$SERVER" | awk 'NR==1 {print $1}'
  fi
}

wait_tunnel() {
  local i
  for i in $(seq 1 60); do
    ip link show "$TUN_NAME" >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "未检测到隧道接口：$TUN_NAME" >&2
  return 1
}

save_underlay() {
  local line gw dev src
  line="$(ip -4 route show default | grep -v "dev $TUN_NAME" | head -n1 || true)"
  [[ -n "$line" ]] || { echo "找不到原始 IPv4 默认路由" >&2; return 1; }
  gw="$(awk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}' <<<"$line")"
  dev="$(awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' <<<"$line")"
  src="$(awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' <<<"$line")"
  {
    printf 'UNDERLAY_GW=%q\n' "$gw"
    printf 'UNDERLAY_DEV=%q\n' "$dev"
    printf 'UNDERLAY_SRC=%q\n' "$src"
  } > "$STATE_FILE"
}

add_server_escape_route() {
  local server_ip="$1"
  source "$STATE_FILE"
  if [[ -n "${UNDERLAY_GW:-}" ]]; then
    ip -4 route replace "$server_ip/32" via "$UNDERLAY_GW" dev "$UNDERLAY_DEV"
  else
    ip -4 route replace "$server_ip/32" dev "$UNDERLAY_DEV"
  fi
}

up() {
  [[ "$ROUTE_MODE" == "none" ]] && exit 0
  wait_tunnel
  save_underlay

  local server_ip
  server_ip="$(resolve_server_ipv4)"
  [[ -n "$server_ip" ]] || { echo "无法解析服务端 IPv4 地址：$SERVER" >&2; exit 1; }
  add_server_escape_route "$server_ip"

  case "$ROUTE_MODE" in
    split)
      local net
      for net in $ROUTES; do
        ip -4 route replace "$net" dev "$TUN_NAME"
      done
      ;;
    full)
      # 文档只明确说明“先排除服务端，再让全部流量走 iwan”。
      # 对点隧道通常允许 default dev；若客户端要求 peer/gateway，应按实际接口调整。
      ip -4 route replace default dev "$TUN_NAME" metric 10
      ;;
  esac
}

down() {
  local server_ip=""
  server_ip="$(resolve_server_ipv4 2>/dev/null || true)"
  case "$ROUTE_MODE" in
    split)
      local net
      for net in $ROUTES; do
        ip -4 route del "$net" dev "$TUN_NAME" 2>/dev/null || true
      done
      ;;
    full)
      ip -4 route del default dev "$TUN_NAME" 2>/dev/null || true
      ;;
  esac
  [[ -n "$server_ip" ]] && ip -4 route del "$server_ip/32" 2>/dev/null || true
}

case "$ACTION" in
  up) up ;;
  down) down ;;
  *) echo "用法：$0 up|down" >&2; exit 2 ;;
esac
EOF
  chmod 0755 /usr/local/sbin/sdwan-route-manager
}

write_systemd_service() {
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Panabit IWAN SD-WAN Linux Client
Wants=network-online.target
After=network-online.target
ConditionPathExists=$BIN_PATH
ConditionPathExists=$CONFIG_FILE

[Service]
Type=simple
ExecStart=$BIN_PATH -f $CONFIG_FILE
ExecStartPost=/usr/local/sbin/sdwan-route-manager up
ExecStopPost=/usr/local/sbin/sdwan-route-manager down
Restart=on-failure
RestartSec=5
TimeoutStartSec=90
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME.service"
}

main() {
  require_root
  need_cmd ip
  need_cmd systemctl
  need_cmd getent
  detect_arch
  install -d -m 0755 "$INSTALL_DIR"

  if [[ -e "$CONFIG_FILE" ]]; then
    cp -a "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%Y%m%d-%H%M%S)"
    warn "旧配置已备份"
  fi

  download_client
  collect_config
  write_config
  collect_routes
  write_route_helper
  write_systemd_service

  log "安装完成，正在启动服务"
  if systemctl restart "$SERVICE_NAME.service"; then
    sleep 2
    systemctl --no-pager --full status "$SERVICE_NAME.service" || true
    echo
    ip -br addr show "$TUN_NAME" 2>/dev/null || true
    ip -4 route show
  else
    warn "服务启动失败，请执行：journalctl -u $SERVICE_NAME -n 100 --no-pager"
    exit 1
  fi
}

main "$@"
