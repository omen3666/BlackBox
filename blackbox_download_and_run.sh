#!/usr/bin/env bash
set -euo pipefail

ENTRY_ACTION="${1:-}"
ORIGINAL_HOME="${ORIGINAL_HOME:-$HOME}"
ORIGINAL_UID="${ORIGINAL_UID:-$(id -u)}"
ORIGINAL_USER="${ORIGINAL_USER:-$(id -un)}"
MISSING_CMDS=()
MISSING_PKGS=()

append_unique_pkg() {
  local pkg="$1"
  local existing=""
  for existing in "${MISSING_PKGS[@]:-}"; do
    if [[ "${existing}" == "${pkg}" ]]; then
      return 0
    fi
  done
  MISSING_PKGS+=("${pkg}")
}

# One-shot dependency check: collect all missing tools and print a single install command.
if [[ "$(id -u)" -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
  MISSING_CMDS+=("sudo")
  append_unique_pkg "root-repo"
  append_unique_pkg "sudo"
fi
if ! command -v wget >/dev/null 2>&1; then
  MISSING_CMDS+=("wget")
  append_unique_pkg "wget"
fi
if ! command -v qemu-img >/dev/null 2>&1; then
  MISSING_CMDS+=("qemu-img")
  append_unique_pkg "qemu-utils"
fi
if [[ "${#MISSING_CMDS[@]}" -gt 0 ]]; then
  echo "[x] Missing required commands: ${MISSING_CMDS[*]}" >&2
  echo "[i] Please install dependencies manually, then rerun:" >&2
  echo "    pkg install -y ${MISSING_PKGS[*]}" >&2
  exit 1
fi

# Elevate once at startup.
if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo -E ORIGINAL_HOME="${ORIGINAL_HOME}" ORIGINAL_UID="${ORIGINAL_UID}" ORIGINAL_USER="${ORIGINAL_USER}" LANGUAGE="${LANGUAGE:-}" bash "$0" "$@"
fi
HOME="${ORIGINAL_HOME}"

OPLUS_LIB_URL="https://github.com/omen3666/BlackBox/raw/refs/heads/main/prebuilt/liboplusaudiopcmdump.so"
BINDER_NDK_LIB_URL="https://github.com/omen3666/BlackBox/raw/refs/heads/main/prebuilt/libbinder_ndk.so"
BINDER_LIB_URL="https://github.com/omen3666/BlackBox/raw/refs/heads/main/prebuilt/libbinder.so"
PREBUILT_DIR="${HOME}/.blackbox/prebuilt"
OPLUS_LIB_PATH="${PREBUILT_DIR}/liboplusaudiopcmdump.so"
BINDER_NDK_LIB_PATH="${PREBUILT_DIR}/libbinder_ndk.so"
BINDER_LIB_PATH="${PREBUILT_DIR}/libbinder.so"
CROSVM_URL="https://github.com/omen3666/BlackBox/raw/refs/heads/main/prebuilt/crosvm"
CROSVM_PATH="${PREBUILT_DIR}/crosvm"

DEBIAN_IMG_URL="https://github.com/omen3666/BlackBox/releases/download/26w08a/debian.img"
KERNEL_IMAGE_URL="https://github.com/omen3666/BlackBox/releases/download/26w08a/Image"
RUNTIME_DIR="${HOME}/.blackbox/runtime"
DEBIAN_IMG_PATH="${RUNTIME_DIR}/debian.img"
KERNEL_IMAGE_PATH="${RUNTIME_DIR}/Image"

CONFIG_DIR="${HOME}/.blackbox"
CONFIG_FILE="${CONFIG_DIR}/config.env"
LOCAL_CFG_MARKER="${CONFIG_DIR}/local_config_imported.flag"
TRANSFER_STAGING_DIR="/tmp/blackbox_localtmp"
TERMUX_STORAGE_ROOT="/data/data/com.termux/files/home/storage"
TERMUX_STORAGE_ALT_ROOT="/data/user/0/com.termux/files/home/storage"
SOCK_PATH="${HOME}/crosvm.sock"
EMERGENCY_SERVICE_PATH="/data/adb/boot-completed.d/blackbox_emergency_cleanup.sh"
EMERGENCY_VM_FLAG="/data/adb/boot-completed.d/.blackbox_vm_running.flag"

LANGUAGE="${LANGUAGE:-}"
RUN_MODE="none"
USE_PRELOAD_LIB=0
USE_A15_PRELOAD_CHAIN=0
EMERGENCY_REBOOT_CLEANUP=0
SESSION_DIFF_PATH=""

info() { printf '[i] %s\n' "$*"; }
ok() { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*"; }
err() { printf '[x] %s\n' "$*" >&2; }

set_language() {
  local choice=""
  if [[ -z "${LANGUAGE}" ]]; then
    echo "Select language / 选择语言: [1] 中文  [2] English"
    read -r -p "Choice (default 1): " choice
    case "${choice}" in
      2|en|EN|English|english) LANGUAGE="en" ;;
      *) LANGUAGE="zh" ;;
    esac
  fi
}

msg() {
  local key="$1"
  case "${LANGUAGE}" in
    en)
      case "${key}" in
        legal_title) echo "Legal Notice" ;;
        legal_warn) echo "This project is for authorized testing, research, and education only." ;;
        legal_warn2) echo "You are solely responsible for legal compliance and all risks." ;;
        legal_confirm_prompt) echo "I acknowledge and will only use BlackBox legally. Continue? [Y/n]" ;;
        legal_confirm_failed) echo "Confirmation failed. Exit." ;;

        mode_title) echo "Select BlackBox run mode:" ;;
        mode_option_full) echo "[1] Full persistence" ;;
        mode_option_half) echo "[2] Semi persistence" ;;
        mode_option_none) echo "[3] No persistence" ;;
        mode_name_full) echo "Full persistence" ;;
        mode_name_half) echo "Semi persistence" ;;
        mode_name_none) echo "No persistence" ;;
        mode_prompt) echo "Enter 1/2/3 (default 1):" ;;
        mode_invalid) echo "Invalid input, please enter 1, 2, or 3." ;;
        mode_selected_full) echo "Mode: Full persistence" ;;
        mode_selected_half) echo "Mode: Semi persistence" ;;
        mode_selected_none) echo "Mode: No persistence" ;;

        menu_title) echo "Main Menu" ;;
        menu_option_1) echo "[1] Start BlackBox" ;;
        menu_option_2) echo "[2] Start local config transfer mode" ;;
        menu_option_3) echo "[3] Delete VM persistence disk" ;;
        menu_option_4) echo "[4] Delete BlackBox" ;;
        menu_option_5) echo "[5] Exit" ;;
        menu_option_6) echo "[6] Switch persistence mode" ;;
        menu_current_mode) echo "Current mode: ${2}" ;;
        menu_prompt) echo "Select an option (1/2/3/4/5/6):" ;;
        menu_invalid) echo "Invalid option." ;;
        menu_ops_title) echo "Actions" ;;
        menu_manage_title) echo "Maintenance" ;;
        menu_footer) echo "Choose an option and press Enter." ;;
        menu_exit) echo "Exit script." ;;

        vm_starting) echo "Starting BlackBox VM..." ;;
        vm_diff_ready) echo "Session diff image ready: ${2}" ;;
        vm_base_copy) echo "Copying base image to /tmp..." ;;
        vm_missing) echo "Required file missing: ${2}" ;;
        transfer_prepare_hint) echo "Put your mihomo config in phone file manager: Download/config.yaml" ;;
        transfer_prepare_hint2) echo "In Termux path this is: ${2}/config.yaml" ;;
        transfer_press_enter) echo "After placing config.yaml, press Enter to continue..." ;;
        transfer_missing_cfg) echo "config.yaml not found at: ${2}" ;;
        transfer_checked_paths) echo "Checked paths: ${2}" ;;
        transfer_move_done) echo "config.yaml copied to ${2}/config.yaml" ;;
        transfer_stage1_done) echo "config.yaml staged at: ${2}" ;;
        deleted_disk) echo "Persistence disk cleanup done." ;;
        deleted_blackbox) echo "BlackBox files removed." ;;
        cfg_loaded) echo "Loaded existing setup. Entering main menu." ;;
        cfg_saved) echo "Setup saved." ;;
        cfg_not_saved_none) echo "No persistence mode selected; setup is not saved." ;;
        emergency_prompt) echo "Enable emergency reboot cleanup? If VM is not normally closed, reboot will auto-delete BlackBox data. [y/N]" ;;
        emergency_enabled) echo "Emergency reboot cleanup enabled." ;;
        emergency_disabled) echo "Emergency reboot cleanup disabled." ;;
      esac
      ;;
    *)
      case "${key}" in
        legal_title) echo "法律与免责声明" ;;
        legal_warn) echo "本项目仅用于合法授权的测试、研究与教育目的。" ;;
        legal_warn2) echo "使用者须自行遵守所在地法律，所有风险与责任由使用者承担。" ;;
        legal_confirm_prompt) echo "我早已知晓并仅合法地使用BlackBox。是否继续？[Y/n]" ;;
        legal_confirm_failed) echo "确认失败，脚本退出。" ;;

        mode_title) echo "请选择 BlackBox 运行模式：" ;;
        mode_option_full) echo "[1] 全持久化" ;;
        mode_option_half) echo "[2] 半持久化" ;;
        mode_option_none) echo "[3] 无持久化" ;;
        mode_name_full) echo "全持久化" ;;
        mode_name_half) echo "半持久化" ;;
        mode_name_none) echo "无持久化" ;;
        mode_prompt) echo "请输入 1/2/3（默认 1）：" ;;
        mode_invalid) echo "输入无效，请输入 1、2 或 3。" ;;
        mode_selected_full) echo "已选择：全持久化" ;;
        mode_selected_half) echo "已选择：半持久化" ;;
        mode_selected_none) echo "已选择：无持久化" ;;

        menu_title) echo "主菜单" ;;
        menu_option_1) echo "[1] 启动BlackBox" ;;
        menu_option_2) echo "[2] 启动本地配置传输模式" ;;
        menu_option_3) echo "[3] 删除虚拟机持久化盘" ;;
        menu_option_4) echo "[4] 删除BlackBox" ;;
        menu_option_5) echo "[5] 退出脚本" ;;
        menu_option_6) echo "[6] 切换持久化模式" ;;
        menu_current_mode) echo "当前模式：${2}" ;;
        menu_prompt) echo "请选择操作（1/2/3/4/5/6）：" ;;
        menu_invalid) echo "无效选项。" ;;
        menu_ops_title) echo "运行操作" ;;
        menu_manage_title) echo "维护操作" ;;
        menu_footer) echo "输入选项后按回车执行。" ;;
        menu_exit) echo "退出脚本。" ;;

        vm_starting) echo "正在启动 BlackBox 虚拟机..." ;;
        vm_diff_ready) echo "会话差分镜像已就绪：${2}" ;;
        vm_base_copy) echo "正在复制基础镜像到 /tmp..." ;;
        vm_missing) echo "缺少必要文件：${2}" ;;
        transfer_prepare_hint) echo "请在手机文件管理器中将 mihomo 配置放到：Download/config.yaml" ;;
        transfer_prepare_hint2) echo "对应 Termux 路径：${2}/config.yaml" ;;
        transfer_press_enter) echo "放好 config.yaml 后按回车继续..." ;;
        transfer_missing_cfg) echo "未找到 config.yaml：${2}" ;;
        transfer_checked_paths) echo "已检查路径：${2}" ;;
        transfer_move_done) echo "config.yaml 已复制到 ${2}/config.yaml" ;;
        transfer_stage1_done) echo "config.yaml 已暂存到：${2}" ;;
        deleted_disk) echo "持久化盘清理完成。" ;;
        deleted_blackbox) echo "BlackBox 文件已删除。" ;;
        cfg_loaded) echo "已读取现有配置，进入主菜单。" ;;
        cfg_saved) echo "配置已保存。" ;;
        cfg_not_saved_none) echo "无持久化模式不会保存首次配置。" ;;
        emergency_prompt) echo "是否开启“胁迫重启清理”？若虚拟机未正常关闭，重启后将自动删除 BlackBox 数据。[y/N]" ;;
        emergency_enabled) echo "已开启胁迫重启清理。" ;;
        emergency_disabled) echo "已关闭胁迫重启清理。" ;;
      esac
      ;;
  esac
}

