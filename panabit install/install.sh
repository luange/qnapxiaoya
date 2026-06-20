#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ============================================================
# Panabit Linux 自动安装器（Linux / macOS 控制端）
#
# 使用方式：
#   1. 把本脚本、Panabit 压缩包以及可选配置文件放在同一目录
#   2. 修改下面的 PACKAGE_GLOB，或直接填写 PACKAGE_FILE
#   3. 在 macOS/Linux 执行：
#        chmod +x panabit-deploy.sh
#        ./panabit-deploy.sh
#
# 也可以直接在目标 Linux 本机执行，选择“本机安装”。
# ============================================================

VERSION="1.1.0"

# GitHub 仓库目录：
# https://github.com/luange/qnapxiaoya/tree/main/panabit%20install
REPO_OWNER="luange"
REPO_NAME="qnapxiaoya"
REPO_BRANCH="main"
REPO_DIR="panabit install"
RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/panabit%20install"

# 更新 Panabit OS 时，通常只需修改这一行。
PANABIT_PACKAGE="PanabitFREE_TANGr7p9_20260617_Linux3.tar.gz"

# 是否从仓库下载并覆盖配置文件：1=是，0=否
DOWNLOAD_ACCOUNT_CONF=1
DOWNLOAD_HTTPD_CONF=1
DOWNLOAD_PANABIT_CONF=1

# 下载缓存目录
REPO_CACHE_DIR="/tmp/panabit-repo-install"


# ===== 只需要重点修改这里 =====
# 精确指定文件名时填写，例如：
# PACKAGE_FILE="PanabitFREE_TANGr6p3_20240905_Linux3.tar.gz"
PACKAGE_FILE="$REPO_CACHE_DIR/$PANABIT_PACKAGE"

# 不填写 PACKAGE_FILE 时，按下面的名称检索。
# 更新 Panabit OS 版本后，只需替换压缩包，或修改此匹配名。
PACKAGE_GLOB="PanabitFREE_TANGr*_Linux3.tar*.gz"

# OEM 版本可改成：
# PACKAGE_GLOB="PanabitOEM_TANGr*_Linux3.tar*.gz"

REMOTE_WORKDIR="/tmp/panabit-installer"
INSTALL_DIR="/usr/panabit"
CONF_DIR="/usr/panaetc"
LOG_DIR="/usr/panalog"
SERVICE_NAME="panabit"
DEFAULT_SSH_PORT="22"
DEFAULT_ADMIN_PORT="60443"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BASENAME="$(basename "$0")"

C_RESET='\033[0m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'
C_CYAN='\033[1;36m'

log()  { printf "${C_GREEN}[+] %s${C_RESET}\n" "$*"; }
info() { printf "${C_CYAN}[i] %s${C_RESET}\n" "$*"; }
warn() { printf "${C_YELLOW}[!] %s${C_RESET}\n" "$*" >&2; }
die()  { printf "${C_RED}[x] %s${C_RESET}\n" "$*" >&2; exit 1; }

pause() {
  echo
  read -r -p "按 Enter 继续..." _
}

prompt_default() {
  local var="$1" text="$2" default="$3" value
  read -r -p "$text [$default]: " value
  printf -v "$var" '%s' "${value:-$default}"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}

install_download_tool() {
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    return 0
  fi

  warn "未检测到 curl/wget，尝试自动安装 curl"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl ca-certificates
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl ca-certificates
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache curl ca-certificates
  else
    die "无法自动安装 curl，请先手工安装 curl 或 wget"
  fi
}

download_url() {
  local url="$1" target="$2"
  local tmp="${target}.part"

  mkdir -p "$(dirname "$target")"
  rm -f "$tmp"

  if command -v curl >/dev/null 2>&1; then
    curl -fL \
      --retry 4 \
      --retry-delay 2 \
      --connect-timeout 20 \
      --speed-time 60 \
      --speed-limit 1024 \
      "$url" -o "$tmp"
  else
    wget --timeout=30 --tries=4 -O "$tmp" "$url"
  fi

  [[ -s "$tmp" ]] || die "下载文件为空：$url"
  mv -f "$tmp" "$target"
}

