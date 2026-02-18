#!/usr/bin/env bash
set -euo pipefail

SERVICES=("mihomo" "tor@default" "i2pd")
UA="clash-verge/v2.4.0"
TMP_CONFIG="/tmp/mihomo_config.yaml"
TARGET_CONFIG="/home/black/mihomo/config.yaml"
LOCAL_CONFIG="/etc/mihomo/config.yaml"
NET_IFACE="enp0s2"
TRANSFER_MOUNT_DIR="/tmp/blackbox_local_config"
TRANSFER_FS_TAG="blackbox_localtmp"
LANGUAGE="${LANGUAGE:-}"
NO_COLOR="${NO_COLOR:-}"
VM_IP=""

COLOR_RESET="\033[0m"
COLOR_CYAN="\033[36m"
COLOR_YELLOW="\033[33m"
COLOR_GREEN="\033[32m"
COLOR_RED="\033[31m"
COLOR_DIM="\033[2m"

if [[ -n "${NO_COLOR}" ]] || [[ ! -t 1 ]]; then
  COLOR_RESET=""
  COLOR_CYAN=""
  COLOR_YELLOW=""
  COLOR_GREEN=""
  COLOR_RED=""
  COLOR_DIM=""
fi

set_language() {
  local arg_lang=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lang)
        shift
        arg_lang="${1:-}"
        ;;
      --lang=*)
        arg_lang="${1#*=}"
        ;;
    esac
    shift || break
  done

  if [[ -n "${arg_lang}" ]]; then
    LANGUAGE="${arg_lang}"
  elif [[ -z "${LANGUAGE}" ]]; then
    local choice=""
    echo "Select language / 选择语言: [1] 中文  [2] English"
    read -r -p "Choice (default 1): " choice
    case "${choice}" in
      2|en|EN|English|english) LANGUAGE="en" ;;
      *) LANGUAGE="zh" ;;
    esac
  fi
}

declare -A MSG_ZH
declare -A MSG_EN