install_emergency_cleanup_service() {
  mkdir -p "/data/adb/boot-completed.d"
  cat > "${EMERGENCY_SERVICE_PATH}" <<EOF
#!/system/bin/sh
FLAG_FILE="${EMERGENCY_VM_FLAG}"
BLACKBOX_DIR="${ORIGINAL_HOME}/.blackbox"
SOCK_FILE="${ORIGINAL_HOME}/crosvm.sock"

[ -f "\${FLAG_FILE}" ] || exit 0

# Wait until credential-encrypted storage becomes available after unlock.
while [ "\$(getprop sys.user.0.ce_available)" != "true" ]; do
  sleep 2
done

rm -rf "\${BLACKBOX_DIR}" /tmp/blackbox_prebuilt /tmp/blackbox_runtime
rm -f /tmp/session_diff.qcow2 /tmp/debian.img "\${SOCK_FILE}" "\${FLAG_FILE}"
EOF
  chmod 755 "${EMERGENCY_SERVICE_PATH}"
}

remove_emergency_cleanup_service() {
  rm -f "${EMERGENCY_SERVICE_PATH}" "${EMERGENCY_VM_FLAG}"
}

ask_emergency_reboot_cleanup() {
  local input=""
  if [[ "${RUN_MODE}" == "none" ]]; then
    EMERGENCY_REBOOT_CLEANUP=0
    remove_emergency_cleanup_service
    return 0
  fi

  read -r -p "$(msg emergency_prompt) " input
  case "${input}" in
    [yY])
      EMERGENCY_REBOOT_CLEANUP=1
      install_emergency_cleanup_service
      ok "$(msg emergency_enabled)"
      ;;
    *)
      EMERGENCY_REBOOT_CLEANUP=0
      remove_emergency_cleanup_service
      info "$(msg emergency_disabled)"
      ;;
  esac
}