download_repo_assets() {
  install_download_tool
  rm -rf "$REPO_CACHE_DIR"
  mkdir -p "$REPO_CACHE_DIR"

  log "从 GitHub 仓库下载 Panabit 安装文件"
  info "仓库目录：${REPO_OWNER}/${REPO_NAME}/${REPO_DIR}"
  info "系统包：$PANABIT_PACKAGE"

  download_url \
    "$RAW_BASE/$PANABIT_PACKAGE" \
    "$REPO_CACHE_DIR/$PANABIT_PACKAGE"

  if [[ "$DOWNLOAD_ACCOUNT_CONF" == "1" ]]; then
    download_url "$RAW_BASE/account.conf" "$REPO_CACHE_DIR/account.conf"
  fi

  if [[ "$DOWNLOAD_HTTPD_CONF" == "1" ]]; then
    download_url "$RAW_BASE/httpd.conf" "$REPO_CACHE_DIR/httpd.conf"
  fi

  if [[ "$DOWNLOAD_PANABIT_CONF" == "1" ]]; then
    download_url "$RAW_BASE/panabit.conf" "$REPO_CACHE_DIR/panabit.conf"
  fi

  log "仓库文件下载完成"
}

verify_repo_assets() {
  [[ -s "$REPO_CACHE_DIR/$PANABIT_PACKAGE" ]] \
    || die "系统包下载失败：$PANABIT_PACKAGE"

  tar -tzf "$REPO_CACHE_DIR/$PANABIT_PACKAGE" >/dev/null 2>&1 \
    || die "下载的系统包不是有效 tar.gz：$PANABIT_PACKAGE"

  tar -tzf "$REPO_CACHE_DIR/$PANABIT_PACKAGE" \
    | grep -Eq '(^|/)ipeinstall$' \
    || die "系统包中没有找到 ipeinstall"

  log "系统包完整性与目录结构检查通过"
}

is_target_linux() {
  [[ "$(uname -s)" == "Linux" ]]
}

find_package() {
  local candidate=""

  if [[ -n "$PACKAGE_FILE" ]]; then
    if [[ -f "$PACKAGE_FILE" ]]; then
      candidate="$(cd "$(dirname "$PACKAGE_FILE")" && pwd)/$(basename "$PACKAGE_FILE")"
    elif [[ -f "$SCRIPT_DIR/$PACKAGE_FILE" ]]; then
      candidate="$SCRIPT_DIR/$PACKAGE_FILE"
    else
      die "找不到指定安装包：$PACKAGE_FILE"
    fi
  else
    # shellcheck disable=SC2086
    candidate="$(
      find "$SCRIPT_DIR" -maxdepth 1 -type f -name "$PACKAGE_GLOB" \
        -print0 2>/dev/null \
        | xargs -0 ls -1t 2>/dev/null \
        | head -n1 || true
    )"

    [[ -n "$candidate" ]] || die \
      "脚本目录中没有匹配安装包：$PACKAGE_GLOB
请修改脚本顶部 PACKAGE_GLOB，或填写 PACKAGE_FILE。"
  fi

  PACKAGE_PATH="$candidate"
  PACKAGE_NAME="$(basename "$PACKAGE_PATH")"
  log "检测到安装包：$PACKAGE_NAME"
}


find_repo_optional_files() {
  OPTIONAL_FILES=()
  local f
  for f in account.conf httpd.conf panabit.conf joskmc; do
    if [[ -f "$REPO_CACHE_DIR/$f" ]]; then
      OPTIONAL_FILES+=("$REPO_CACHE_DIR/$f")
      info "检测到仓库文件：$f"
    fi
  done
}

find_optional_files() {
  OPTIONAL_FILES=()

  local f
  for f in account.conf httpd.conf panabit.conf joskmc; do
    if [[ -f "$SCRIPT_DIR/$f" ]]; then
      OPTIONAL_FILES+=("$SCRIPT_DIR/$f")
      info "检测到可选文件：$f"
    fi
  done
}

validate_package() {
  require_command tar

  tar -tzf "$PACKAGE_PATH" >/dev/null 2>&1 \
    || die "安装包不是有效的 tar.gz 文件：$PACKAGE_PATH"

  local installer_count
  installer_count="$(tar -tzf "$PACKAGE_PATH" | grep -Ec '(^|/)ipeinstall$' || true)"
  (( installer_count >= 1 )) \
    || die "安装包内未找到 ipeinstall，不能确认是 Panabit Linux 安装包"
}

remote_shell() {
  local command="$1"
  ssh \
    -p "$SSH_PORT" \
    -o ConnectTimeout=15 \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=3 \
    "$SSH_USER@$SERVER_IP" \
    "$command"
}

remote_shell_tty() {
  ssh \
    -tt \
    -p "$SSH_PORT" \
    -o ConnectTimeout=15 \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=3 \
    "$SSH_USER@$SERVER_IP" \
    "$@"
}