MSG_ZH[prepare]="准备执行配置..."
MSG_ZH[enable_services]="启用服务..."
MSG_ZH[start_services]="启动服务中..."
MSG_ZH[ask_download]="是否需要从指定地址下载 mihomo 订阅文件?"
MSG_ZH[prompt_yesno]="输入 y 继续，输入 n 跳过: "
MSG_ZH[prompt_url]="请输入订阅地址 (http/https): "
MSG_ZH[empty_url]="地址为空，返回上一级。"
MSG_ZH[invalid_url]="地址不合法，只接受 http/https。"
MSG_ZH[skip_download]="跳过下载。"
MSG_ZH[downloading]="正在下载配置..."
MSG_ZH[loading_local]="使用本地配置文件..."
MSG_ZH[loading_transfer]="进入本地配置传输模式..."
MSG_ZH[local_missing]="本地配置文件不存在：%s"
MSG_ZH[target_missing]="目标配置文件不存在：%s"
MSG_ZH[iface_missing]="未检测到网卡 %s，切换为本地配置传输模式。"
MSG_ZH[mount_prepare]="准备挂载本地配置目录..."
MSG_ZH[mount_failed]="挂载失败：%s"
MSG_ZH[transfer_missing]="挂载目录中未找到配置文件：%s"
MSG_ZH[imported_shutdown]="配置已导入，系统即将关机。"
MSG_ZH[shutdown_countdown]="将在 %s 秒后关机..."
MSG_ZH[compare_hash]="正在比对默认配置与当前配置校验值..."
MSG_ZH[hash_same]="继续使用当前配置。"
MSG_ZH[hash_diff_use_existing]="继续使用先前从本地导入并修正过的配置。"
MSG_ZH[reuse_existing_cfg]="跳过配置修正，继续使用当前配置。"
MSG_ZH[yaml_invalid]="下载内容不像 YAML，已终止。"
MSG_ZH[changed_mixed]="已修改 mixed-port 为 7890。"
MSG_ZH[changed_allow]="已修改 allow-lan 为 true。"
MSG_ZH[changed_ipv6]="已修改 ipv6 为 true。"
MSG_ZH[changed_ext]="已修改 external-controller 为 %s。"
MSG_ZH[no_change]="配置已符合要求，无需修改。"
MSG_ZH[copy_cfg]="正在复制配置..."
MSG_ZH[done]="完成。"
MSG_ZH[svc_enable]="启用 %s ..."
MSG_ZH[svc_start]="启动 %s..."
MSG_ZH[legal_title]="法律与免责声明"
MSG_ZH[legal_warn]="本项目仅用于合法授权的测试、研究与教育目的。"
MSG_ZH[legal_warn2]="使用者须自行遵守所在地法律，所有风险与责任由使用者承担。"
MSG_ZH[tor_wait]="等待 Tor 就绪(100%)..."
MSG_ZH[tor_ready]="Tor 已就绪(100%)。"
MSG_ZH[tor_timeout]="等待 Tor 超时，继续执行。"
MSG_ZH[tor_logs]="实时输出 Tor 日志："
MSG_ZH[ports_report]="监听端口信息："
MSG_ZH[ports_tor]="Tor Socks: %s:9050"
MSG_ZH[ports_i2p_http]="i2pd HTTP: %s:4444"
MSG_ZH[ports_i2p_socks]="i2pd Socks: %s:4447"
MSG_ZH[ports_i2p_web]="i2pd WEB 控制台: %s:7070"
MSG_ZH[ports_mihomo]="mihomo 外部管理控制台: %s:9090"
MSG_ZH[host_connect_hint]="现在可回到宿主机连接 BlackBox 容器代理。"
MSG_ZH[next_action]="下一步操作："
MSG_ZH[next_action_prompt]="输入 1 关闭 BlackBox，输入 2 回到 Shell: "
MSG_ZH[action_shutdown]="立即关闭 BlackBox..."
MSG_ZH[action_shell]="已返回 Shell。"
MSG_ZH[action_invalid]="无效输入，请输入 1 或 2。"
MSG_ZH[error_ip]="获取IP失败。请检查crosvm网络设置"

MSG_EN[prepare]="Preparing configuration..."
MSG_EN[enable_services]="Enabling services..."
MSG_EN[start_services]="Starting services..."
MSG_EN[ask_download]="Download mihomo subscription from a URL?"
MSG_EN[prompt_yesno]="Enter y to continue, n to skip: "
MSG_EN[prompt_url]="Enter subscription URL (http/https): "
MSG_EN[empty_url]="Empty URL, going back."
MSG_EN[invalid_url]="Invalid URL, only http/https accepted."
MSG_EN[skip_download]="Skip download."
MSG_EN[downloading]="Downloading config..."
MSG_EN[loading_local]="Using local config file..."
MSG_EN[loading_transfer]="Switching to local config transfer mode..."
MSG_EN[local_missing]="Local config file not found: %s"
MSG_EN[target_missing]="Target config file not found: %s"
MSG_EN[iface_missing]="Network interface %s not found, switching to local transfer mode."
MSG_EN[mount_prepare]="Preparing local config mount..."
MSG_EN[mount_failed]="Mount failed: %s"
MSG_EN[transfer_missing]="Config file not found in mounted directory: %s"
MSG_EN[imported_shutdown]="Config imported. System will shut down."
MSG_EN[shutdown_countdown]="Shutting down in %s seconds..."
MSG_EN[compare_hash]="Comparing checksums between default and current config..."
MSG_EN[hash_same]="Now using default config."
MSG_EN[hash_diff_use_existing]="Now using previously imported and fixed config."
MSG_EN[reuse_existing_cfg]="Skip config rewrite and continue with current config."
MSG_EN[yaml_invalid]="Downloaded content doesn't look like YAML. Abort."
MSG_EN[changed_mixed]="Updated mixed-port to 7890."
MSG_EN[changed_allow]="Updated allow-lan to true."
MSG_EN[changed_ipv6]="Updated ipv6 to true."
MSG_EN[changed_ext]="Updated external-controller to %s."
MSG_EN[no_change]="Config already matches required values."
MSG_EN[copy_cfg]="Copying config..."
MSG_EN[done]="Done."
MSG_EN[svc_enable]="Enabling %s..."
MSG_EN[svc_start]="Starting %s..."
MSG_EN[legal_title]="Legal & Disclaimer"
MSG_EN[legal_warn]="For authorized testing, research, and education only."
MSG_EN[legal_warn2]="You are solely responsible for legal compliance and all risks."
MSG_EN[tor_wait]="Waiting for Tor readiness (100%)..."
MSG_EN[tor_ready]="Tor is ready (100%)."
MSG_EN[tor_timeout]="Timed out waiting for Tor, continuing."
MSG_EN[tor_logs]="Live Tor logs:"
MSG_EN[ports_report]="Listening ports:"
MSG_EN[ports_tor]="Tor Socks: %s:9050"
MSG_EN[ports_i2p_http]="i2pd HTTP: %s:4444"
MSG_EN[ports_i2p_socks]="i2pd Socks: %s:4447"
MSG_EN[ports_i2p_web]="i2pd Web Console: %s:7070"
MSG_EN[ports_mihomo]="mihomo External Controller: %s:9090"
MSG_EN[host_connect_hint]="You can now return to host and connect to the BlackBox container proxy."
MSG_EN[next_action]="Next action:"
MSG_EN[next_action_prompt]="Enter 1 to power off BlackBox, 2 to return to shell: "
MSG_EN[action_shutdown]="Powering off BlackBox now..."
MSG_EN[action_shell]="Returned to shell."
MSG_EN[action_invalid]="Invalid input, please enter 1 or 2."
MSG_EN[error_ip]="error getting VM's IP. Please check network setup of crosvm"