mark_vm_running_for_emergency() {
  if [[ "${EMERGENCY_REBOOT_CLEANUP}" -eq 1 ]]; then
    : > "${EMERGENCY_VM_FLAG}"
  fi
}

clear_vm_running_for_emergency() {
  rm -f "${EMERGENCY_VM_FLAG}"
}

clear_stale_emergency_flag_on_start() {
  if [[ ! -f "${EMERGENCY_VM_FLAG}" ]]; then
    return 0
  fi

  # If no VM process exists, treat flag as stale and clear it to avoid false cleanup on reboot.
  if ! pgrep -x crosvm >/dev/null 2>&1; then
    rm -f "${EMERGENCY_VM_FLAG}"
  fi
}

print_legal_notice() {
  printf '\n%s\n' "============================================================"
  printf '%s\n' "$(msg legal_title)"
  printf '%s\n' "$(msg legal_warn)"
  printf '%s\n' "$(msg legal_warn2)"
  printf '%s\n\n' "============================================================"

  cat <<'TEXT'
《中华人民共和国计算机信息网络国际联网管理暂行规定》（国务院令第195号）
第六条：计算机信息网络直接进行国际联网，必须使用邮电部国家公用电信网提供的国际出入口信道。任何单位和个人不得自行建立或者使用其他信道进行国际联网。
第十四条：违反第六条规定的，由公安机关责令停止联网，给予警告，可以并处15000元以下的罚款。

中华人民共和国刑法第二百八十六条【破坏计算机信息系统罪；网络服务渎职罪】
违反国家规定，删除、修改、增加或者干扰计算机信息系统的功能，造成计算机信息系统运行异常，后果严重的，处五年以下有期徒刑或者拘役；后果特别严重的，处五年以上有期徒刑。
违反国家规定，删除、修改、增加计算机信息系统中存储、处理、传输的数据和应用程序，造成严重后果的，依照前款的规定处罚。

美国法律条文：计算机欺诈与滥用行为法 (CFAA - 18 U.S.C. § 1030):
未经授权访问: 禁止故意进入受保护计算机系统，获取政府、金融或影响跨州贸易的信息。
损害与破坏: 故意传输代码导致受保护计算机损害，最高可判十年徒刑；若造成身体伤害或威胁公共健康，刑期可加重。
犯罪意图: 涵盖阴谋和企图实施非法入侵行为。
电子通信隐私法 (ECPA):
禁止非法拦截电子邮件、语音电话等电子通信数据。
身份盗用法 (Identity Theft Act):
针对通过黑客手段窃取他人个人身份信息（PII）以进行欺诈的行为。
TEXT
  printf '\n'
}