test_remote_connection() {
  log "测试 SSH 连接"
  remote_shell "printf 'SSH_OK\n'; uname -s; uname -m; id -u" \
    | tee /tmp/panabit-ssh-test.$$

  grep -q "SSH_OK" /tmp/panabit-ssh-test.$$ \
    || die "SSH 测试失败"
  grep -q "^Linux$" /tmp/panabit-ssh-test.$$ \
    || die "目标系统不是 Linux"
  grep -q "^0$" /tmp/panabit-ssh-test.$$ \
    || die "远端必须直接使用 root 登录，或改用具备免密 sudo 的账号"

  rm -f /tmp/panabit-ssh-test.$$
}

upload_files() {
  log "创建远端临时目录：$REMOTE_WORKDIR"
  remote_shell "rm -rf '$REMOTE_WORKDIR' && mkdir -p '$REMOTE_WORKDIR'"

  local upload_list=("$PACKAGE_PATH")
  upload_list+=("${OPTIONAL_FILES[@]}")

  log "上传安装包和配置文件"
  scp \
    -P "$SSH_PORT" \
    -o ConnectTimeout=15 \
    "${upload_list[@]}" \
    "$SSH_USER@$SERVER_IP:$REMOTE_WORKDIR/"
}

write_remote_installer_local() {
  REMOTE_INSTALLER_LOCAL="$(mktemp -t panabit-remote-install.XXXXXX.sh)"

  cat > "$REMOTE_INSTALLER_LOCAL" <<'REMOTE_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

WORKDIR="${1:?缺少工作目录}"
PACKAGE_NAME="${2:?缺少安装包名称}"
ADMIN_IFACE="${3:?缺少管理网卡名称}"
ADMIN_PORT="${4:-60443}"
INSTALL_DIR="/usr/panabit"
CONF_DIR="/usr/panaetc"
LOG_DIR="/usr/panalog"
SERVICE_NAME="panabit"

C_RESET='\033[0m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[1;31m'

log()  { printf "${C_GREEN}[+] %s${C_RESET}\n" "$*"; }
warn() { printf "${C_YELLOW}[!] %s${C_RESET}\n" "$*" >&2; }
die()  { printf "${C_RED}[x] %s${C_RESET}\n" "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "必须以 root 运行"
[[ "$(uname -s)" == "Linux" ]] || die "目标系统必须是 Linux"
[[ "$(uname -m)" == "x86_64" ]] || warn "当前架构不是 x86_64：$(uname -m)，二进制可能无法运行"

install_net_tools_if_needed() {
  command -v tar >/dev/null 2>&1 || die "缺少 tar 命令"

  # 至少需要 ip、ifconfig、route 其中一套。缺少时自动安装。
  if command -v ip >/dev/null 2>&1 ||
     command -v ifconfig >/dev/null 2>&1 ||
     command -v route >/dev/null 2>&1; then
    return 0
  fi

  warn "没有检测到网络查询命令，尝试自动安装 iproute2/net-tools"

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y iproute2 net-tools
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y iproute net-tools
  elif command -v yum >/dev/null 2>&1; then
    yum install -y iproute net-tools
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache iproute2 net-tools
  else
    die "无法自动安装网络工具，请手工安装 iproute2 或 net-tools"
  fi
}

iface_is_usable() {
  local nic="$1"
  [[ -n "$nic" && "$nic" != "lo" ]] || return 1
  [[ -d "/sys/class/net/$nic" ]] || return 1

  case "$nic" in
    docker*|veth*|br-*|virbr*|cni*|flannel*|tun*|tap*|wg*|iwan*)
      return 1
      ;;
  esac

  [[ "$(cat "/sys/class/net/$nic/operstate" 2>/dev/null || true)" != "down" ]] || return 1
  return 0
}

iface_has_ipv4() {
  local nic="$1"

  if command -v ip >/dev/null 2>&1; then
    ip -4 -o addr show dev "$nic" scope global 2>/dev/null | grep -q .
    return
  fi

  if command -v ifconfig >/dev/null 2>&1; then
    ifconfig "$nic" 2>/dev/null |
      awk '/inet / && $2 != "127.0.0.1" {found=1} END{exit !found}'
    return
  fi

  return 1
}

detect_default_iface() {
  local nic=""

  # 方法 1：现代 iproute2，最可靠。
  if command -v ip >/dev/null 2>&1; then
    nic="$(
      ip -4 route show default 2>/dev/null |
        awk '{
          for (i=1;i<=NF;i++) {
            if ($i=="dev") {print $(i+1); exit}
          }
        }'
    )"
    if iface_is_usable "$nic" && iface_has_ipv4 "$nic"; then
      printf '%s\n' "$nic"
      return 0
    fi

    # 某些系统 default 表里异常，改用实际路由探测。
    nic="$(
      ip -4 route get 1.1.1.1 2>/dev/null |
        awk '{
          for (i=1;i<=NF;i++) {
            if ($i=="dev") {print $(i+1); exit}
          }
        }'
    )"
    if iface_is_usable "$nic" && iface_has_ipv4 "$nic"; then
      printf '%s\n' "$nic"
      return 0
    fi
  fi

  # 方法 2：传统 route -n。
  if command -v route >/dev/null 2>&1; then
    nic="$(
      route -n 2>/dev/null |
        awk '$1=="0.0.0.0" && $8!="" {print $8; exit}'
    )"
    if iface_is_usable "$nic" && iface_has_ipv4 "$nic"; then
      printf '%s\n' "$nic"
      return 0
    fi
  fi

  # 方法 3：直接读取内核路由表，无需额外命令。
  if [[ -r /proc/net/route ]]; then
    nic="$(
      awk '$2=="00000000" && and(strtonum("0x"$4),2) {print $1; exit}' \
        /proc/net/route 2>/dev/null || true
    )"
    if iface_is_usable "$nic" && iface_has_ipv4 "$nic"; then
      printf '%s\n' "$nic"
      return 0
    fi
  fi

  # 方法 4：遍历所有真实网卡，选择第一个处于 UP 且有全局 IPv4 的接口。
  local path
  for path in /sys/class/net/*; do
    nic="${path##*/}"
    if iface_is_usable "$nic" && iface_has_ipv4 "$nic"; then
      printf '%s\n' "$nic"
      return 0
    fi
  done

  return 1
}