msg() {
  local key="$1"
  shift
  case "${key}" in
    banner)
      cat <<'EOF'
   (   (                )   (              
 ( )\  )\    )       ( /( ( )\          )  
 )((_)((_)( /(   (   )\()))((_)  (   ( /(  
((_)_  _  )(_))  )\ ((_)\((_)_   )\  )\()) 
 | _ )| |((_)_  ((_)| |(_)| _ ) ((_)((_)\  
 | _ \| |/ _` |/ _| | / / | _ \/ _ \\ \ /  
 |___/|_|\__,_|\__| |_\_\ |___/\___//_\_\  
EOF
      return
      ;;
    brand)
      if [[ "${LANGUAGE}" == "zh" ]]; then
        echo "BlackBox / 匿盒"
      else
        echo "BlackBox"
      fi
      return
      ;;
    step)
      if [[ "${LANGUAGE}" == "zh" ]]; then
        printf "步骤 %s/%s: %s\n" "$1" "$2" "$3"
      else
        printf "Step %s/%s: %s\n" "$1" "$2" "$3"
      fi
      return
      ;;
  esac

  local template=""
  if [[ "${LANGUAGE}" == "zh" ]]; then
    template="${MSG_ZH[${key}]-}"
  else
    template="${MSG_EN[${key}]-}"
  fi

  if [[ -z "${template}" ]]; then
    return
  fi

  if [[ $# -gt 0 ]]; then
    printf "${template}\n" "$@"
  else
    printf '%s\n' "${template}"
  fi
}

banner() {
  echo -e "${COLOR_CYAN}============================================================${COLOR_RESET}"
  echo -e "${COLOR_CYAN}$(msg banner)${COLOR_RESET}"
  echo -e "${COLOR_CYAN}$(msg brand)${COLOR_RESET}"
  echo -e "${COLOR_CYAN}============================================================${COLOR_RESET}"
  legal_notice
  echo -e "${COLOR_CYAN}============================================================${COLOR_RESET}"
}

legal_notice() {
  echo -e "${COLOR_YELLOW}============================================================${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}$(msg legal_title)${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}$(msg legal_warn)${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}$(msg legal_warn2)${COLOR_RESET}"
}

info() {
  echo -e "${COLOR_CYAN}[i]${COLOR_RESET} $*"
}

warn() {
  echo -e "${COLOR_YELLOW}[!]${COLOR_RESET} $*"
}

ok() {
  echo -e "${COLOR_GREEN}[+]${COLOR_RESET} $*"
}

err() {
  echo -e "${COLOR_RED}[x]${COLOR_RESET} $*" >&2
}

detect_vm_ip() {
  local ip=""

  if command -v ip >/dev/null 2>&1; then
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  fi

  if [[ -z "${ip}" ]] && command -v hostname >/dev/null 2>&1; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi

  if [[ -z "${ip}" ]]; then
    err "$(msg error_ip)"
    ip="192.168.8.2"
  fi

  echo "${ip}"
}

net_iface_exists() {
  local iface="$1"
  if command -v ip >/dev/null 2>&1; then
    ip link show "${iface}" >/dev/null 2>&1
    return $?
  fi
  return 1
}

setup_local_transfer_mode() {
  info "$(msg mount_prepare)"
  mkdir -p "${TRANSFER_MOUNT_DIR}"

  if command -v mountpoint >/dev/null 2>&1 && mountpoint -q "${TRANSFER_MOUNT_DIR}"; then
    return 0
  fi

  if ! mount -t virtiofs "${TRANSFER_FS_TAG}" "${TRANSFER_MOUNT_DIR}"; then
    err "$(msg mount_failed "${TRANSFER_MOUNT_DIR}")"
    return 1
  fi
  return 0
}

wait_for_tor() {
  local timeout_sec=60
  local interval=2
  local elapsed=0
  local log_pid=""

  info "$(msg tor_wait)"
  info "$(msg tor_logs)"
  (
    journalctl -u tor@default -n 20 -f --no-pager -o cat 2>/dev/null | sed -u "s/^/[tor] /"
  ) &
  log_pid=$!
  while [[ "${elapsed}" -lt "${timeout_sec}" ]]; do
    if systemctl is-active --quiet tor@default; then
      if journalctl -u tor@default --no-pager -n 400 -o cat 2>/dev/null | _rg -q "Bootstrapped 100%"; then
        if [[ -n "${log_pid}" ]] && kill -0 "${log_pid}" >/dev/null 2>&1; then
          kill "${log_pid}" >/dev/null 2>&1 || true
          wait "${log_pid}" 2>/dev/null || true
        fi
        ok "$(msg tor_ready)"
        return 0
      fi
    fi
    sleep "${interval}"
    elapsed=$((elapsed + interval))
  done

  if [[ -n "${log_pid}" ]] && kill -0 "${log_pid}" >/dev/null 2>&1; then
    kill "${log_pid}" >/dev/null 2>&1 || true
    wait "${log_pid}" 2>/dev/null || true
  fi
  warn "$(msg tor_timeout)"
  return 0
}

report_ports() {
  info "$(msg ports_report)"
  ok "$(msg ports_tor "${VM_IP}")"
  ok "$(msg ports_i2p_http "${VM_IP}")"
  ok "$(msg ports_i2p_socks "${VM_IP}")"
  ok "$(msg ports_i2p_web "${VM_IP}")"
  ok "$(msg ports_mihomo "${VM_IP}")"
}

post_run_menu() {
  info "$(msg host_connect_hint)"
  info "$(msg next_action)"
  while true; do
    local action=""
    read -r -p "$(msg next_action_prompt)" action
    case "${action}" in
      1)
        warn "$(msg action_shutdown)"
        shutdown -h now
        exit 0
        ;;
      2)
        ok "$(msg action_shell)"
        return 0
        ;;
      *)
        warn "$(msg action_invalid)"
        ;;
    esac
  done
}

enable_services() {
  service_action enable
}

start_services() {
  service_action start
}

service_action() {
  local action="$1"
  for svc in "${SERVICES[@]}"; do
    local unit="${svc}"
    local msg_key="svc_start"
    if [[ "${action}" == "enable" ]]; then
      msg_key="svc_enable"
      if [[ "${svc}" == "tor@default" ]]; then
        unit="tor"
      fi
    fi
    info "$(msg "${msg_key}" "${unit}")"
    systemctl "${action}" "${unit}"
  done
}

validate_url() {
  local url="$1"
  if [[ "${url}" =~ ^https?://.+ ]]; then
    return 0
  fi
  return 1
}

_rg() {
  if command -v rg >/dev/null 2>&1; then
    rg "$@"
  else
    grep -E "$@"
  fi
}

ensure_kv() {
  local key="$1"
  local desired="$2"
  local file="$3"
  local tmp_file=""

  tmp_file="$(mktemp)"
  if awk -v key="${key}" -v desired="${desired}" '
    BEGIN { found=0; changed=0 }
    {
      if ($0 ~ ("^[ \t]*" key ":[ \t]*")) {
        found=1
        new_line=key ": " desired
        if ($0 != new_line) {
          print new_line
          changed=1
        } else {
          print $0
        }
      } else {
        print $0
      }
    }
    END {
      if (!found) {
        print key ": " desired
        changed=1
      }
      exit(changed ? 0 : 1)
    }
  ' "${file}" > "${tmp_file}"; then
    mv "${tmp_file}" "${file}"
    return 0
  fi

  rm -f "${tmp_file}"
  return 1
}

sanity_check_yaml() {
  local file="$1"
  if grep -qi "<html" "${file}"; then
    return 1
  fi
  if awk '
    /^[ \t]*#/ { next }
    /^[ \t]*$/ { next }
    /:/ { found=1; exit }
    END { exit(found ? 0 : 1) }
  ' "${file}"; then
    return 0
  fi
  return 1
}

checksum_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file}" | awk '{print $1}'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file}" | awk '{print $1}'
    return 0
  fi
  return 1
}

compare_existing_configs() {
  if [[ ! -f "${LOCAL_CONFIG}" ]]; then
    err "$(msg local_missing "${LOCAL_CONFIG}")"
    return 1
  fi
  if [[ ! -f "${TARGET_CONFIG}" ]]; then
    err "$(msg target_missing "${TARGET_CONFIG}")"
    return 1
  fi

  info "$(msg compare_hash)"
  local local_hash=""
  local target_hash=""
  local_hash="$(checksum_file "${LOCAL_CONFIG}")" || return 1
  target_hash="$(checksum_file "${TARGET_CONFIG}")" || return 1

  if [[ "${local_hash}" == "${target_hash}" ]]; then
    ok "$(msg hash_same)"
  else
    warn "$(msg hash_diff_use_existing)"
  fi
  return 0
}

process_config() {
  local changed=0

  if ensure_kv "mixed-port" "7890" "${TMP_CONFIG}"; then
    ok "$(msg changed_mixed)"
    changed=1
  fi

  if ensure_kv "allow-lan" "true" "${TMP_CONFIG}"; then
    ok "$(msg changed_allow)"
    changed=1
  fi

  if ensure_kv "ipv6" "true" "${TMP_CONFIG}"; then
    ok "$(msg changed_ipv6)"
    changed=1
  fi

  if ensure_kv "external-controller" "${VM_IP}:9090" "${TMP_CONFIG}"; then
    ok "$(msg changed_ext "${VM_IP}:9090")"
    changed=1
  fi

  if [[ "${changed}" -eq 0 ]]; then
    ok "$(msg no_change)"
  fi
}

load_config() {
  local do_download="$1"
  local use_transfer_mode="$2"
  local url="$3"

  if [[ "${do_download}" -eq 1 ]]; then
    info "$(msg downloading)"
    curl -fsSL -A "${UA}" "${url}" -o "${TMP_CONFIG}"
    return 0
  fi

  if [[ "${use_transfer_mode}" -eq 1 ]]; then
    info "$(msg loading_transfer)"
    setup_local_transfer_mode
    local transfer_config="${TRANSFER_MOUNT_DIR}/config.yaml"
    if [[ ! -f "${transfer_config}" ]]; then
      err "$(msg transfer_missing "${transfer_config}")"
      return 1
    fi
    # Use a plain stream copy here. Some virtiofs/fuse combinations can fail
    # with cp(1) open flags and return "Operation not supported".
    cat "${transfer_config}" > "${TMP_CONFIG}"
    return 0
  fi

  info "$(msg loading_local)"
  if [[ ! -f "${LOCAL_CONFIG}" ]]; then
    err "$(msg local_missing "${LOCAL_CONFIG}")"
    return 1
  fi
  cp "${LOCAL_CONFIG}" "${TMP_CONFIG}"
  return 0
}

main() {
  set_language "$@"
  local use_transfer_mode=0
  if ! net_iface_exists "${NET_IFACE}"; then
    use_transfer_mode=1
    VM_IP="192.168.8.2"
  else
    VM_IP="$(detect_vm_ip)"
  fi
  banner

  echo -e "${COLOR_DIM}$(msg step 1 4 "$(msg prepare)")${COLOR_RESET}"

  local url=""
  local do_download=1
  if [[ "${use_transfer_mode}" -eq 1 ]]; then
    warn "$(msg iface_missing "${NET_IFACE}")"
    do_download=0
  else
    while true; do
      info "$(msg ask_download)"
      read -r -p "$(msg prompt_yesno)" yn
      case "${yn}" in
        [yY])
          read -r -p "$(msg prompt_url)" url
          if [[ -z "${url}" ]]; then
            warn "$(msg empty_url)"
            continue
          fi
          if ! validate_url "${url}"; then
            warn "$(msg invalid_url)"
            continue
          fi
          break
          ;;
        [nN]|"")
          warn "$(msg skip_download)"
          do_download=0
          break
          ;;
        *)
          warn "y / n"
          ;;
      esac
    done
  fi

  local step2_msg=""
  if [[ "${do_download}" -eq 1 ]]; then
    step2_msg="$(msg downloading)"
  elif [[ "${use_transfer_mode}" -eq 1 ]]; then
    step2_msg="$(msg loading_transfer)"
  else
    step2_msg="$(msg compare_hash)"
  fi
  echo -e "${COLOR_DIM}$(msg step 2 4 "${step2_msg}")${COLOR_RESET}"

  local skip_config_update=0
  if [[ "${do_download}" -eq 0 ]] && [[ "${use_transfer_mode}" -eq 0 ]]; then
    if ! compare_existing_configs; then
      exit 1
    fi
    skip_config_update=1
  else
    if ! load_config "${do_download}" "${use_transfer_mode}" "${url}"; then
      exit 1
    fi
  fi

  if [[ "${skip_config_update}" -eq 0 ]]; then
    if ! sanity_check_yaml "${TMP_CONFIG}"; then
      err "$(msg yaml_invalid)"
      exit 1
    fi

    process_config

    echo -e "${COLOR_DIM}$(msg step 3 4 "$(msg copy_cfg)")${COLOR_RESET}"
    info "$(msg copy_cfg)"
    cp "${TMP_CONFIG}" "${TARGET_CONFIG}"
  else
    echo -e "${COLOR_DIM}$(msg step 3 4 "$(msg reuse_existing_cfg)")${COLOR_RESET}"
    info "$(msg reuse_existing_cfg)"
  fi

  if [[ "${use_transfer_mode}" -eq 1 ]]; then
    local countdown=5
    ok "$(msg imported_shutdown)"
    while [[ "${countdown}" -gt 0 ]]; do
      warn "$(msg shutdown_countdown "${countdown}")"
      sleep 1
      countdown=$((countdown - 1))
    done
    shutdown -h now
    exit 0
  fi

  echo -e "${COLOR_DIM}$(msg step 4 4 "$(msg enable_services)")${COLOR_RESET}"
  enable_services
  info "$(msg start_services)"
  start_services
  wait_for_tor
  report_ports
  ok "$(msg done)"
  post_run_menu
}

main "$@"