confirm_legal_use() {
  local input=""
  read -r -p "$(msg legal_confirm_prompt) " input
  case "${input}" in
    [yY]|"") ok "Confirmed." ;;
    *) err "$(msg legal_confirm_failed)"; exit 1 ;;
  esac
}

ensure_wget() {
  command -v wget >/dev/null 2>&1 || { err "Missing required command after precheck: wget"; exit 1; }
}

check_root_ready() {
  if [[ "$(id -u)" -ne 0 ]]; then
    err "Root check failed: script is not running as root."
    exit 1
  fi
}

check_gunyah_device() {
  test -e /dev/gunyah || { err "/dev/gunyah not found."; exit 1; }
}

ensure_qemu_img() {
  command -v qemu-img >/dev/null 2>&1 || { err "Missing required command after precheck: qemu-img"; exit 1; }
}

prepare_preload_libraries() {
  local phase="${1:-runtime}"
  local brand=""
  local android_release=""
  local need_download=0
  USE_PRELOAD_LIB=0
  USE_A15_PRELOAD_CHAIN=0

  if ! command -v getprop >/dev/null 2>&1; then
    return 0
  fi

  android_release="$(getprop ro.build.version.release 2>/dev/null || true)"
  if [[ "${android_release}" =~ ^15([[:space:]].*)?$ || "${android_release}" =~ ^15\. ]]; then
    if [[ ! -s "${BINDER_NDK_LIB_PATH}" || ! -s "${BINDER_LIB_PATH}" || ! -s "${OPLUS_LIB_PATH}" ]]; then
      need_download=1
    fi
    if [[ "${need_download}" -eq 1 ]] && [[ "${phase}" == "setup" ]]; then
      mkdir -p "${PREBUILT_DIR}"
      info "Android ${android_release} detected, downloading preload chain libraries..."
      wget --show-progress --progress=bar:force:noscroll -O "${BINDER_NDK_LIB_PATH}" "${BINDER_NDK_LIB_URL}"
      wget --show-progress --progress=bar:force:noscroll -O "${BINDER_LIB_PATH}" "${BINDER_LIB_URL}"
      wget --show-progress --progress=bar:force:noscroll -O "${OPLUS_LIB_PATH}" "${OPLUS_LIB_URL}"
    fi
    if [[ -s "${BINDER_NDK_LIB_PATH}" && -s "${BINDER_LIB_PATH}" && -s "${OPLUS_LIB_PATH}" ]]; then
      USE_A15_PRELOAD_CHAIN=1
      if [[ "${phase}" == "setup" ]]; then
        ok "A15 preload libraries ready: ${BINDER_NDK_LIB_PATH}, ${BINDER_LIB_PATH}, ${OPLUS_LIB_PATH}"
      fi
      return 0
    fi
    warn "Android ${android_release} detected but A15 preload chain is incomplete."
  fi

  brand="$(getprop ro.product.brand 2>/dev/null || true)"
  if [[ "${brand}" =~ ^(OnePlus)$ ]]; then
    mkdir -p "${PREBUILT_DIR}"
    if [[ ! -s "${OPLUS_LIB_PATH}" ]] && [[ "${phase}" == "setup" ]]; then
      info "Downloading OnePlus preload library..."
      wget --show-progress --progress=bar:force:noscroll -O "${OPLUS_LIB_PATH}" "${OPLUS_LIB_URL}"
    fi
    if [[ -s "${OPLUS_LIB_PATH}" ]]; then
      USE_PRELOAD_LIB=1
      if [[ "${phase}" == "setup" ]]; then
        ok "Preload library ready: ${OPLUS_LIB_PATH}"
      fi
    else
      if [[ "${phase}" == "setup" ]]; then
        err "Failed to download preload library."
        exit 1
      fi
    fi
  fi
}