get_iface_ipv4() {
  local nic="$1"

  if command -v ip >/dev/null 2>&1; then
    ip -4 -o addr show dev "$nic" scope global 2>/dev/null |
      awk 'NR==1 {print $4}'
    return
  fi

  if command -v ifconfig >/dev/null 2>&1; then
    local ip mask
    ip="$(
      ifconfig "$nic" 2>/dev/null |
        awk '/inet / {
          for (i=1;i<=NF;i++) {
            if ($i=="inet") {print $(i+1); exit}
            if ($i ~ /^addr:/) {sub(/^addr:/,"",$i); print $i; exit}
          }
        }'
    )"
    mask="$(
      ifconfig "$nic" 2>/dev/null |
        awk '/inet / {
          for (i=1;i<=NF;i++) {
            if ($i=="netmask") {print $(i+1); exit}
            if ($i ~ /^Mask:/) {sub(/^Mask:/,"",$i); print $i; exit}
          }
        }'
    )"
    [[ -n "$ip" ]] && printf '%s|%s\n' "$ip" "$mask"
    return
  fi
}

get_default_gateway() {
  local nic="$1"

  if command -v ip >/dev/null 2>&1; then
    ip -4 route show default 2>/dev/null |
      awk -v dev="$nic" '
        $0 ~ ("dev " dev) {
          for (i=1;i<=NF;i++) if ($i=="via") {print $(i+1); exit}
        }
      '
    return
  fi

  if command -v route >/dev/null 2>&1; then
    route -n 2>/dev/null |
      awk -v dev="$nic" '$1=="0.0.0.0" && $8==dev {print $2; exit}'
    return
  fi

  if [[ -r /proc/net/route ]]; then
    local hex
    hex="$(awk -v dev="$nic" '$1==dev && $2=="00000000"{print $3;exit}' /proc/net/route)"
    if [[ ${#hex} -eq 8 ]]; then
      printf '%d.%d.%d.%d\n' \
        "$((16#${hex:6:2}))" "$((16#${hex:4:2}))" \
        "$((16#${hex:2:2}))" "$((16#${hex:0:2}))"
    fi
  fi
}

mask_to_prefix() {
  local mask="$1"
  local prefix=0 octet bits
  IFS=. read -r -a octets <<< "$mask"
  for octet in "${octets[@]}"; do
    case "$octet" in
      255) bits=8 ;; 254) bits=7 ;; 252) bits=6 ;; 248) bits=5 ;;
      240) bits=4 ;; 224) bits=3 ;; 192) bits=2 ;; 128) bits=1 ;;
      0) bits=0 ;; *) return 1 ;;
    esac
    prefix=$((prefix + bits))
  done
  printf '%s\n' "$prefix"
}

install_net_tools_if_needed

if [[ -z "$ADMIN_IFACE" || "$ADMIN_IFACE" == "auto" ]]; then
  ADMIN_IFACE="$(detect_default_iface)" \
    || die "自动识别管理网卡失败，请重新运行并手工输入网卡名"
  log "自动识别管理网卡：$ADMIN_IFACE"
else
  iface_is_usable "$ADMIN_IFACE" \
    || die "管理网卡不存在或不适合作为管理口：$ADMIN_IFACE"
  iface_has_ipv4 "$ADMIN_IFACE" \
    || die "管理网卡没有可用 IPv4 地址：$ADMIN_IFACE"
fi

PACKAGE="$WORKDIR/$PACKAGE_NAME"
[[ -f "$PACKAGE" ]] || die "安装包不存在：$PACKAGE"
tar -tzf "$PACKAGE" >/dev/null 2>&1 || die "安装包校验失败"

ADDR_RESULT="$(get_iface_ipv4 "$ADMIN_IFACE")"

if [[ "$ADDR_RESULT" == *"|"* ]]; then
  ADMIN_IP="${ADDR_RESULT%%|*}"
  ADMIN_MASK="${ADDR_RESULT#*|}"
  ADMIN_PREFIX="$(mask_to_prefix "$ADMIN_MASK" 2>/dev/null || printf '24')"
else
  ADMIN_IP="${ADDR_RESULT%/*}"
  ADMIN_PREFIX="${ADDR_RESULT#*/}"
  [[ "$ADMIN_PREFIX" != "$ADDR_RESULT" ]] || ADMIN_PREFIX="24"
  ADMIN_MASK=""
fi

ADMIN_MAC="$(
  cat "/sys/class/net/$ADMIN_IFACE/address" 2>/dev/null || true
)"
DEFAULT_GW="$(get_default_gateway "$ADMIN_IFACE")"

[[ -n "$ADMIN_IP" ]] || die "管理网卡 $ADMIN_IFACE 没有 IPv4 地址"
[[ -n "$ADMIN_MAC" ]] || die "无法读取管理网卡 MAC 地址"

prefix_to_mask() {
  local prefix="$1"
  local mask="" full=$((prefix / 8)) partial=$((prefix % 8)) i octet
  for i in 0 1 2 3; do
    if (( i < full )); then
      octet=255
    elif (( i == full && partial > 0 )); then
      octet=$((256 - 2 ** (8 - partial)))
    else
      octet=0
    fi
    mask+="${mask:+.}$octet"
  done
  printf '%s\n' "$mask"
}

[[ -n "${ADMIN_MASK:-}" ]] || ADMIN_MASK="$(prefix_to_mask "$ADMIN_PREFIX")"

echo
log "安装前信息"
echo "管理网卡：$ADMIN_IFACE"
echo "管理地址：$ADMIN_IP/$ADMIN_PREFIX"
echo "子网掩码：$ADMIN_MASK"
echo "默认网关：${DEFAULT_GW:-未检测到}"
echo "管理 MAC：$ADMIN_MAC"
echo "管理端口：$ADMIN_PORT"
echo

EXTRACT_DIR="$WORKDIR/extracted"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
tar -xzf "$PACKAGE" -C "$EXTRACT_DIR"

INSTALLER="$(
  find "$EXTRACT_DIR" -type f -name ipeinstall -print -quit
)"
[[ -n "$INSTALLER" ]] || die "解压后未找到 ipeinstall"

PACKAGE_ROOT="$(dirname "$INSTALLER")"
chmod +x "$INSTALLER"

# 安装脚本存在已知变量错误：
#   它读取 gateway，但替换配置时误用了 admin_gateway。
# 安装前生成一个修正版副本，避免网关保持为 2.2.2.2。
PATCHED_INSTALLER="$PACKAGE_ROOT/ipeinstall.auto"
cp -f "$INSTALLER" "$PATCHED_INSTALLER"
sed -i \
  's/\$admin_gateway/\$gateway/g; s/${admin_gateway}/${gateway}/g' \
  "$PATCHED_INSTALLER" || true
chmod +x "$PATCHED_INSTALLER"

if [[ -f /etc/PG.conf ]]; then
  STAMP="$(date +%Y%m%d-%H%M%S)"
  log "备份现有 Panabit 配置"
  mkdir -p "/root/panabit-backup-$STAMP"
  cp -a /etc/PG.conf "/root/panabit-backup-$STAMP/" 2>/dev/null || true
  cp -a "$CONF_DIR" "/root/panabit-backup-$STAMP/" 2>/dev/null || true
fi

log "执行 Panabit 官方安装程序"
cd "$PACKAGE_ROOT"

# 官方脚本检测到旧安装时会询问覆盖，这里只向该问题输入 y。
printf 'y\n' | "$PATCHED_INSTALLER" "$ADMIN_IFACE"