download_crosvm_binary() {
  local force="${1:-0}"
  mkdir -p "${PREBUILT_DIR}"
  if [[ "${force}" -ne 1 && -s "${CROSVM_PATH}" ]]; then
    info "crosvm binary already exists, skipping download."
    return 0
  fi
  info "Downloading crosvm binary..."
  wget --show-progress --progress=bar:force:noscroll -O "${CROSVM_PATH}" "${CROSVM_URL}"
  [[ -s "${CROSVM_PATH}" ]] || { err "Failed to download crosvm."; exit 1; }
  chmod 755 "${CROSVM_PATH}"
}

download_runtime_images() {
  local force="${1:-0}"
  mkdir -p "${RUNTIME_DIR}"
  if [[ "${force}" -ne 1 && -s "${DEBIAN_IMG_PATH}" ]]; then
    info "Debian base image already exists, skipping download."
  else
    info "Downloading debian base image..."
    wget --show-progress --progress=bar:force:noscroll -O "${DEBIAN_IMG_PATH}" "${DEBIAN_IMG_URL}"
    [[ -s "${DEBIAN_IMG_PATH}" ]] || { err "Failed to download debian image."; exit 1; }
  fi

  if [[ "${force}" -ne 1 && -s "${KERNEL_IMAGE_PATH}" ]]; then
    info "Kernel image already exists, skipping download."
  else
    info "Downloading kernel image..."
    wget --show-progress --progress=bar:force:noscroll -O "${KERNEL_IMAGE_PATH}" "${KERNEL_IMAGE_URL}"
    [[ -s "${KERNEL_IMAGE_PATH}" ]] || { err "Failed to download kernel image."; exit 1; }
  fi
}

prepare_ephemeral_runtime() {
  PREBUILT_DIR="/tmp/blackbox_prebuilt"
  RUNTIME_DIR="/tmp/blackbox_runtime"
  DEBIAN_IMG_PATH="${RUNTIME_DIR}/debian.img"
  KERNEL_IMAGE_PATH="${RUNTIME_DIR}/Image"
  CROSVM_PATH="${PREBUILT_DIR}/crosvm"
  OPLUS_LIB_PATH="${PREBUILT_DIR}/liboplusaudiopcmdump.so"
  BINDER_NDK_LIB_PATH="${PREBUILT_DIR}/libbinder_ndk.so"
  BINDER_LIB_PATH="${PREBUILT_DIR}/libbinder.so"

  rm -f "${DEBIAN_IMG_PATH}" "${KERNEL_IMAGE_PATH}" "${CROSVM_PATH}" \
    "${OPLUS_LIB_PATH}" "${BINDER_NDK_LIB_PATH}" "${BINDER_LIB_PATH}"

  download_runtime_images 1
  download_crosvm_binary 1
  prepare_preload_libraries setup
}

cleanup_ephemeral_runtime() {
  rm -rf /tmp/blackbox_prebuilt /tmp/blackbox_runtime
  rm -f /tmp/session_diff.qcow2 /tmp/debian.img
  rm -f "${LOCAL_CFG_MARKER}"
}

configure_network() {
  info "Configuring network (crosvm_tap)..."
  sh <<'NETEOF'
cd /data/local/tmp || exit 1
ifname=crosvm_tap

table_id=$(ip rule list | grep "lookup" | grep -m 1 "wlan0" | awk '{print $NF}')
[ -z "$table_id" ] && table_id="main"

if [ ! -d "/sys/class/net/$ifname" ]; then
    ip tuntap add mode tap vnet_hdr "$ifname"
    ip addr add 192.168.8.1/24 dev "$ifname"
    ip link set "$ifname" up

    ip route add 192.168.8.0/24 via 192.168.8.1 dev "$ifname" table "$table_id" 2>/dev/null || true

    iptables -D INPUT -j ACCEPT -i "$ifname" 2>/dev/null || true
    iptables -I INPUT -j ACCEPT -i "$ifname"

    iptables -D OUTPUT -j ACCEPT -o "$ifname" 2>/dev/null || true
    iptables -I OUTPUT -j ACCEPT -o "$ifname"

    iptables -t nat -D POSTROUTING -j MASQUERADE -o wlan0 -s 192.168.8.0/24 2>/dev/null || true
    iptables -t nat -I POSTROUTING -j MASQUERADE -o wlan0 -s 192.168.8.0/24

    sysctl -w net.ipv4.ip_forward=1

    ip rule add from all fwmark 0/0x1ffff iif wlan0 lookup "$table_id" 2>/dev/null || true
    ip rule add iif "$ifname" lookup "$table_id" 2>/dev/null || true

    iptables -D FORWARD -i "$ifname" -o wlan0 -j ACCEPT 2>/dev/null || true
    iptables -I FORWARD -i "$ifname" -o wlan0 -j ACCEPT

    iptables -D FORWARD -m state --state ESTABLISHED,RELATED -i wlan0 -o "$ifname" -j ACCEPT 2>/dev/null || true
    iptables -I FORWARD -m state --state ESTABLISHED,RELATED -i wlan0 -o "$ifname" -j ACCEPT
fi
NETEOF
}

prepare_local_transfer_config_for_vm() {
  local src_cfg=""
  local candidate=""
  local searched=""
  local candidate_paths=()

  mapfile -t candidate_paths < <(get_termux_config_candidates)
  info "$(msg transfer_prepare_hint)"
  if [[ "${#candidate_paths[@]}" -gt 0 ]]; then
    info "$(msg transfer_prepare_hint2 "$(dirname "${candidate_paths[0]}")")"
  else
    info "$(msg transfer_prepare_hint2 "${ORIGINAL_HOME}/storage/downloads")"
  fi
  read -r -p "$(msg transfer_press_enter) " _

  for candidate in "${candidate_paths[@]}"; do
    if [[ -f "${candidate}" ]]; then
      src_cfg="${candidate}"
      break
    fi
  done

  if [[ -z "${src_cfg}" ]]; then
    searched="$(IFS=', '; printf '%s' "${candidate_paths[*]:-none}")"
    err "$(msg transfer_missing_cfg "${ORIGINAL_HOME}/storage/downloads/config.yaml")"
    err "$(msg transfer_checked_paths "${searched}")"
    return 1
  fi

  mkdir -p "${TRANSFER_STAGING_DIR}"
  chmod 755 "${TRANSFER_STAGING_DIR}"
  cp "${src_cfg}" "${TRANSFER_STAGING_DIR}/config.yaml"
  chmod 644 "${TRANSFER_STAGING_DIR}/config.yaml"
  [[ -s "${TRANSFER_STAGING_DIR}/config.yaml" ]] || { err "staging config failed."; return 1; }
  ok "$(msg transfer_move_done "${TRANSFER_STAGING_DIR}")"
  ok "$(msg transfer_stage1_done "${TRANSFER_STAGING_DIR}/config.yaml")"
  return 0
}

get_termux_config_candidates() {
  local roots=(
    "${ORIGINAL_HOME}/storage"
    "${HOME}/storage"
    "${TERMUX_STORAGE_ROOT}"
    "${TERMUX_STORAGE_ALT_ROOT}"
  )
  local rels=("downloads" "Download" "shared/Download" "shared/download")
  local root=""
  local rel=""
  local file=""
  local -A seen=()

  for root in "${roots[@]}"; do
    [[ -n "${root}" ]] || continue
    for rel in "${rels[@]}"; do
      file="${root}/${rel}/config.yaml"
      if [[ -z "${seen[${file}]:-}" ]]; then
        seen["${file}"]=1
        printf '%s\n' "${file}"
      fi
    done
  done

  # Explicit common fallback paths for Termux storage.
  for file in \
    "/data/data/com.termux/files/home/storage/downloads/config.yaml" \
    "/data/user/0/com.termux/files/home/storage/downloads/config.yaml"; do
    if [[ -z "${seen[${file}]:-}" ]]; then
      seen["${file}"]=1
      printf '%s\n' "${file}"
    fi
  done
}

choose_run_mode() {
  local mode_choice=""
  info "$(msg mode_title)"
  info "$(msg mode_option_full)"
  info "$(msg mode_option_half)"
  info "$(msg mode_option_none)"

  while true; do
    read -r -p "$(msg mode_prompt) " mode_choice
    case "${mode_choice}" in
      ""|1) RUN_MODE="full"; ok "$(msg mode_selected_full)"; break ;;
      2) RUN_MODE="half"; ok "$(msg mode_selected_half)"; break ;;
      3) RUN_MODE="none"; ok "$(msg mode_selected_none)"; break ;;
      *) warn "$(msg mode_invalid)" ;;
    esac
  done
}

save_config_if_persistent() {
  if [[ "${RUN_MODE}" == "none" ]]; then
    EMERGENCY_REBOOT_CLEANUP=0
    remove_emergency_cleanup_service
    rm -f "${CONFIG_FILE}"
    warn "$(msg cfg_not_saved_none)"
    return 0
  fi

  mkdir -p "${CONFIG_DIR}"
  cat > "${CONFIG_FILE}" <<CFG
CONFIG_LANGUAGE=${LANGUAGE}
RUN_MODE=${RUN_MODE}
EMERGENCY_REBOOT_CLEANUP=${EMERGENCY_REBOOT_CLEANUP}
SETUP_DONE=1
CFG
  ok "$(msg cfg_saved)"
}

load_saved_config() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    return 1
  fi

  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
  if [[ "${SETUP_DONE:-0}" != "1" ]]; then
    return 1
  fi
  # No-persistence mode should re-run first-launch flow every time.
  if [[ "${RUN_MODE:-}" == "none" ]]; then
    rm -f "${CONFIG_FILE}"
    return 1
  fi
  if [[ "${RUN_MODE:-}" != "full" && "${RUN_MODE:-}" != "half" && "${RUN_MODE:-}" != "none" ]]; then
    return 1
  fi

  LANGUAGE="${CONFIG_LANGUAGE:-zh}"
  RUN_MODE="${RUN_MODE}"
  EMERGENCY_REBOOT_CLEANUP="${EMERGENCY_REBOOT_CLEANUP:-0}"
  if [[ "${EMERGENCY_REBOOT_CLEANUP}" == "1" ]]; then
    install_emergency_cleanup_service
  else
    remove_emergency_cleanup_service
  fi
  ok "$(msg cfg_loaded)"
  return 0
}