[[ -f /etc/PG.conf ]] || die "安装结束但 /etc/PG.conf 不存在"
[[ -x "$INSTALL_DIR/bin/ipectrl" ]] || die "安装结束但 ipectrl 不存在"

# 用现代 ip 命令重新写入管理口信息，避免旧 ifconfig/route 输出差异。
cat > "$CONF_DIR/ifadmin.conf" <<EOF
ADMIN_IP=$ADMIN_IP
ADMIN_MASK=$ADMIN_MASK
GATEWAY=$DEFAULT_GW
EOF

# 修复配置模板中的地址、网关、MAC。
if [[ -f "$CONF_DIR/panabit.conf" ]]; then
  sed -i \
    -e "s/addr=1\.1\.1\.1/addr=$ADMIN_IP/g" \
    -e "s/gateway=2\.2\.2\.2/gateway=${DEFAULT_GW:-0.0.0.0}/g" \
    -e "s/clonemac=00:00:00:00:00:00/clonemac=$ADMIN_MAC/g" \
    "$CONF_DIR/panabit.conf"
fi

# 覆盖用户提供的可选配置。
for config in account.conf httpd.conf panabit.conf; do
  if [[ -f "$WORKDIR/$config" ]]; then
    log "植入用户配置：$config"
    cp -f "$WORKDIR/$config" "$CONF_DIR/$config"
    chmod 600 "$CONF_DIR/$config" 2>/dev/null || true
  fi
done

# joskmc 是内核驱动诊断工具，不替换 Panabit 主程序。
if [[ -f "$WORKDIR/joskmc" ]]; then
  log "安装 joskmc 诊断工具"
  install -m 0755 "$WORKDIR/joskmc" "$INSTALL_DIR/bin/joskmc"
fi

# 如果用户配置的 httpd.conf 中另有端口，以文件为准。
if [[ -f "$CONF_DIR/httpd.conf" ]]; then
  CONF_PORT="$(awk -F= '$1=="port"{gsub(/[[:space:]]/,"",$2);print $2;exit}' "$CONF_DIR/httpd.conf")"
  [[ -n "$CONF_PORT" ]] && ADMIN_PORT="$CONF_PORT"
fi

log "配置 systemd 开机自启和保活"
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Panabit Network Application Gateway
Wants=network-online.target
After=network-online.target
ConditionPathExists=$INSTALL_DIR/bin/ipectrl

[Service]
Type=forking
ExecStart=$INSTALL_DIR/bin/ipectrl start
ExecStop=$INSTALL_DIR/bin/ipectrl stop
ExecReload=$INSTALL_DIR/bin/ipectrl restart
Restart=on-failure
RestartSec=5
TimeoutStartSec=90
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME.service"

log "放行管理端口：TCP $ADMIN_PORT"
if command -v firewall-cmd >/dev/null 2>&1 &&
   systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-port="${ADMIN_PORT}/tcp" || true
  firewall-cmd --reload || true
elif command -v ufw >/dev/null 2>&1; then
  ufw allow "${ADMIN_PORT}/tcp" || true
elif command -v iptables >/dev/null 2>&1; then
  iptables -C INPUT -p tcp --dport "$ADMIN_PORT" -j ACCEPT 2>/dev/null \
    || iptables -I INPUT -p tcp --dport "$ADMIN_PORT" -j ACCEPT
  warn "iptables 规则已即时加入，但是否持久化取决于目标系统"
else
  warn "未检测到 firewalld、ufw 或 iptables，请自行放行 TCP $ADMIN_PORT"
fi

log "启动 Panabit"
systemctl restart "$SERVICE_NAME.service" || {
  warn "systemd 启动失败，尝试直接启动"
  "$INSTALL_DIR/bin/ipectrl" start
}

sleep 3

echo
echo "================ 安装结果 ================"
systemctl --no-pager --full status "$SERVICE_NAME.service" 2>/dev/null || true
echo
echo "管理地址：https://$ADMIN_IP:$ADMIN_PORT"
echo "管理网卡：$ADMIN_IFACE"
echo "配置目录：$CONF_DIR"
echo "程序目录：$INSTALL_DIR"
echo "日志目录：$LOG_DIR"
echo
echo "常用命令："
echo "  systemctl status $SERVICE_NAME"
echo "  systemctl restart $SERVICE_NAME"
echo "  journalctl -u $SERVICE_NAME -n 100 --no-pager"
echo "  $INSTALL_DIR/bin/ipectrl status"
echo "==========================================="
REMOTE_SCRIPT

  chmod +x "$REMOTE_INSTALLER_LOCAL"
}