run_mode_name() {
  case "${RUN_MODE}" in
    full) msg mode_name_full ;;
    half) msg mode_name_half ;;
    none|*) msg mode_name_none ;;
  esac
}

switch_run_mode_from_menu() {
  local previous_mode="${RUN_MODE}"
  choose_run_mode
  save_config_if_persistent
  if [[ "${previous_mode}" != "none" && "${RUN_MODE}" == "none" ]]; then
    # Switching to no persistence: drop any persistent diff disk.
    if [[ -f "${RUNTIME_DIR}/session_diff.qcow2" ]]; then
      rm -f /tmp/session_diff.qcow2
      mv "${RUNTIME_DIR}/session_diff.qcow2" /tmp/session_diff.qcow2
      rm -f "${RUNTIME_DIR}/session_diff.qcow2"
    fi
  fi
}

ensure_base_prereqs() {
  ensure_wget
  check_root_ready
  check_gunyah_device
  ensure_qemu_img
}

ensure_runtime_prereqs() {
  ensure_base_prereqs
  download_runtime_images
  download_crosvm_binary
  prepare_preload_libraries setup
  configure_network
}

require_file() {
  local file="$1"
  if [[ ! -f "${file}" ]]; then
    err "$(msg vm_missing "${file}")"
    return 1
  fi
  return 0
}

create_session_diff() {
  local mode="$1"
  local diff_path=""

  case "${mode}" in
    full)
      diff_path="${RUNTIME_DIR}/session_diff.qcow2"
      rm -f "${diff_path}"
      qemu-img create -f qcow2 -b "${DEBIAN_IMG_PATH}" -F raw "${diff_path}" >/dev/null
      ;;
    half)
      diff_path="/tmp/session_diff.qcow2"
      if [[ -f "${LOCAL_CFG_MARKER}" ]] && [[ -f "${diff_path}" ]]; then
        info "Reuse existing half-persistent diff disk because local config was imported."
      else
        rm -f "${diff_path}"
        qemu-img create -f qcow2 -b "${DEBIAN_IMG_PATH}" -F raw "${diff_path}" >/dev/null
      fi
      ;;
    none)
      diff_path="/tmp/session_diff.qcow2"
      info "$(msg vm_base_copy)"
      cp "${DEBIAN_IMG_PATH}" /tmp/debian.img
      rm -f "${diff_path}"
      qemu-img create -f qcow2 -b /tmp/debian.img -F raw "${diff_path}" >/dev/null
      ;;
    *)
      err "Unknown mode: ${mode}"
      exit 1
      ;;
  esac

  SESSION_DIFF_PATH="${diff_path}"
  ok "$(msg vm_diff_ready "${SESSION_DIFF_PATH}")"
}

run_crosvm() {
  local transfer_mode="$1"
  local preload_value=""
  rm -f "${SOCK_PATH}"

  # Android reboot clears tap/iptables state; re-apply before networked VM boot.
  if [[ "${transfer_mode}" != "1" ]]; then
    configure_network
  fi

  prepare_preload_libraries runtime

  if [[ "${USE_A15_PRELOAD_CHAIN}" -eq 1 ]]; then
    preload_value="${BINDER_NDK_LIB_PATH}:${BINDER_LIB_PATH}:${OPLUS_LIB_PATH}"
  elif [[ "${USE_PRELOAD_LIB}" -eq 1 ]]; then
    preload_value="${OPLUS_LIB_PATH}"
  fi

  if [[ "${transfer_mode}" == "1" ]]; then
    if [[ -n "${preload_value}" ]]; then
      LD_PRELOAD="${preload_value}" "${CROSVM_PATH}" run \
      --no-balloon \
      --protected-vm-without-firmware \
      --disable-sandbox \
      --shared-dir "${TRANSFER_STAGING_DIR}:blackbox_localtmp:type=fs" \
      -s "${SOCK_PATH}" \
      --block "${SESSION_DIFF_PATH},root" \
      "${KERNEL_IMAGE_PATH}" \
      --vsock 3 \
      --mem 500 \
      --cpus 1
    else
      "${CROSVM_PATH}" run \
      --no-balloon \
      --protected-vm-without-firmware \
      --disable-sandbox \
      --shared-dir "${TRANSFER_STAGING_DIR}:blackbox_localtmp:type=fs" \
      -s "${SOCK_PATH}" \
      --block "${SESSION_DIFF_PATH},root" \
      "${KERNEL_IMAGE_PATH}" \
      --vsock 3 \
      --mem 500 \
      --cpus 1
    fi
  else
    if [[ -n "${preload_value}" ]]; then
      LD_PRELOAD="${preload_value}" "${CROSVM_PATH}" run \
      --no-balloon \
      --protected-vm-without-firmware \
      --disable-sandbox \
      --net tap-name=crosvm_tap \
      -s "${SOCK_PATH}" \
      --block "${SESSION_DIFF_PATH},root" \
      "${KERNEL_IMAGE_PATH}" \
      --vsock 3 \
      --mem 500 \
      --cpus 1
    else
      "${CROSVM_PATH}" run \
      --no-balloon \
      --protected-vm-without-firmware \
      --disable-sandbox \
      --net tap-name=crosvm_tap \
      -s "${SOCK_PATH}" \
      --block "${SESSION_DIFF_PATH},root" \
      "${KERNEL_IMAGE_PATH}" \
      --vsock 3 \
      --mem 500 \
      --cpus 1
    fi
  fi
}

start_blackbox() {
  local rc=0
  if [[ "${RUN_MODE}" == "none" ]]; then
    prepare_ephemeral_runtime
  fi
  require_file "${DEBIAN_IMG_PATH}" || return 1
  require_file "${KERNEL_IMAGE_PATH}" || return 1
  require_file "${CROSVM_PATH}" || return 1

  create_session_diff "${RUN_MODE}"
  info "$(msg vm_starting)"
  mark_vm_running_for_emergency
  if run_crosvm 0; then
    clear_vm_running_for_emergency
  else
    rc=$?
  fi
  if [[ "${RUN_MODE}" == "none" ]]; then
    cleanup_ephemeral_runtime
  fi
  return "${rc}"
}

start_local_transfer_mode() {
  local rc=0
  if [[ "${RUN_MODE}" == "none" ]]; then
    prepare_ephemeral_runtime
  fi
  require_file "${DEBIAN_IMG_PATH}" || return 1
  require_file "${KERNEL_IMAGE_PATH}" || return 1
  require_file "${CROSVM_PATH}" || return 1

  prepare_local_transfer_config_for_vm || return 1
  mkdir -p "${CONFIG_DIR}"
  touch "${LOCAL_CFG_MARKER}"
  create_session_diff "${RUN_MODE}"
  info "$(msg vm_starting)"
  mark_vm_running_for_emergency
  if run_crosvm 1; then
    clear_vm_running_for_emergency
  else
    rc=$?
  fi
  if [[ "${RUN_MODE}" == "none" ]]; then
    cleanup_ephemeral_runtime
  fi
  return "${rc}"
}

delete_persistence_disk() {
  rm -f "${RUNTIME_DIR}/session_diff.qcow2" /tmp/session_diff.qcow2
  rm -f "${LOCAL_CFG_MARKER}"
  ok "$(msg deleted_disk)"
}

cleanup_network() {
  sh <<'CLEANEOF'
if ip link show crosvm_tap >/dev/null 2>&1; then
  ip link set crosvm_tap down 2>/dev/null || true
  ip tuntap del mode tap crosvm_tap 2>/dev/null || true
fi
iptables -D INPUT -j ACCEPT -i crosvm_tap 2>/dev/null || true
iptables -D OUTPUT -j ACCEPT -o crosvm_tap 2>/dev/null || true
iptables -t nat -D POSTROUTING -j MASQUERADE -o wlan0 -s 192.168.8.0/24 2>/dev/null || true
iptables -D FORWARD -i crosvm_tap -o wlan0 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -m state --state ESTABLISHED,RELATED -i wlan0 -o crosvm_tap -j ACCEPT 2>/dev/null || true
CLEANEOF
}

delete_blackbox() {
  cleanup_network || true
  rm -rf "${CONFIG_DIR}"
  rm -f /tmp/session_diff.qcow2 /tmp/debian.img "${SOCK_PATH}"
  ok "$(msg deleted_blackbox)"
  exit 0
}

main_menu() {
  local choice=""
  while true; do
    echo
    printf '%s\n' "============================================================"
    printf '%s\n' "  $(msg menu_title)"
    printf '%s\n' "------------------------------------------------------------"
    printf '%s\n' "  $(msg menu_current_mode "$(run_mode_name)")"
    printf '%s\n' "------------------------------------------------------------"
    printf '%s\n' "  $(msg menu_ops_title):"
    printf '%s\n' "    $(msg menu_option_1)"
    printf '%s\n' "    $(msg menu_option_2)"
    printf '%s\n' "  $(msg menu_manage_title):"
    printf '%s\n' "    $(msg menu_option_3)"
    printf '%s\n' "    $(msg menu_option_4)"
    printf '%s\n' "    $(msg menu_option_5)"
    printf '%s\n' "    $(msg menu_option_6)"
    printf '%s\n' "------------------------------------------------------------"
    printf '%s\n' "  $(msg menu_footer)"
    printf '%s\n' "============================================================"
    read -r -p "$(msg menu_prompt) " choice
    case "${choice}" in
      1) start_blackbox ;;
      2) start_local_transfer_mode ;;
      3) delete_persistence_disk ;;
      4) delete_blackbox ;;
      5) ok "$(msg menu_exit)"; exit 0 ;;
      6) switch_run_mode_from_menu ;;
      *) warn "$(msg menu_invalid)" ;;
    esac
  done
}

first_launch_setup() {
  set_language
  print_legal_notice
  confirm_legal_use
  choose_run_mode
  ask_emergency_reboot_cleanup
  if [[ "${RUN_MODE}" == "none" ]]; then
    ensure_base_prereqs
  else
    ensure_runtime_prereqs
  fi
  save_config_if_persistent
}

main() {
  clear_stale_emergency_flag_on_start
  if ! load_saved_config; then
    first_launch_setup
  fi

  main_menu
}

main "$@"