upload_remote_installer() {
  write_remote_installer_local
  scp \
    -P "$SSH_PORT" \
    -o ConnectTimeout=15 \
    "$REMOTE_INSTALLER_LOCAL" \
    "$SSH_USER@$SERVER_IP:$REMOTE_WORKDIR/remote-install.sh"
  rm -f "$REMOTE_INSTALLER_LOCAL"
}

remote_preflight() {
  log "远端安装前检查"
  remote_shell_tty \
    "bash '$REMOTE_WORKDIR/remote-install.sh' \
      '$REMOTE_WORKDIR' '$PACKAGE_NAME' '$ADMIN_IFACE' '$ADMIN_PORT'"
}

remote_install_flow() {
  download_repo_assets
  verify_repo_assets
  find_package
  find_repo_optional_files
  validate_package

  echo
  prompt_default SERVER_IP "请输入服务器 IP" ""
  [[ -n "$SERVER_IP" ]] || die "服务器 IP 不能为空"

  prompt_default SSH_PORT "请输入 SSH 端口" "$DEFAULT_SSH_PORT"
  prompt_default SSH_USER "请输入 SSH 用户" "root"
  prompt_default ADMIN_IFACE "请输入 Panabit 管理网卡，输入 auto 自动识别" "auto"
  prompt_default ADMIN_PORT "请输入管理页面 TCP 端口" "$DEFAULT_ADMIN_PORT"

  require_command ssh
  require_command scp

  echo
  info "接下来 SSH 会正常提示输入远端密码；脚本不会保存密码。"
  test_remote_connection
  upload_files
  upload_remote_installer
  remote_preflight

  echo
  log "远程安装流程结束"
}

local_install_flow() {
  [[ "$(uname -s)" == "Linux" ]] || die "本机安装只能在 Linux 上执行"

  download_repo_assets
  verify_repo_assets
  find_package
  find_repo_optional_files
  validate_package

  prompt_default ADMIN_IFACE "请输入 Panabit 管理网卡，输入 auto 自动识别" "auto"
  prompt_default ADMIN_PORT "请输入管理页面 TCP 端口" "$DEFAULT_ADMIN_PORT"

  [[ "$(id -u)" -eq 0 ]] || die "本机安装请用 sudo 或 root 运行"

  rm -rf "$REMOTE_WORKDIR"
  mkdir -p "$REMOTE_WORKDIR"
  cp -f "$PACKAGE_PATH" "$REMOTE_WORKDIR/"
  local f
  for f in "${OPTIONAL_FILES[@]}"; do
    cp -f "$f" "$REMOTE_WORKDIR/"
  done

  write_remote_installer_local
  bash "$REMOTE_INSTALLER_LOCAL" \
    "$REMOTE_WORKDIR" "$PACKAGE_NAME" "$ADMIN_IFACE" "$ADMIN_PORT"
  rm -f "$REMOTE_INSTALLER_LOCAL"
}

show_package_help() {
  cat <<EOF

当前 GitHub 仓库下载设置：

  RAW_BASE="$RAW_BASE"
  PANABIT_PACKAGE="$PANABIT_PACKAGE"

更新 Panabit OS 时：

  1. 把新版 tar.gz 上传到仓库的 panabit install 目录；
  2. 打开本脚本，修改顶部这一行：

     PANABIT_PACKAGE="新的完整文件名.tar.gz"

例如：

  PANABIT_PACKAGE="PanabitFREE_TANGr7p9_20260617_Linux3.tar.gz"

仓库内的 account.conf、httpd.conf、panabit.conf
会在安装时自动下载并植入。

管理网卡默认填写 auto，会依次尝试：
  1. ip route show default
  2. ip route get 1.1.1.1
  3. route -n
  4. /proc/net/route
  5. 遍历 /sys/class/net 中有 IPv4 的真实网卡

因此一般不需要手工输入 eth0、ens18、enp1s0 等名称。
EOF
}

main_menu() {
  while true; do
    clear 2>/dev/null || true
    cat <<EOF
================================================
        Panabit Linux 自动安装器 v$VERSION
================================================
  1. 从 macOS/Linux 远程安装到 Linux
  2. 在当前 Linux 本机安装
  3. 查看仓库和版本配置方法
  0. 退出
================================================
EOF

    read -r -p "请选择: " choice
    case "$choice" in
      1) remote_install_flow; pause ;;
      2) local_install_flow; pause ;;
      3) show_package_help; pause ;;
      0) exit 0 ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

show_local_help() {
  cat <<EOF
Panabit 本地安装器 v$VERSION

用途：
  直接在目标 Linux 服务器本机执行，不经过 SSH/SCP。

准备：
  本脚本会直接从你的 GitHub 仓库下载 Panabit 安装包和配置文件。
  仓库目录：
    https://github.com/luange/qnapxiaoya/tree/main/panabit%20install

当前安装包：
  $PANABIT_PACKAGE

常用命令：
  sudo ./$BASENAME install
  sudo ./$BASENAME check
  sudo ./$BASENAME download
  ./$BASENAME package-help
EOF
}

local_precheck() {
  [[ "$(uname -s)" == "Linux" ]] || die "本地安装器只能在 Linux 目标服务器上运行"
  [[ "$(id -u)" -eq 0 ]] || die "请使用 root 或 sudo 运行"

  find_package
  find_optional_files
  validate_package

  echo
  echo "========== 本地安装前检查 =========="
  echo "系统：$(uname -s) $(uname -r)"
  echo "架构：$(uname -m)"
  echo "安装包：$PACKAGE_NAME"
  echo "脚本目录：$SCRIPT_DIR"
  echo

  if command -v ip >/dev/null 2>&1; then
    echo "---- 默认路由 ----"
    ip -4 route show default || true
    echo
    echo "---- IPv4 网卡 ----"
    ip -4 -br addr || true
  elif command -v ifconfig >/dev/null 2>&1; then
    echo "---- 网卡信息 ----"
    ifconfig -a || true
  else
    warn "当前没有 ip/ifconfig，正式安装时会尝试自动安装网络工具"
  fi

  echo
  echo "---- 可选配置文件 ----"
  if ((${#OPTIONAL_FILES[@]})); then
    printf '%s\n' "${OPTIONAL_FILES[@]}"
  else
    echo "未检测到"
  fi
  echo "===================================="
}

local_direct_install() {
  [[ "$(uname -s)" == "Linux" ]] || die "本地安装器只能在 Linux 目标服务器上运行"
  [[ "$(id -u)" -eq 0 ]] || die "请使用 sudo 或 root 运行"

  find_package
  find_optional_files
  validate_package

  echo
  info "管理网卡默认使用 auto 自动识别。"
  prompt_default ADMIN_IFACE "请输入 Panabit 管理网卡，输入 auto 自动识别" "auto"
  prompt_default ADMIN_PORT "请输入管理页面 TCP 端口" "$DEFAULT_ADMIN_PORT"

  echo
  echo "即将执行本地安装："
  echo "  安装包：$PACKAGE_NAME"
  echo "  管理网卡：$ADMIN_IFACE"
  echo "  管理端口：$ADMIN_PORT"
  echo

  read -r -p "确认开始安装？输入 YES: " confirm
  [[ "$confirm" == "YES" ]] || {
    info "已取消安装"
    return 0
  }

  rm -rf "$REMOTE_WORKDIR"
  mkdir -p "$REMOTE_WORKDIR"
  cp -f "$PACKAGE_PATH" "$REMOTE_WORKDIR/"

  local f
  for f in "${OPTIONAL_FILES[@]}"; do
    cp -f "$f" "$REMOTE_WORKDIR/"
  done

  write_remote_installer_local
  bash "$REMOTE_INSTALLER_LOCAL" \
    "$REMOTE_WORKDIR" "$PACKAGE_NAME" "$ADMIN_IFACE" "$ADMIN_PORT"
  rm -f "$REMOTE_INSTALLER_LOCAL"

  echo
  log "本地安装执行完毕"
}

local_menu() {
  while true; do
    clear 2>/dev/null || true
    cat <<EOF
================================================
       Panabit Linux 本地安装器 v$VERSION
================================================
  1. 开始本地安装
  2. 安装前检查
  3. 查看仓库和版本配置方法
  4. 查看帮助
  0. 退出
================================================
EOF

    read -r -p "请选择: " choice
    case "$choice" in
      1) local_direct_install; pause ;;
      2) local_precheck; pause ;;
      3) show_package_help; pause ;;
      4) show_local_help; pause ;;
      0) exit 0 ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

case "${1:-menu}" in
  install|local)
    local_direct_install
    ;;
  check)
    local_precheck
    ;;
  download)
    [[ "$(id -u)" -eq 0 ]] || die "请使用 root 或 sudo 运行"
    download_repo_assets
    verify_repo_assets
    find_repo_optional_files
    log "文件已下载到：$REPO_CACHE_DIR"
    ;;
  package-help)
    show_package_help
    ;;
  menu)
    local_menu
    ;;
  -h|--help|help)
    show_local_help
    ;;
  *)
    die "未知参数：$1"
    ;;
esac

