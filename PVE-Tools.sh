#!/bin/bash

# PVE 9.0 配置工具脚本
# 支持换源、删除订阅弹窗、硬盘管理等功能
# 适用于 Proxmox VE 9.0 (基于 Debian 13)
# Auther:Maple 二次修改使用请不要删除此段注释

# 版本信息
CURRENT_VERSION="3.3.1"
VERSION_FILE_URL="https://raw.githubusercontent.com/Mapleawaa/PVE-Tools-9/main/VERSION"

# 颜色定义 - 保持一致性
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
ORANGE='\033[0;33m'  # Alternative to YELLOW for warnings
NC='\033[0m' # No Color

# UI 界面一致性常量
UI_BORDER="${CYAN}┌────────────────────────────────────────────────┐${NC}"
UI_DIVIDER="${CYAN}├────────────────────────────────────────────────┤${NC}"
UI_FOOTER="${CYAN}└────────────────────────────────────────────────┘${NC}"
UI_HEADER="${CYAN}------------------------------------------------${NC}"
UI_FOOTER_SHORT="${CYAN}------------------------------------------------${NC}"

# 镜像源配置
MIRROR_USTC="https://mirrors.ustc.edu.cn/proxmox/debian/pve"
MIRROR_TUNA="https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/pve" 
MIRROR_DEBIAN="https://deb.debian.org/debian"
SELECTED_MIRROR=""

# 日志函数
log_info() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${CYAN}[INFO]${NC} $1" | tee -a /var/log/pve-tools.log
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${ORANGE}[WARN]${NC} $1" | tee -a /var/log/pve-tools.log
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${RED}[ERROR]${NC} $1" | tee -a /var/log/pve-tools.log >&2
}

log_step() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${MAGENTA}[STEP]${NC} $1" | tee -a /var/log/pve-tools.log
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${GREEN}[SUCCESS]${NC} $1" | tee -a /var/log/pve-tools.log
}

log_tips(){
    echo -e "${CYAN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ${MAGENTA}[TIPS]${NC} $1" | tee -a /var/log/pve-tools.log
}

# Enhanced error handling function with consistent messaging
display_error() {
    local error_msg="$1"
    local suggestion="${2:-请检查输入或联系作者寻求帮助。}"
    
    log_error "$error_msg"
    echo -e "${YELLOW}提示: $suggestion${NC}"
    pause_function
}

# Enhanced success feedback
display_success() {
    local success_msg="$1"
    local next_step="${2:-}"
    
    log_success "$success_msg"
    if [[ -n "$next_step" ]]; then
        echo -e "${GREEN}下一步: $next_step${NC}"
    fi
}

# Confirmation prompt with consistent UI
confirm_action() {
    local action_desc="$1"
    local default_choice="${2:-N}"
    
    echo -e "${YELLOW}确认操作: $action_desc${NC}"
    read -p "请输入 'yes' 确认继续，其他任意键取消 [$default_choice]: " -r confirm
    if [[ "$confirm" == "yes" || "$confirm" == "YES" ]]; then
        return 0
    else
        log_info "操作已取消"
        return 1
    fi
}

# 进度指示函数
show_progress() {
    local message="$1"
    local spinner="|/-\\"
    local i=0
    # Print initial message
    echo -ne "${CYAN}[    ]${NC} $message\033[0K\r"
    
    # Update the spinner position in the box
    while true; do
        i=$(( (i + 1) % 4 ))
        echo -ne "\b\b\b\b\b${CYAN}[${spinner:$i:1}]${NC}\033[0K\r"
        sleep 0.1
    done &
    # Store the background job ID to be killed later
    SPINNER_PID=$!
}

update_progress() {
    local message="$1"
    # Kill the spinner if running
    if [[ -n "$SPINNER_PID" ]]; then
        kill $SPINNER_PID 2>/dev/null
    fi
    echo -ne "${GREEN}[ OK ]${NC} $message\033[0K\r"
    echo
}

# Enhanced visual feedback function
show_status() {
    local status="$1"
    local message="$2"
    local color="$3"
    
    case $status in
        "info")
            echo -e "${CYAN}[INFO]${NC} $message"
            ;;
        "success")
            echo -e "${GREEN}[ OK ]${NC} $message"
            ;;
        "warning")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "error")
            echo -e "${RED}[FAIL]${NC} $message"
            ;;
        "step")
            echo -e "${MAGENTA}[STEP]${NC} $message"
            ;;
        *)
            echo -e "${WHITE}[$status]${NC} $message"
            ;;
    esac
}

# Progress bar function
show_progress_bar() {
    local current="$1"
    local total="$2"
    local message="$3"
    local width=40
    local percentage=$(( current * 100 / total ))
    local filled=$(( width * current / total ))
    
    printf "${CYAN}[${NC}"
    for ((i=0; i<filled; i++)); do
        printf "█"
    done
    for ((i=filled; i<width; i++)); do
        printf " "
    done
    printf "${CYAN}]${NC} ${percentage}%% $message\r"
}

# 显示横幅
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
██████╗ ██╗   ██╗███████╗    ████████╗ ██████╗  ██████╗ ██╗     ███████╗     █████╗ 
██╔══██╗██║   ██║██╔════╝    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██╔════╝    ██╔══██╗
██████╔╝██║   ██║█████╗         ██║   ██║   ██║██║   ██║██║     ███████╗    ╚██████║
██╔═══╝ ╚██╗ ██╔╝██╔══╝         ██║   ██║   ██║██║   ██║██║     ╚════██║     ╚═══██║
██║      ╚████╔╝ ███████╗       ██║   ╚██████╔╝╚██████╔╝███████╗███████║     █████╔╝
╚═╝       ╚═══╝  ╚══════╝       ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚══════╝     ╚════╝ 
EOF
    echo -e "${NC}"
    echo -e "${YELLOW}                    ═══════════════════════════════════════${NC}"
    echo -e "${YELLOW}                           PVE 9.0 一键配置神器${NC}"
    echo -e "${GREEN}                            让 PVE 配置变得简单快乐${NC}"
    echo -e "${CYAN}                             作者: Maple & Claude 4${NC}"
    echo -e "${NC}                             当前版本: ${YELLOW}$CURRENT_VERSION${NC}"
    echo -e "${NC}                             最新版本: ${GREEN}$remote_version${NC}"
    echo -e "${YELLOW}                    ═══════════════════════════════════════${NC}"
    echo
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "哎呀！需要超级管理员权限才能运行哦"
        echo -e "${YELLOW}请使用以下命令重新运行：${NC}"
        echo -e "${CYAN}sudo $0${NC}"
        exit 1
    fi
}

# 检查调试模式
check_debug_mode() {
    for arg in "$@"; do
        if [[ "$arg" == "--debug" ]]; then
            log_warn "警告：您正在使用调试模式！"
            log_warn "此模式将跳过 PVE 系统版本检测"
            log_warn "仅在开发和测试环境中使用"
            log_warn "在非 PVE (Debian 系) 系统上使用可能导致系统损坏"
            echo -e "${YELLOW}您确定要继续吗？输入 'yes' 确认，其他任意键退出: ${NC}"
            read -r confirm
            if [[ "$confirm" != "yes" ]]; then
                log_info "已取消操作，退出脚本"
                exit 0
            fi
            DEBUG_MODE=true
            log_success "已启用调试模式"
            return
        fi
    done
    DEBUG_MODE=false
}

# 检查是否安装依赖软件包
check_packages() {
    # 程序依赖的软件包: `sudo` `curl`
    local packages=("sudo" "curl")
    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            log_error "哎呀！需要安装 $pkg 软件包才能运行哦"
            log_tips "请使用以下命令安装：apt install -y $pkg"
            exit 1
        fi
    done
 }
    



# 检查 PVE 版本
check_pve_version() {
    # 如果在调试模式下，跳过 PVE 版本检测
    if [[ "$DEBUG_MODE" == "true" ]]; then
        log_warn "调试模式：跳过 PVE 版本检测"
        log_tips "请注意：您正在非 PVE 系统上运行此脚本，某些功能可能无法正常工作"
        return
    fi
    
    if ! command -v pveversion &> /dev/null; then
        log_error "咦？这里好像不是 PVE 环境呢"
        log_warn "请在 Proxmox VE 系统上运行此脚本"
        exit 1
    fi
    
    local pve_version=$(pveversion | head -n1 | cut -d'/' -f2 | cut -d'-' -f1)
    log_info "太好了！检测到 PVE 版本: ${GREEN}$pve_version${NC}"
}

# 检测当前内核版本
check_kernel_version() {
    log_info "检测当前内核信息..."
    local current_kernel=$(uname -r)
    local kernel_arch=$(uname -m)
    local kernel_variant=""
    
    # 检测内核变体（普通/企业版/测试版）
    if [[ $current_kernel == *"pve"* ]]; then
        kernel_variant="PVE标准内核"
    elif [[ $current_kernel == *"edge"* ]]; then
        kernel_variant="PVE边缘内核"
    elif [[ $current_kernel == *"test"* ]]; then
        kernel_variant="测试内核"
    else
        kernel_variant="未知类型"
    fi
    
    echo -e "${CYAN}当前内核信息：${NC}"
    echo -e "  版本: ${GREEN}$current_kernel${NC}"
    echo -e "  架构: ${GREEN}$kernel_arch${NC}"
    echo -e "  类型: ${GREEN}$kernel_variant${NC}"
    
    # 检测可用的内核版本
    local installed_kernels=$(dpkg -l | grep -E 'pve-kernel|linux-image' | grep -E 'ii|hi' | awk '{print $2}' | sort -V)
    if [[ -n "$installed_kernels" ]]; then
        echo -e "${CYAN}已安装的内核版本：${NC}"
        while IFS= read -r kernel; do
            echo -e "  ${GREEN}•${NC} $kernel"
        done <<< "$installed_kernels"
    fi
    
    return 0
}

# 获取可用内核列表
get_available_kernels() {
    log_info "获取可用内核列表..."
    
    # 检查网络连接
    if ! ping -c 1 mirrors.tuna.tsinghua.edu.cn &> /dev/null; then
        log_error "网络连接失败，无法获取内核列表"
        return 1
    fi
    
    # 获取当前 PVE 版本
    local pve_version=$(pveversion | head -n1 | cut -d'/' -f2 | cut -d'-' -f1)
    local major_version=$(echo $pve_version | cut -d'.' -f1)
    
    # 构建内核包URL
    local kernel_url="https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/pve/dists/trixie/pve-no-subscription/binary-amd64/Packages"
    
    # 下载并解析可用内核
    local available_kernels=$(curl -s "$kernel_url" | grep -E 'Package: (pve-kernel|linux-pve)' | awk '{print $2}' | sort -V | uniq)
    
    if [[ -z "$available_kernels" ]]; then
        log_warn "无法获取可用内核列表，使用备用方法"
        # 备用方法：使用apt-cache搜索
        available_kernels=$(apt-cache search --names-only '^pve-kernel-.*' | awk '{print $1}' | sort -V)
    fi
    
    if [[ -n "$available_kernels" ]]; then
        echo -e "${CYAN}可用内核版本：${NC}"
        while IFS= read -r kernel; do
            echo -e "  ${BLUE}•${NC} $kernel"
        done <<< "$available_kernels"
    else
        log_error "无法找到可用内核"
        return 1
    fi
    
    return 0
}

# 安装指定内核版本
install_kernel() {
    local kernel_version=$1
    
    # 验证内核版本格式
    if [[ -z "$kernel_version" ]]; then
        log_error "请指定要安装的内核版本"
        return 1
    fi
    
    if ! [[ "$kernel_version" =~ ^pve-kernel- ]]; then
        log_warn "内核版本格式可能不正确，尝试自动修正"
        kernel_version="pve-kernel-$kernel_version"
    fi
    
    log_info "开始安装内核: ${GREEN}$kernel_version${NC}"
    
    # 检查内核是否已安装
    if dpkg -l | grep -q "^ii.*$kernel_version"; then
        log_warn "内核 $kernel_version 已经安装"
        read -p "是否重新安装？(y/N): " reinstall
        if [[ "$reinstall" != "y" && "$reinstall" != "Y" ]]; then
            return 0
        fi
    fi
    
    # 更新软件包列表
    log_info "更新软件包列表..."
    if ! apt-get update; then
        log_error "更新软件包列表失败"
        return 1
    fi
    
    # 安装内核
    log_info "正在安装内核 $kernel_version ..."
    if ! apt-get install -y "$kernel_version"; then
        log_error "内核安装失败"
        return 1
    fi
    
    log_success "内核 $kernel_version 安装成功"
    
    # 更新引导配置
    update_grub_config
    
    return 0
}

# 更新 GRUB 配置
update_grub_config() {
    log_info "更新引导配置..."
    
    # 检查是否是 UEFI 系统
    local efi_dir="/boot/efi"
    local grub_cfg=""
    
    if [[ -d "$efi_dir" ]]; then
        log_info "检测到 UEFI 启动模式"
        grub_cfg="/boot/efi/EFI/proxmox/grub.cfg"
    else
        log_info "检测到 Legacy BIOS 启动模式"
        grub_cfg="/boot/grub/grub.cfg"
    fi
    
    # 更新 GRUB
    if command -v update-grub &> /dev/null; then
        if update-grub; then
            log_success "GRUB 配置更新成功"
        else
            log_warn "GRUB 配置更新过程中出现警告，但可能仍然成功"
        fi
    elif command -v grub-mkconfig &> /dev/null; then
        if grub-mkconfig -o "$grub_cfg"; then
            log_success "GRUB 配置更新成功"
        else
            log_warn "GRUB 配置更新过程中出现警告"
        fi
    else
        log_error "找不到 GRUB 更新工具"
        return 1
    fi
    
    return 0
}

# 切换默认启动内核
set_default_kernel() {
    local kernel_version=$1
    
    if [[ -z "$kernel_version" ]]; then
        log_error "请指定要设置为默认的内核版本"
        return 1
    fi
    
    log_info "设置默认启动内核: ${GREEN}$kernel_version${NC}"
    
    # 检查内核是否存在
    if ! [[ -d "/boot/initrd.img-$kernel_version" || -d "/boot/vmlinuz-$kernel_version" ]]; then
        log_error "内核文件不存在，请先安装该内核"
        return 1
    fi
    
    # 使用 grub-set-default 设置默认内核
    if command -v grub-set-default &> /dev/null; then
        # 查找内核在 GRUB 菜单中的位置
        local menu_entry=$(grep -n "$kernel_version" /boot/grub/grub.cfg | head -1 | cut -d: -f1)
        if [[ -n "$menu_entry" ]]; then
            # 计算 GRUB 菜单项索引（从0开始）
            local grub_index=$(( (menu_entry - 1) / 2 ))
            if grub-set-default "$grub_index"; then
                log_success "默认启动内核设置成功"
                return 0
            fi
        fi
    fi
    
    # 备用方法：手动编辑 GRUB 配置
    log_warn "使用备用方法设置默认内核"
    
    # 备份当前 GRUB 配置
    cp /etc/default/grub /etc/default/grub.backup.$(date +%Y%m%d%H%M%S)
    
    # 设置 GRUB_DEFAULT 为内核版本
    if sed -i "s/^GRUB_DEFAULT=.*/GRUB_DEFAULT=\"Advanced options for Proxmox VE GNU\/Linux>Proxmox VE GNU\/Linux, with Linux $kernel_version\"/" /etc/default/grub; then
        log_success "GRUB 配置更新成功"
        update_grub_config
        return 0
    else
        log_error "GRUB 配置更新失败"
        return 1
    fi
}

# 删除旧内核（保留最近2个版本）
remove_old_kernels() {
    log_info "清理旧内核..."
    
    # 获取所有已安装的内核
    local installed_kernels=$(dpkg -l | grep -E '^ii.*pve-kernel' | awk '{print $2}' | sort -V)
    local kernel_count=$(echo "$installed_kernels" | wc -l)
    
    if [[ $kernel_count -le 2 ]]; then
        log_info "当前只有 $kernel_count 个内核，无需清理"
        return 0
    fi
    
    # 计算需要保留的内核数量（保留最新的2个）
    local keep_count=2
    local remove_count=$((kernel_count - keep_count))
    
    echo -e "${YELLOW}将删除 $remove_count 个旧内核，保留最新的 $keep_count 个内核${NC}"
    
    # 获取要删除的内核列表（最旧的几个）
    local kernels_to_remove=$(echo "$installed_kernels" | head -n $remove_count)
    
    read -p "是否继续？(y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "取消内核清理"
        return 0
    fi
    
    # 删除旧内核
    while IFS= read -r kernel; do
        log_info "正在删除内核: $kernel"
        if apt-get remove -y --purge "$kernel"; then
            log_success "内核 $kernel 删除成功"
        else
            log_error "删除内核 $kernel 失败"
        fi
    done <<< "$kernels_to_remove"
    
    # 更新引导配置
    update_grub_config
    
    log_success "旧内核清理完成"
    return 0
}

# 内核管理主菜单
kernel_management_menu() {
    while true; do
        echo -e "\n"
        show_menu_header "内核管理菜单"
        create_aligned_menu \
            "1" "显示当前内核信息" \
            "2" "查看可用内核列表" \
            "3" "安装新内核" \
            "4" "设置默认启动内核" \
            "5" "清理旧内核" \
            "6" "重启系统应用新内核"
        echo -e "${UI_DIVIDER}"
        show_menu_option "0" "返回主菜单"
        show_menu_footer
        
        choice=$(get_menu_choice "请选择操作 [0-6]: " "0 1 2 3 4 5 6" "0")
        
        case $choice in
            1)
                check_kernel_version
                ;;
            2)
                get_available_kernels
                ;;
            3)
                read -p "请输入要安装的内核版本 (例如: 6.8.8-1): " kernel_ver
                if [[ -n "$kernel_ver" ]]; then
                    install_kernel "$kernel_ver"
                else
                    log_error "请输入有效的内核版本"
                fi
                ;;
            4)
                read -p "请输入要设置为默认的内核版本 (例如: 6.8.8-1-pve): " kernel_ver
                if [[ -n "$kernel_ver" ]]; then
                    set_default_kernel "$kernel_ver"
                else
                    log_error "请输入有效的内核版本"
                fi
                ;;
            5)
                remove_old_kernels
                ;;
            6)
                read -p "确认要重启系统吗？(y/N): " reboot_confirm
                if [[ "$reboot_confirm" == "y" || "$reboot_confirm" == "Y" ]]; then
                    log_info "系统将在5秒后重启..."
                    echo -e "${YELLOW}按 Ctrl+C 取消重启${NC}"
                    sleep 5
                    reboot
                else
                    log_info "取消重启"
                fi
                ;;
            0)
                break
                ;;
            *)
                log_error "无效的选择，请重新输入"
                ;;
        esac
        
        echo
        pause_function
    done
}

# 内核同步更新（自动检测并更新到最新稳定版）
sync_kernel_update() {
    log_info "开始内核同步更新检查..."
    
    # 获取当前内核版本
    local current_kernel=$(uname -r)
    log_info "当前内核版本: ${GREEN}$current_kernel${NC}"
    
    # 获取最新可用内核
    local latest_kernel=$(get_available_kernels | tail -1 | awk '{print $2}')
    
    if [[ -z "$latest_kernel" ]]; then
        log_error "无法获取最新内核信息"
        return 1
    fi
    
    log_info "最新可用内核: ${GREEN}$latest_kernel${NC}"
    
    # 检查是否需要更新
    if [[ "$current_kernel" == *"$latest_kernel"* ]]; then
        log_success "当前已是最新内核，无需更新"
        return 0
    fi
    
    echo -e "${YELLOW}发现新内核版本: $latest_kernel${NC}"
    read -p "是否安装并更新到最新内核？(Y/n): " update_confirm
    
    if [[ "$update_confirm" == "n" || "$update_confirm" == "N" ]]; then
        log_info "取消内核更新"
        return 0
    fi
    
    # 安装最新内核
    if install_kernel "$latest_kernel"; then
        # 设置新内核为默认启动项
        if set_default_kernel "$latest_kernel"; then
            log_success "内核同步更新完成"
            echo -e "${YELLOW}建议重启系统以应用新内核${NC}"
            return 0
        else
            log_warn "内核安装成功但设置默认启动项失败"
            return 1
        fi
    else
        log_error "内核更新失败"
        return 1
    fi
}

# 备份文件
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        # 创建备份目录
        local backup_dir="/etc/pve-tools-9-bak"
        mkdir -p "$backup_dir"
        
        # 生成带时间戳的备份文件名
        local filename=$(basename "$file")
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_path="${backup_dir}/${filename}.backup.${timestamp}"
        
        cp "$file" "$backup_path"
        log_info "贴心备份完成: ${CYAN}$file${NC}"
        log_info "备份文件位置: ${CYAN}${backup_path}${NC}"
    fi
}

# 换源功能
change_sources() {
    log_step "开始为您的 PVE 换上飞速源"
    
    # 根据选择的镜像源确定URL
    local debian_mirror=""
    local debian_security_mirror=""
    local pve_mirror=""
    
    case $SELECTED_MIRROR in
        $MIRROR_USTC)
            debian_mirror="https://mirrors.ustc.edu.cn/debian"
            pve_mirror="$MIRROR_USTC"
            ;;
        $MIRROR_TUNA)
            debian_mirror="https://mirrors.tuna.tsinghua.edu.cn/debian"
            pve_mirror="$MIRROR_TUNA"
            ;;
        $MIRROR_DEBIAN)
            debian_mirror="https://deb.debian.org/debian"
            debian_security_mirror="https://security.debian.org/debian-security"
            pve_mirror="https://ftp.debian.org/debian"
            ;;
    esac
    
    # 询问用户是否要更换安全更新源
    log_info "安全更新源选择"
    echo "  安全更新源包含重要的系统安全补丁，选择合适的源很重要："
    echo "  1) 使用官方安全源 (推荐，更新最及时，但可能较慢)"
    echo "  2) 使用镜像站安全源 (速度快，但可能有延迟)"
    echo ""
    
    read -p "  请选择 [1-2] (默认: 1): " security_choice
    security_choice=${security_choice:-1}
    
    if [[ "$security_choice" == "2" ]]; then
        # 使用镜像站的安全源
        case $SELECTED_MIRROR in
            $MIRROR_USTC)
                debian_security_mirror="https://mirrors.ustc.edu.cn/debian-security"
                ;;
            $MIRROR_TUNA)
                debian_security_mirror="https://mirrors.tuna.tsinghua.edu.cn/debian-security"
                ;;
            $MIRROR_DEBIAN)
                debian_security_mirror="https://security.debian.org/debian-security"
                ;;
        esac
        log_info "将使用镜像站的安全更新源"
    else
        # 使用官方安全源
        debian_security_mirror="https://security.debian.org/debian-security"
        log_info "将使用官方安全更新源"
    fi
    
    # 1. 更换 Debian 软件源 (DEB822 格式)
    log_info "正在配置 Debian 镜像源..."
    backup_file "/etc/apt/sources.list.d/debian.sources"
    
    cat > /etc/apt/sources.list.d/debian.sources << EOF
Types: deb
URIs: $debian_mirror
Suites: trixie trixie-updates trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
# Types: deb-src
# URIs: $debian_mirror
# Suites: trixie trixie-updates trixie-backports
# Components: main contrib non-free non-free-firmware
# Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# 以下安全更新软件源包含了官方源与镜像站配置，如有需要可自行修改注释切换
Types: deb
URIs: $debian_security_mirror
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# Types: deb-src
# URIs: $debian_security_mirror
# Suites: trixie-security
# Components: main contrib non-free non-free-firmware
# Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
    
    # 2. 注释企业源
    log_info "正在关闭企业源（我们用免费版就够啦）..."
    if [[ -f "/etc/apt/sources.list.d/pve-enterprise.sources" ]]; then
        backup_file "/etc/apt/sources.list.d/pve-enterprise.sources"
        sed -i 's/^Types:/#Types:/g' /etc/apt/sources.list.d/pve-enterprise.sources
        sed -i 's/^URIs:/#URIs:/g' /etc/apt/sources.list.d/pve-enterprise.sources
        sed -i 's/^Suites:/#Suites:/g' /etc/apt/sources.list.d/pve-enterprise.sources
        sed -i 's/^Components:/#Components:/g' /etc/apt/sources.list.d/pve-enterprise.sources
        sed -i 's/^Signed-By:/#Signed-By:/g' /etc/apt/sources.list.d/pve-enterprise.sources
    fi
    
    # 3. 更换 Ceph 源
    log_info "正在配置 Ceph 镜像源..."
    if [[ -f "/etc/apt/sources.list.d/ceph.sources" ]]; then
        backup_file "/etc/apt/sources.list.d/ceph.sources"
        cat > /etc/apt/sources.list.d/ceph.sources << EOF
Types: deb
URIs: $pve_mirror
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    fi
    
    # 4. 添加无订阅源
    log_info "正在添加免费版专用源..."
    cat > /etc/apt/sources.list.d/pve-no-subscription.sources << EOF
Types: deb
URIs: $pve_mirror
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    
    # 5. 更换 CT 模板源
    log_info "正在加速 CT 模板下载..."
    if [[ -f "/usr/share/perl5/PVE/APLInfo.pm" ]]; then
        backup_file "/usr/share/perl5/PVE/APLInfo.pm"
        sed -i "s|http://download.proxmox.com|$pve_mirror|g" /usr/share/perl5/PVE/APLInfo.pm
    fi
    
    log_success "太棒了！所有源都换成飞速版本啦"
}

# 删除订阅弹窗
remove_subscription_popup() {
    log_step "正在消除那个烦人的订阅弹窗"
    
    local js_file="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
    if [[ -f "$js_file" ]]; then
        backup_file "$js_file"
        sed -Ezi.bak "s/(Ext.Msg.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" "$js_file"
        systemctl restart pveproxy.service
        log_success "完美！再也不会有烦人的弹窗啦"
    else
        log_warn "咦？没找到弹窗文件，可能已经被处理过了"
    fi
}

# 合并 local 与 local-lvm
merge_local_storage() {
    log_step "准备合并存储空间，让小硬盘发挥最大价值"
    log_warn "重要提醒：此操作会删除 local-lvm，请确保重要数据已备份！"
    
    echo -e "${YELLOW}您确定要继续吗？这个操作不可逆哦${NC}"
    read -p "输入 'yes' 确认继续，其他任意键取消: " -r
    if [[ ! $REPLY == "yes" ]]; then
        log_info "明智的选择！操作已取消"
        return
    fi
    
    # 检查 local-lvm 是否存在
    if ! lvdisplay /dev/pve/data &> /dev/null; then
        log_warn "没有找到 local-lvm 分区，可能已经合并过了"
        return
    fi
    
    log_info "正在删除 local-lvm 分区..."
    lvremove -f /dev/pve/data
    
    log_info "正在扩容 local 分区..."
    lvextend -l +100%FREE /dev/pve/root
    
    log_info "正在扩展文件系统..."
    resize2fs /dev/pve/root
    
    log_success "存储合并完成！现在空间更充裕了"
    log_warn "温馨提示：请在 Web UI 中删除 local-lvm 存储配置，并编辑 local 存储勾选所有内容类型"
}

# 删除 Swap 分配给主分区
remove_swap() {
    log_step "准备释放 Swap 空间给系统使用"
    log_warn "注意：删除 Swap 后请确保内存充足！"
    
    echo -e "${YELLOW}您确定要删除 Swap 分区吗？${NC}"
    read -p "输入 'yes' 确认继续，其他任意键取消: " -r
    if [[ ! $REPLY == "yes" ]]; then
        log_info "好的，操作已取消"
        return
    fi
    
    # 检查 swap 是否存在
    if ! lvdisplay /dev/pve/swap &> /dev/null; then
        log_warn "没有找到 swap 分区，可能已经删除过了"
        return
    fi
    
    log_info "正在关闭 Swap..."
    swapoff /dev/mapper/pve-swap
    
    log_info "正在修改启动配置..."
    backup_file "/etc/fstab"
    sed -i 's|^/dev/pve/swap|# /dev/pve/swap|g' /etc/fstab
    
    log_info "正在删除 swap 分区..."
    lvremove -f /dev/pve/swap
    
    log_info "正在扩展系统分区..."
    lvextend -l +100%FREE /dev/mapper/pve-root
    
    log_info "正在扩展文件系统..."
    resize2fs /dev/mapper/pve-root
    
    log_success "Swap 删除完成！系统空间更宽裕了"
}

# 更新系统
update_system() {
    log_step "开始更新系统，让 PVE 保持最新状态 📦"
    
    echo -e "${CYAN}正在更新软件包列表...${NC}"
    apt update
    
    echo -e "${CYAN}正在升级系统软件包...${NC}"
    apt upgrade -y
    
    echo -e "${CYAN}正在清理不需要的软件包...${NC}"
    apt autoremove -y
    
    log_success "系统更新完成！您的 PVE 现在是最新版本"
}

# 标准化暂停函数
pause_function() {
    echo -ne "${CYAN}按任意键继续...${NC} "
    read -n 1 -s input
    if [[ -n ${input} ]]; then
        echo -e "\b
"
    fi
}

# Enhanced input validation function
validate_input() {
    local input="$1"
    local valid_options="$2"
    local default_value="${3:-}"
    
    if [[ -z "$input" && -n "$default_value" ]]; then
        echo "$default_value"
        return 0
    fi
    
    if [[ -n "$valid_options" ]]; then
        local option
        for option in $valid_options; do
            if [[ "$input" == "$option" ]]; then
                echo "$input"
                return 0
            fi
        done
        # If we reached here, input was not in valid options
        echo ""
        return 1
    else
        # If no valid options provided, return input as is
        echo "$input"
        return 0
    fi
}

# Enhanced menu input function with validation
get_menu_choice() {
    local prompt="$1"
    local valid_options="$2"
    local default_value="${3:-}"
    
    while true; do
        read -p "$prompt" choice
        validated_choice=$(validate_input "$choice" "$valid_options" "$default_value")
        
        if [[ -n "$validated_choice" ]]; then
            echo "$validated_choice"
            return 0
        else
            log_error "无效选择，请重新输入！"
            echo -ne "${YELLOW}有效选项: $valid_options${NC}\n"
        fi
    done
}

#--------------开启硬件直通----------------
# 开启硬件直通
enable_pass() {
    echo
    log_step "开启硬件直通..."
    if [ `dmesg | grep -e DMAR -e IOMMU|wc -l` = 0 ];then
        log_error "您的硬件不支持直通！不如检查一下主板的BIOS设置？"
        pause_function
        return
    fi
    if [ `cat /proc/cpuinfo|grep Intel|wc -l` = 0 ];then
        iommu="amd_iommu=on"
    else
        iommu="intel_iommu=on"
    fi
    if [ `grep $iommu /etc/default/grub|wc -l` = 0 ];then
        backup_file "/etc/default/grub"
        sed -i 's|quiet|quiet '$iommu'|' /etc/default/grub
        update-grub
        if [ `grep "vfio" /etc/modules|wc -l` = 0 ];then
            cat <<-EOF >> /etc/modules
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
kvmgt
EOF
        fi
        
        if [ ! -f "/etc/modprobe.d/blacklist.conf" ];then
            echo "blacklist snd_hda_intel" >> /etc/modprobe.d/blacklist.conf 
            echo "blacklist snd_hda_codec_hdmi" >> /etc/modprobe.d/blacklist.conf 
            echo "blacklist i915" >> /etc/modprobe.d/blacklist.conf 
        fi

        if [ ! -f "/etc/modprobe.d/vfio.conf" ];then
            echo "options vfio-pci ids=8086:3185" >> /etc/modprobe.d/vfio.conf
        fi
        
        log_success "开启设置后需要重启系统，请准备就绪后重启宿主机"
        log_tips "重启后才可以应用对内核引导的修改哦！命令是 reboot"
    else
        log_warn "您已经配置过!"
    fi
}

# 关闭硬件直通
disable_pass() {
    echo
    log_step "关闭硬件直通..."
    if [ `dmesg | grep -e DMAR -e IOMMU|wc -l` = 0 ];then
        log_error "您的硬件不支持直通！"
        log_tips "不如检查一下主板的BIOS设置？"
        pause_function
        return
    fi
    if [ `cat /proc/cpuinfo|grep Intel|wc -l` = 0 ];then
        iommu="amd_iommu=on"
    else
        iommu="intel_iommu=on"
    fi
    if [ `grep $iommu /etc/default/grub|wc -l` = 0 ];then
        log_warn "您还没有配置过该项"
    else
        backup_file "/etc/default/grub"
        {
            sed -i 's/ '$iommu'//g' /etc/default/grub
            sed -i '/vfio/d' /etc/modules
            rm -rf /etc/modprobe.d/blacklist.conf
            rm -rf /etc/modprobe.d/vfio.conf
            sleep 1
        }
        log_success "关闭设置后需要重启系统，请准备就绪后重启宿主机。"
        log_tips "重启后才可以应用对内核引导的修改哦！命令是 reboot"
        sleep 1
        update-grub
    fi
}

# 硬件直通菜单
hw_passth() {
    while :; do
        clear
        show_banner
        show_menu_header "配置硬件直通"
        create_aligned_menu \
            "1" "开启硬件直通" \
            "2" "关闭硬件直通" \
            "0" "返回"
        show_menu_footer
        read -p "请选择: [ ]" -n 1 hwmenuid
        echo  # New line after input
        hwmenuid=${hwmenuid:-0}
        case "${hwmenuid}" in
            1)
                enable_pass
                pause_function
                ;;
            2)
                disable_pass
                pause_function
                ;;
            0)
                break
                ;;
            *)
                log_error "无效选项!"
                pause_function
                ;;
        esac
    done
}
#--------------开启硬件直通----------------

#--------------设置CPU电源模式----------------
# 设置CPU电源模式
cpupower() {
    governors=`cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors`
    while :; do
        clear
        show_banner
        show_menu_header "设置CPU电源模式"
        create_aligned_menu \
            "1" "设置CPU模式 conservative  保守模式   [变身老年机]" \
            "2" "设置CPU模式 ondemand       按需模式  [默认]" \
            "3" "设置CPU模式 powersave      节能模式  [省电小能手]" \
            "4" "设置CPU模式 performance   性能模式   [性能释放]" \
            "5" "设置CPU模式 schedutil      负载模式  [交给负载自动配置]" \
            "6" "恢复系统默认电源设置"
        echo
        show_menu_option "0" "返回"
        show_menu_footer
        echo
        echo "部分CPU仅支持 performance 和 powersave 模式，只能选择这两项，其他模式无效不要选！"
        echo
        echo "你的CPU支持 ${governors} 模式"
        echo
        read -p "请选择: [ ]" -n 1 cpupowerid
        echo  # New line after input
        cpupowerid=${cpupowerid:-2}
        case "${cpupowerid}" in
            1)
                GOVERNOR="conservative"
                ;;
            2)
                GOVERNOR="ondemand"
                ;;
            3)
                GOVERNOR="powersave"
                ;;
            4)
                GOVERNOR="performance"
                ;;
            5)
                GOVERNOR="schedutil"
                ;;
            6)
                cpupower_del
                pause_function
                break
                ;;
            0)
                break
                ;;
            *)
                log_error "你的输入无效，请重新输入！"
                pause_function
                ;;
        esac
        if [[ ${GOVERNOR} != "" ]]; then
            if [[ -n `echo "${governors}" | grep -o "${GOVERNOR}"` ]]; then
                echo "您选择的CPU模式：${GOVERNOR}"
                echo
                cpupower_add
                pause_function
            else
                log_error "您的CPU不支持该模式！"
                log_tips "现在暂时不会对你的系统造成影响，但是下次开机时，CPU模式会恢复为默认模式。"
                pause_function
            fi
        fi
    done
}

# 修改CPU模式
cpupower_add() {
    echo "${GOVERNOR}" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
    echo "查看当前CPU模式"
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

    echo "正在添加开机任务"
    NEW_CRONTAB_COMMAND="sleep 10 && echo "${GOVERNOR}" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null #CPU Power Mode"
    EXISTING_CRONTAB=$(crontab -l 2>/dev/null)
    if [[ -n "$EXISTING_CRONTAB" ]]; then
        TEMP_CRONTAB_FILE=$(mktemp)
        echo "$EXISTING_CRONTAB" | grep -v "@reboot sleep 10 && echo*" > "$TEMP_CRONTAB_FILE"
        crontab "$TEMP_CRONTAB_FILE"
        rm "$TEMP_CRONTAB_FILE"
    fi
    log_success "CPU模式已修改完成"
    # 修改完成
    (crontab -l 2>/dev/null; echo "@reboot $NEW_CRONTAB_COMMAND") | crontab -
    echo -e "
检查计划任务设置 (使用 'crontab -l' 命令来检查)"
}

# 恢复系统默认电源设置
cpupower_del() {
    # 恢复性模式
    echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
    # 删除计划任务
    EXISTING_CRONTAB=$(crontab -l 2>/dev/null)
    if [[ -n "$EXISTING_CRONTAB" ]]; then
        TEMP_CRONTAB_FILE=$(mktemp)
        echo "$EXISTING_CRONTAB" | grep -v "@reboot sleep 10 && echo*" > "$TEMP_CRONTAB_FILE"
        crontab "$TEMP_CRONTAB_FILE"
        rm "$TEMP_CRONTAB_FILE"
    fi

    log_success "已恢复系统默认电源设置！还是默认的好用吧"
}
#--------------设置CPU电源模式----------------

#--------------CPU、主板、硬盘温度显示----------------
# 安装工具
cpu_add() {
    nodes="/usr/share/perl5/PVE/API2/Nodes.pm"
    pvemanagerlib="/usr/share/pve-manager/js/pvemanagerlib.js"
    proxmoxlib="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"

    pvever=$(pveversion | awk -F"/" '{print $2}')
    echo pve版本$pvever

    # 判断是否已经执行过修改
    [ ! -e $nodes.$pvever.bak ] || { log_warn "已经执行过修改，请勿重复执行"; pause_function; return;}

    # 先刷新下源
    log_step "更新软件包列表..."
    apt-get update

    log_step "开始安装所需工具..."
    # 输入需要安装的软件包
    packages=(lm-sensors nvme-cli sysstat linux-cpupower)

    # 查询软件包，判断是否安装
    for package in "${packages[@]}"; do
        if ! dpkg -s "$package" &> /dev/null; then
            echo "$package 未安装，开始安装软件包"
            apt-get install "${packages[@]}" -y
            modprobe msr
            install=ok
            break
        fi
    done

    # 设置执行权限
    if dpkg -s "linux-cpupower" &> /dev/null; then
        chmod +s /usr/sbin/linux-cpupower || echo "Failed to set permissions for /usr/sbin/linux-cpupower"
    fi

    chmod +s /usr/sbin/nvme
    chmod +s /usr/sbin/hddtemp
    chmod +s /usr/sbin/smartctl
    chmod +s /usr/sbin/turbostat || echo "Failed to set permissions for /usr/sbin/turbostat"
    modprobe msr && echo msr > /etc/modules-load.d/turbostat-msr.conf

    # 软件包安装完成
    if [ "$install" == "ok" ]; then
        log_info "软件包安装完成，检测硬件信息"
        sensors-detect --auto > /tmp/sensors
        drivers=`sed -n '/Chip drivers/,/\\#----cut here/p' /tmp/sensors|sed '/Chip /d'|sed '/cut/d'`
        if [ `echo $drivers|wc -w` = 0 ];then
            log_error "没有找到任何驱动，似乎你的系统不支持或驱动安装失败。"
            log_tips "请检查你的硬件是否支持，或者尝试手动安装驱动。"
            log_tips "手动安装驱动方法：去制造商官网找驱动，然后手动安装。不会装驱动建议去问问AI"
            log_tips "猜你再找: https://claude.ai"
            pause_function
            return
        else
            for i in $drivers
            do
                modprobe $i
                if [ `grep $i /etc/modules|wc -l` = 0 ];then
                    echo $i >> /etc/modules
                fi
            done
            sensors
            sleep 3
            log_success "驱动信息配置成功。"
        fi
        /etc/init.d/kmod start
        rm /tmp/sensors
        # 驱动信息配置完成
    fi

    log_step "备份源文件"
    # 删除旧版本备份文件
    rm -f  $nodes.*.bak
    rm -f  $pvemanagerlib.*.bak
    rm -f  $proxmoxlib.*.bak
    # 备份当前版本文件
    [ ! -e $nodes.$pvever.bak ] && cp $nodes $nodes.$pvever.bak
    [ ! -e $pvemanagerlib.$pvever.bak ] && cp $pvemanagerlib $pvemanagerlib.$pvever.bak
    [ ! -e $proxmoxlib.$pvever.bak ] && cp $proxmoxlib $proxmoxlib.$pvever.bak

    # 生成系统变量
    tmpf=tmpfile.temp
    touch $tmpf
    cat > $tmpf << 'EOF' 
    $res->{thermalstate} = `sensors`;
    $res->{cpusensors} = `cat /proc/cpuinfo | grep MHz && lscpu | grep MHz`;
    
    my $nvme0_temperatures = `smartctl -a /dev/nvme0|grep -E "Model Number|(?=Total|Namespace)[^:]+Capacity|Temperature:|Available Spare:|Percentage|Data Unit|Power Cycles|Power On Hours|Unsafe Shutdowns|Integrity Errors"`;
    my $nvme0_io = `iostat -d -x -k 1 1 | grep -E "^nvme0"`;
    $res->{nvme0_status} = $nvme0_temperatures . $nvme0_io;
    
    $res->{hdd_temperatures} = `smartctl -a /dev/sd?|grep -E "Device Model|Capacity|Power_On_Hours|Temperature"`;

    my $powermode = `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor && turbostat -S -q -s PkgWatt -i 0.1 -n 1 -c package | grep -v PkgWatt`;
    $res->{cpupower} = $powermode;

EOF

    ###################  修改node.pm   ##########################
    log_info "开始大活"
    log_info "修改node.pm："
    log_info "找到关键字 PVE::pvecfg::version_text 的行号并跳到下一行"
    # 显示匹配的行
    ln=$(expr $(sed -n -e '/PVE::pvecfg::version_text/=' $nodes) + 1)
    log_info "匹配的行号： $ln"

    log_info "修改结果："
    sed -i "${ln}r $tmpf" $nodes
    # 显示修改结果
    sed -n '/PVE::pvecfg::version_text/,+18p' $nodes
    rm $tmpf

    ###################  修改pvemanagerlib.js   ##########################
    tmpf=tmpfile.temp
    touch $tmpf
    cat > $tmpf << 'EOF'

    {
          itemId: 'CPUW',
          colspan: 2,
          printBar: false,
          title: gettext('CPU功耗'),
          textField: 'cpupower',
          renderer:function(value){
              const w0 = value.split('\n')[0].split(' ')[0];
              const w1 = value.split('\n')[1].split(' ')[0];
              return `CPU电源模式: <strong>${w0}</strong> | CPU功耗: <strong>${w1} W</strong> `
            }
    },

    {
          itemId: 'MHz',
          colspan: 2,
          printBar: false,
          title: gettext('CPU频率'),
          textField: 'cpusensors',
          renderer:function(value){
              const f0 = value.match(/cpu MHz.*?([\d]+)/)[1];
              const f1 = value.match(/CPU min MHz.*?([\d]+)/)[1];
              const f2 = value.match(/CPU max MHz.*?([\d]+)/)[1];
              return `CPU实时: <strong>${f0} MHz</strong> | 最小: ${f1} MHz | 最大: ${f2} MHz `
            }
    },
    
    {
          itemId: 'thermal',
          colspan: 2,
          printBar: false,
          title: gettext('CPU温度'),
          textField: 'thermalstate',
          renderer: function(value) {
              const coreTemps = [];
              let coreMatch;
              const coreRegex = /(Core\s*\d+|Core\d+|Tdie|Tctl|Physical id\s*\d+).*?\+\s*([\d\.]+)/gi;

              while ((coreMatch = coreRegex.exec(value)) !== null) {
                  let label = coreMatch[1];
                  let tempValue = coreMatch[2];

                  if (label.match(/Tdie|Tctl/i)) {
                      coreTemps.push(`CPU温度: <strong>${tempValue}℃</strong>`);
                  }

                  else {
                      const coreNumberMatch = label.match(/\d+/);
                      const coreNum = coreNumberMatch ? parseInt(coreNumberMatch[0]) + 1 : 1;
                      coreTemps.push(`核心${coreNum}: <strong>${tempValue}℃</strong>`);
                  }
              }

              // 核显温度
              let igpuTemp = '';
              const intelIgpuMatch = value.match(/(GFX|Graphics).*?\+\s*([\d\.]+)/i);
              const amdIgpuMatch = value.match(/(junction|edge).*?\+\s*([\d\.]+)/i);
        
              if (intelIgpuMatch) {
                  igpuTemp = `核显: ${intelIgpuMatch[2]}℃`;
              } else if (amdIgpuMatch) {
                  igpuTemp = `核显: ${amdIgpuMatch[2]}℃`;
              }

              if (coreTemps.length === 0) {
                  const k10tempMatch = value.match(/k10temp-pci-\w+\n[^+]*\+\s*([\d\.]+)/);
                  if (k10tempMatch) {
                      coreTemps.push(`CPU温度: <strong>${k10tempMatch[1]}℃</strong>`);
                  }
              }

              const groupedTemps = [];
              for (let i = 0; i < coreTemps.length; i += 4) {
                  groupedTemps.push(coreTemps.slice(i, i + 4).join(' | '));
              }

              const packageMatch = value.match(/(Package|SoC)\s*(id \d+)?.*?\+\s*([\d\.]+)/i);
              const packageTemp = packageMatch ? `CPU Package: <strong>${packageMatch[3]}℃</strong>` : '';

              const boardTempMatch = value.match(/(?:temp1|motherboard|sys).*?\+\s*([\d\.]+)/i);
              const boardTemp = boardTempMatch ? `主板: <strong>${boardTempMatch[1]}℃</strong>` : '';

              const combinedTemps = [
                  igpuTemp,
                  packageTemp,
                  boardTemp
              ].filter(Boolean).join(' | ');

              const result = [
                  groupedTemps.join('<br>'),
                  combinedTemps
              ].filter(Boolean).join('<br>');

              return result || '未获取到温度信息';
          }
    },

    {
          itemId: 'HEXIN',
          colspan: 2,
          printBar: false,
          title: gettext('核心频率'),
          textField: 'cpusensors',
          renderer: function(value) {
              const freqMatches = value.matchAll(/^cpu MHz\s*:\s*([\d\.]+)/gm);
              const frequencies = [];
              
              for (const match of freqMatches) {
                  const coreNum = frequencies.length + 1;
                  frequencies.push(`核心${coreNum}: <strong>${parseInt(match[1])} MHz</strong>`);
              }
              
              if (frequencies.length === 0) {
                  return '无法获取CPU频率信息';
              }
              
              const groupedFreqs = [];
              for (let i = 0; i < frequencies.length; i += 4) {
                  const group = frequencies.slice(i, i + 4);
                  groupedFreqs.push(group.join(' | '));
              }
              
              return groupedFreqs.join('<br>');
           }
    },
    
    /* 检测不到相关参数的可以注释掉---需要的注释本行即可
    // 风扇转速
    {
          itemId: 'RPM',
          colspan: 2,
          printBar: false,
          title: gettext('CPU风扇'),
          textField: 'thermalstate',
          renderer:function(value){
              const fan1 = value.match(/fan1:.*?\ ([\d.]+) R/)[1];
              const fan2 = value.match(/fan2:.*?\ ([\d.]+) R/)[1];
              if (fan1 === "0") {
                fan11 = "停转";
              } else {
                fan11 = fan1 + " RPM";
              }
              if (fan2 === "0") {
                fan22 = "停转";
              } else {
                fan22 = fan2 + " RPM";
              }
              return `CPU风扇: ${fan11} | 系统风扇: ${fan22}`
            }
    },
    检测不到相关参数的可以注释掉---需要的注释本行即可  */

    // /* 检测不到相关参数的可以注释掉---需要的注释本行即可
    // NVME硬盘温度
    {
        itemId: 'nvme0-status',
        colspan: 2,
        printBar: false,
        title: gettext('NVME硬盘'),
        textField: 'nvme0_status',
        renderer:function(value){
            if (value.length > 0) {
                value = value.replace(/Â/g, '');
                let data = [];
                let nvmeNumber = -1;

                let nvmes = value.matchAll(/(^(?:Model|Total|Temperature:|Available Spare:|Percentage|Data|Power|Unsafe|Integrity Errors|nvme)[\s\S]*)+/gm);
                
                for (const nvme of nvmes) {
                    if (/Model Number:/.test(nvme[1])) {
                    nvmeNumber++; 
                    data[nvmeNumber] = {
                        Models: [],
                        Integrity_Errors: [],
                        Capacitys: [],
                        Temperatures: [],
                        Available_Spares: [],
                        Useds: [],
                        Reads: [],
                        Writtens: [],
                        Cycles: [],
                        Hours: [],
                        Shutdowns: [],
                        States: [],
                        r_kBs: [],
                        r_awaits: [],
                        w_kBs: [],
                        w_awaits: [],
                        utils: []
                    };
                    }

                    let Models = nvme[1].matchAll(/^Model Number: *([ \S]*)$/gm);
                    for (const Model of Models) {
                        data[nvmeNumber]['Models'].push(Model[1]);
                    }

                    let Integrity_Errors = nvme[1].matchAll(/^Media and Data Integrity Errors: *([ \S]*)$/gm);
                    for (const Integrity_Error of Integrity_Errors) {
                        data[nvmeNumber]['Integrity_Errors'].push(Integrity_Error[1]);
                    }

                    let Capacitys = nvme[1].matchAll(/^(?=Total|Namespace)[^:]+Capacity:[^\[]*\[([ \S]*)\]$/gm);
                    for (const Capacity of Capacitys) {
                        data[nvmeNumber]['Capacitys'].push(Capacity[1]);
                    }

                    let Temperatures = nvme[1].matchAll(/^Temperature: *([\d]*)[ \S]*$/gm);
                    for (const Temperature of Temperatures) {
                        data[nvmeNumber]['Temperatures'].push(Temperature[1]);
                    }

                    let Available_Spares = nvme[1].matchAll(/^Available Spare: *([\d]*%)[ \S]*$/gm);
                    for (const Available_Spare of Available_Spares) {
                        data[nvmeNumber]['Available_Spares'].push(Available_Spare[1]);
                    }

                    let Useds = nvme[1].matchAll(/^Percentage Used: *([ \S]*)%$/gm);
                    for (const Used of Useds) {
                        data[nvmeNumber]['Useds'].push(Used[1]);
                    }

                    let Reads = nvme[1].matchAll(/^Data Units Read:[^\[]*\[([ \S]*)\]$/gm);
                    for (const Read of Reads) {
                        data[nvmeNumber]['Reads'].push(Read[1]);
                    }

                    let Writtens = nvme[1].matchAll(/^Data Units Written:[^\[]*\[([ \S]*)\]$/gm);
                    for (const Written of Writtens) {
                        data[nvmeNumber]['Writtens'].push(Written[1]);
                    }

                    let Cycles = nvme[1].matchAll(/^Power Cycles: *([ \S]*)$/gm);
                    for (const Cycle of Cycles) {
                        data[nvmeNumber]['Cycles'].push(Cycle[1]);
                    }

                    let Hours = nvme[1].matchAll(/^Power On Hours: *([ \S]*)$/gm);
                    for (const Hour of Hours) {
                        data[nvmeNumber]['Hours'].push(Hour[1]);
                    }

                    let Shutdowns = nvme[1].matchAll(/^Unsafe Shutdowns: *([ \S]*)$/gm);
                    for (const Shutdown of Shutdowns) {
                        data[nvmeNumber]['Shutdowns'].push(Shutdown[1]);
                    }

                    let States = nvme[1].matchAll(/^nvme\S+(( *\d+\.\d{2}){22})/gm);
                    for (const State of States) {
                        data[nvmeNumber]['States'].push(State[1]);
                        const IO_array = [...State[1].matchAll(/\d+\.\d{2}/g)];
                        if (IO_array.length > 0) {
                            data[nvmeNumber]['r_kBs'].push(IO_array[1]);
                            data[nvmeNumber]['r_awaits'].push(IO_array[4]);
                            data[nvmeNumber]['w_kBs'].push(IO_array[7]);
                            data[nvmeNumber]['w_awaits'].push(IO_array[10]);
                            data[nvmeNumber]['utils'].push(IO_array[21]);
                        }
                    }

                    let output = '';
                    for (const [i, nvme] of data.entries()) {
                        if (i > 0) output += '<br><br>';

                        if (nvme.Models.length > 0) {
                            output += `<strong>${nvme.Models[0]}</strong>`;

                            if (nvme.Integrity_Errors.length > 0) {
                                for (const nvmeIntegrity_Error of nvme.Integrity_Errors) {
                                    if (nvmeIntegrity_Error != 0) {
                                        output += ` (`;
                                        output += `0E: ${nvmeIntegrity_Error}-故障！`;
                                        if (nvme.Available_Spares.length > 0) {
                                            output += ', ';
                                            for (const Available_Spare of nvme.Available_Spares) {
                                                output += `备用空间: ${Available_Spare}`;
                                            }
                                        }
                                        output += `)`;
                                    }
                                }
                            }
                            output += '<br>';
                        }

                        if (nvme.Capacitys.length > 0) {
                            for (const nvmeCapacity of nvme.Capacitys) {
                                output += `容量: ${nvmeCapacity.replace(/ |,/gm, '')}`;
                            }
                        }

                        if (nvme.Useds.length > 0) {
                            output += ' | ';
                            for (const nvmeUsed of nvme.Useds) {
                                output += `寿命: <strong>${100-Number(nvmeUsed)}%</strong> `;
                                if (nvme.Reads.length > 0) {
                                    output += '(';
                                    for (const nvmeRead of nvme.Reads) {
                                        output += `已读${nvmeRead.replace(/ |,/gm, '')}`;
                                        output += ')';
                                    }
                                }

                                if (nvme.Writtens.length > 0) {
                                    output = output.slice(0, -1);
                                    output += ', ';
                                    for (const nvmeWritten of nvme.Writtens) {
                                        output += `已写${nvmeWritten.replace(/ |,/gm, '')}`;
                                    }
                                    output += ')';
                                }
                            }
                        }

                        if (nvme.Temperatures.length > 0) {
                            output += ' | ';
                            for (const nvmeTemperature of nvme.Temperatures) {
                                output += `温度: <strong>${nvmeTemperature}°C</strong>`;
                            }
                        }

                        if (nvme.States.length > 0) {
                            if (nvme.Models.length > 0) {
                                output += '\n';
                            }

                            output += 'I/O: ';
                            if (nvme.r_kBs.length > 0 || nvme.r_awaits.length > 0) {
                                output += '读-';
                                if (nvme.r_kBs.length > 0) {
                                    for (const nvme_r_kB of nvme.r_kBs) {
                                        var nvme_r_mB = `${nvme_r_kB}` / 1024;
                                        nvme_r_mB = nvme_r_mB.toFixed(2);
                                        output += `速度${nvme_r_mB}MB/s`;
                                    }
                                }
                                if (nvme.r_awaits.length > 0) {
                                    for (const nvme_r_await of nvme.r_awaits) {
                                        output += `, 延迟${nvme_r_await}ms / `;
                                    }
                                }
                            }

                            if (nvme.w_kBs.length > 0 || nvme.w_awaits.length > 0) {
                                output += '写-';
                                if (nvme.w_kBs.length > 0) {
                                    for (const nvme_w_kB of nvme.w_kBs) {
                                        var nvme_w_mB = `${nvme_w_kB}` / 1024;
                                        nvme_w_mB = nvme_w_mB.toFixed(2);
                                        output += `速度${nvme_w_mB}MB/s`;
                                    }
                                }
                                if (nvme.w_awaits.length > 0) {
                                    for (const nvme_w_await of nvme.w_awaits) {
                                        output += `, 延迟${nvme_w_await}ms | `;
                                    }
                                }
                            }

                            if (nvme.utils.length > 0) {
                                for (const nvme_util of nvme.utils) {
                                    output += `负载${nvme_util}%`;
                                }
                            }
                        }

                        if (nvme.Cycles.length > 0) {
                            output += '\n';
                            for (const nvmeCycle of nvme.Cycles) {
                                output += `通电: ${nvmeCycle.replace(/ |,/gm, '')}次`;
                            }

                            if (nvme.Shutdowns.length > 0) {
                                output += ', ';
                                for (const nvmeShutdown of nvme.Shutdowns) {
                                    output += `不安全断电${nvmeShutdown.replace(/ |,/gm, '')}次`;
                                    break
                                }
                            }

                            if (nvme.Hours.length > 0) {
                                output += ', ';
                                for (const nvmeHour of nvme.Hours) {
                                    output += `累计${nvmeHour.replace(/ |,/gm, '')}小时`;
                                }
                            }
                        }
                    //output = output.slice(0, -3);
                }
                return output.replace(/\n/g, '<br>');
            }

            return output;
        } else {
            return `提示: 未安装 NVME 或已直通 NVME 控制器！`;
        }
    }
},
    // 检测不到相关参数的可以注释掉---需要的注释本行即可  */

    // SATA硬盘温度
    {
        itemId: 'hdd-temperatures',
        colspan: 2,
        printBar: false,
        title: gettext('SATA硬盘'),
        textField: 'hdd_temperatures',
        renderer: function(value) {
            if (value.length > 0) {
               try {
               const jsonData = JSON.parse(value);
            if (jsonData.standy === true) {
               return '休眠中';
               }
            let output = '';
            if (jsonData.model_name) {
            output = `<strong>${jsonData.model_name}</strong><br>`;
                    if (jsonData.temperature?.current !== undefined) {
                       output += `温度: <strong>${jsonData.temperature.current}°C</strong>`;
                    }
                    if (jsonData.power_on_time?.hours !== undefined) {
                       if (output.length > 0) output += ' | ';
                       output += `通电: ${jsonData.power_on_time.hours}小时`;
                    if (jsonData.power_cycle_count) {
                       output += `, 次数: ${jsonData.power_cycle_count}`;
                       }
                    }
                    if (jsonData.smart_status?.passed !== undefined) {
                       if (output.length > 0) output += ' | ';
                       output += 'SMART: ' + (jsonData.smart_status.passed ? '正常' : '警告!');
                    }
                       return output;
                       }
                       } catch (e) {
                    }
                    let outputs = [];
                    let devices = value.matchAll(/(\s*(Model|Device Model|Vendor).*:\s*[\s\S]*?\n){1,2}^User.*\[([\s\S]*?)\]\n^\s*9[\s\S]*?\-\s*([\d]+)[\s\S]*?(\n(^19[0,4][\s\S]*?$){1,2}|\s{0}$)/gm);
                    for (const device of devices) {
                    let devicemodel = '';
                    if (device[1].indexOf("Family") !== -1) {
                       devicemodel = device[1].replace(/.*Model Family:\s*([\s\S]*?)\n^Device Model:\s*([\s\S]*?)\n/m, '$1 - $2');
                    } else if (device[1].match(/Vendor/)) {
                       devicemodel = device[1].replace(/.*Vendor:\s*([\s\S]*?)\n^.*Model:\s*([\s\S]*?)\n/m, '$1 $2');
                    } else {
                       devicemodel = device[1].replace(/.*(Model|Device Model):\s*([\s\S]*?)\n/m, '$2');
                    }
                    let capacity = device[3] ? device[3].replace(/ |,/gm, '') : "未知容量";
                    let powerOnHours = device[4] || "未知";
                    let deviceOutput = '';
                    if (value.indexOf("Min/Max") !== -1) {
                       let devicetemps = device[6]?.matchAll(/19[0,4][\s\S]*?\-\s*(\d+)(\s\(Min\/Max\s(\d+)\/(\d+)\)$|\s{0}$)/gm);
                       for (const devicetemp of devicetemps || []) {
                         deviceOutput = `<strong>${devicemodel}</strong><br>容量: ${capacity} | 已通电: ${powerOnHours}小时 | 温度: <strong>${devicetemp[1]}°C</strong>`;
                         outputs.push(deviceOutput);
                      }
                    } else if (value.indexOf("Temperature") !== -1 || value.match(/Airflow_Temperature/)) {
                       let devicetemps = device[6]?.matchAll(/19[0,4][\s\S]*?\-\s*(\d+)/gm);
                    for (const devicetemp of devicetemps || []) {
                       deviceOutput = `<strong>${devicemodel}</strong><br>容量: ${capacity} | 已通电: ${powerOnHours}小时 | 温度: <strong>${devicetemp[1]}°C</strong>`;
                       outputs.push(deviceOutput);
                    }
                    } else {
                       if (value.match(/\/dev\/sd[a-z]/)) {
                           deviceOutput = `<strong>${devicemodel}</strong><br>容量: ${capacity} | 已通电: ${powerOnHours}小时 | 提示: 设备存在但未报告温度信息`;
                           outputs.push(deviceOutput);
                       } else {
                           deviceOutput = `<strong>${devicemodel}</strong><br>容量: ${capacity} | 已通电: ${powerOnHours}小时 | 提示: 未检测到温度传感器`;
                           outputs.push(deviceOutput);
                       }
                      }
                    }
                    if (!outputs.length && value.length > 0) {
                       let fallbackDevices = value.matchAll(/(\/dev\/sd[a-z]).*?Model:([\s\S]*?)\n/gm);
                       for (const fallbackDevice of fallbackDevices || []) {
                         outputs.push(`${fallbackDevice[2].trim()}<br>提示: 设备存在但无法获取完整信息`);
                       }
                    }
                    return outputs.length ? outputs.join('<br>') : '提示: 检测到硬盘但无法识别详细信息';
            } else {
                return '提示: 未安装硬盘或已直通硬盘控制器';
        }
    }
},
EOF

    log_info "找到关键字pveversion的行号"
    # 显示匹配的行
    ln=$(sed -n '/pveversion/,+10{/},/{=;q}}' $pvemanagerlib)
    log_info "匹配的行号pveversion： $ln"

    log_info "修改结果："
    sed -i "${ln}r $tmpf" $pvemanagerlib
    # 显示修改结果
    # sed -n '/pveversion/,+30p' $pvemanagerlib
    rm $tmpf

    log_info "开始配置温度监控显示高度"
    disk_count=$(lsblk -d -o NAME | grep -cE 'sd[a-z]|nvme[0-9]')
    
    # 提示用户配置高度相关信息
    echo -e "${YELLOW}温度监控高度配置说明：${NC}"
    echo -e "${CYAN}检测到系统中有 $disk_count 个磁盘设备${NC}"
    echo -e "${GREEN}默认高度增量为每个磁盘69像素，如CPU核心过多导致高度不够可调整此值${NC}"
    echo -e "${CYAN}当前设置：每个磁盘增加69像素高度${NC}"
    echo
    
    # 用户可以选择自定义高度增量，或使用默认值
    read -p "请输入每个磁盘的高度增量 (默认: 69, 直接回车使用默认值): " user_height_input
    height_per_disk=${user_height_input:-69}
    
    # 验证输入是否为有效数字
    if ! [[ "$height_per_disk" =~ ^[0-9]+$ ]]; then
        log_warn "输入的高度增量无效，使用默认值69"
        height_per_disk=69
    fi
    
    height_increase=$((disk_count * height_per_disk))

    node_status_new_height=$((400 + height_increase))
    sed -i -r '/widget\\.pveNodeStatus/,+5{/height/{s#[0-9]+#'$node_status_new_height'#}}' $pvemanagerlib
    cpu_status_new_height=$((300 + height_increase))
    sed -i -r '/widget\\.pveCpuStatus/,+5{/height/{s#[0-9]+#'$cpu_status_new_height'#}}' $pvemanagerlib

    log_info "配置后的高度值："
    sed -n -e '/widget\.pveNodeStatus/,+5{/height/{p}}' \
           -e '/widget\.pveCpuStatus/,+5{/height/{p}}' $pvemanagerlib
    # 添加滚动功能 - 为各种温度监控组件添加垂直滚动
    sed -i '/widget\.pveNodeStatus/,+10{s/height:[[:space:]]*[0-9]{1,}[[:space:]]*;/height: '$node_status_new_height'px; overflow-y: auto; padding-right: 8px;/}' $pvemanagerlib
    sed -i '/widget\.pveCpuStatus/,+10{s/height:[[:space:]]*[0-9]{1,}[[:space:]]*;/height: '$cpu_status_new_height'px; overflow-y: auto; padding-right: 8px;/}' $pvemanagerlib
    
    log_info "高度配置完成："
    echo -e "${GREEN}节点状态组件高度: ${node_status_new_height}px${NC}"
    echo -e "${GREEN}CPU状态组件高度: ${cpu_status_new_height}px${NC}"
    echo -e "${YELLOW}每个磁盘增加高度: ${height_per_disk}px${NC}"
    echo -e "${CYAN}磁盘数量: ${disk_count}${NC}"

    # 调整显示布局
    ln=$(expr $(sed -n -e '/widget.pveDcGuests/=' $pvemanagerlib) + 10)
    sed -i "${ln}a\ textAlign: 'right'," $pvemanagerlib
    ln=$(expr $(sed -n -e '/widget.pveNodeStatus/=' $pvemanagerlib) + 10)
    sed -i "${ln}a\ textAlign: 'right'," $pvemanagerlib

    ###################  修改proxmoxlib.js   ##########################

    log_info "修改去除订阅弹窗"
    sed -r -i '/\/nodes\/localhost\/subscription/,+10{/^\s+if \(res === null /{N;s#.+#\t\t  if(false){#}}' $proxmoxlib
    # 显示修改结果
    sed -n '/\/nodes\/localhost\/subscription/,+10p' $proxmoxlib

    systemctl restart pveproxy
    log_success "请刷新浏览器缓存shift+f5"
}

# 删除工具
cpu_del() {
    nodes="/usr/share/perl5/PVE/API2/Nodes.pm"
    pvemanagerlib="/usr/share/pve-manager/js/pvemanagerlib.js"
    proxmoxlib="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"

    pvever=$(pveversion | awk -F"/" '{print $2}')
    echo pve版本$pvever
    if [ -f "$nodes.$pvever.bak" ];then
        rm -f $nodes $pvemanagerlib $proxmoxlib
        mv $nodes.$pvever.bak $nodes
        mv $pvemanagerlib.$pvever.bak $pvemanagerlib
        mv $proxmoxlib.$pvever.bak $proxmoxlib

        log_success "已删除温度显示，请重新刷新浏览器缓存."
    else
        log_warn "你没有添加过温度显示，退出脚本."
    fi
}
#--------------CPU、主板、硬盘温度显示----------------

#---------PVE8/9添加ceph-squid源-----------
pve9_ceph() {
    sver=`cat /etc/debian_version |awk -F"." '{print $1}'`
    case "$sver" in
     13 )
         sver="trixie"
     ;;
     12 )
         sver="bookworm"
     ;;
    * )
        sver=""
     ;;
    esac
    if [ ! $sver ];then
        log_error "版本不支持！"
        pause_function
        return
    fi

    log_info "ceph-squid目前仅支持PVE8和9！"
    [[ ! -d /etc/apt/backup ]] && mkdir -p /etc/apt/backup
    [[ ! -d /etc/apt/sources.list.d ]] && mkdir -p /etc/apt/sources.list.d

    [[ -e /etc/apt/sources.list.d/ceph.sources ]] && mv /etc/apt/sources.list.d/ceph.sources /etc/apt/backup/ceph.sources.bak
    [[ -e /etc/apt/sources.list.d/ceph.list ]] && mv /etc/apt/sources.list.d/ceph.list /etc/apt/backup/ceph.list.bak

    [[ -e /usr/share/perl5/PVE/CLI/pveceph.pm ]] && cp -rf /usr/share/perl5/PVE/CLI/pveceph.pm /etc/apt/backup/pveceph.pm.bak
    sed -i 's|http://download.proxmox.com|https://mirrors.tuna.tsinghua.edu.cn/proxmox|g' /usr/share/perl5/PVE/CLI/pveceph.pm

    cat > /etc/apt/sources.list.d/ceph.list <<-EOF
deb https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/ceph-squid ${sver} no-subscription
EOF
    log_success "添加ceph-squid源完成!"
}
#---------PVE8/9添加ceph-squid源-----------

#---------PVE7/8添加ceph-quincy源-----------
pve8_ceph() {
    sver=`cat /etc/debian_version |awk -F"." '{print $1}'`
    case "$sver" in
     12 )
         sver="bookworm"
     ;;
     11 )
         sver="bullseye"
     ;;
    * )
        sver=""
     ;;
    esac
    if [ ! $sver ];then
        log_error "版本不支持！"
        pause_function
        return
    fi

    log_info "ceph-quincy目前仅支持PVE7和8！"
    [[ ! -d /etc/apt/backup ]] && mkdir -p /etc/apt/backup
    [[ ! -d /etc/apt/sources.list.d ]] && mkdir -p /etc/apt/sources.list.d

    [[ -e /etc/apt/sources.list.d/ceph.sources ]] && mv /etc/apt/sources.list.d/ceph.sources /etc/apt/backup/ceph.sources.bak
    [[ -e /etc/apt/sources.list.d/ceph.list ]] && mv /etc/apt/sources.list.d/ceph.list /etc/apt/backup/ceph.list.bak

    [[ -e /usr/share/perl5/PVE/CLI/pveceph.pm ]] && cp -rf /usr/share/perl5/PVE/CLI/pveceph.pm /etc/apt/backup/pveceph.pm.bak
    sed -i 's|http://download.proxmox.com|https://mirrors.tuna.tsinghua.edu.cn/proxmox|g' /usr/share/perl5/PVE/CLI/pveceph.pm

    cat > /etc/apt/sources.list.d/ceph.list <<-EOF
deb https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/ceph-quincy ${sver} main
EOF
    log_success "添加ceph-quincy源完成!"
}
#---------PVE7/8添加ceph-quincy源-----------
# 待办
#---------PVE7/8添加ceph-quincy源-----------
#---------PVE一键卸载ceph-----------
remove_ceph() {
    log_warn "会卸载ceph，并删除所有ceph相关文件！"

    systemctl stop ceph-mon.target && systemctl stop ceph-mgr.target && systemctl stop ceph-mds.target && systemctl stop ceph-osd.target
    rm -rf /etc/systemd/system/ceph*

    killall -9 ceph-mon ceph-mgr ceph-mds ceph-osd
    rm -rf /var/lib/ceph/mon/* && rm -rf /var/lib/ceph/mgr/* && rm -rf /var/lib/ceph/mds/* && rm -rf /var/lib/ceph/osd/*

    pveceph purge

    apt purge -y ceph-mon ceph-osd ceph-mgr ceph-mds
    apt purge -y ceph-base ceph-mgr-modules-core

    rm -rf /etc/ceph && rm -rf /etc/pve/ceph.conf  && rm -rf /etc/pve/priv/ceph.* && rm -rf /var/log/ceph && rm -rf /etc/pve/ceph && rm -rf /var/lib/ceph

    [[ -e /etc/apt/sources.list.d/ceph.sources ]] && mv /etc/apt/sources.list.d/ceph.sources /etc/apt/backup/ceph.sources.bak

    log_success "已成功卸载ceph."
}
#---------PVE一键卸载ceph-----------

# PVE8 to PVE9 升级功能
pve8_to_pve9_upgrade() {
    log_step "开始 PVE 8.x 升级到 PVE 9.x"
    
    # 检查当前 PVE 版本
    local current_pve_version=$(pveversion | head -n1 | cut -d'/' -f2 | cut -d'-' -f1)
    local major_version=$(echo $current_pve_version | cut -d'.' -f1)
    
    if [[ "$major_version" != "8" ]]; then
        log_error "当前 PVE 版本为 $current_pve_version，不是 PVE 8.x 版本，无法执行此升级"
        log_info "PVE7 请先试用ISO或升级教程升级哦! ：https://pve.proxmox.com/wiki/Upgrade_from_7_to_8"
        log_tips "如果你已经是PVE 9.x了，你还来用这个脚本，敲你额头！"
        return 1
    fi
    
    log_info "检测到当前 PVE 版本: ${GREEN}$current_pve_version${NC}"
    log_warn "即将开始 PVE 8.x 到 PVE 9.x 的升级流程"
    log_warn "此过程不可逆，请确保已备份重要数据！"
    log_warn "建议在升级前阅读官方升级指南：https://pve.proxmox.com/wiki/Upgrade_from_8.x_to_9.0"
    echo -e ""
    log_warn "升级过程中请勿中断，确保有稳定的网络连接"
    log_warn "升级完成后，系统将自动重启以应用更改"
    log_warn "如果脚本出现升级问题，请及时联系作者或参照官方文档解决。"
    echo -e ""
    log_info "推荐使用我的新项目嘿嘿，一个独立的升级AGENT: https://github.com/Mapleawaa/PVE-8-Upgrage-helper"
    
    # 确认用户要继续执行升级
    echo -e "${YELLOW}您确定要继续升级吗？本次任务执行以下操作：${NC}"
    echo -e "  1. 安装 pve8to9 检查工具"
    echo -e "  2. 运行升级前检查"
    echo -e "  3. 更新软件源到 Debian 13 (Trixie)"
    echo -e "  4. 执行系统升级"
    echo -e "  5. 重启系统以应用更改"
    echo -e ""
    echo -e "${RED}注意：升级过程中可能会遇到一些警告或错误，请根据提示进行处理！脚本无法处理故障提示！(脚本只能把提示扔给你..) )${NC}"
    read -p "输入 'yesido' 确认继续，其他任意键取消: " confirm
    if [[ "$confirm" != "yesido" ]]; then
        log_info "已取消升级操作"
        return 0
    fi
    
    # 1. 更新当前系统到最新 PVE 8.x 版本
    log_info "更新当前系统到最新 PVE 8.x 版本..."
    if ! apt update && apt dist-upgrade -y; then
        log_error "更新 PVE 8.x 到最新版本失败了，请检查网络连接或源配置，或者前往作者的GitHub反馈issue.."
        return 1
    fi
    
    # 再次检查当前版本
    current_pve_version=$(pveversion | head -n1 | cut -d'/' -f2 | cut -d'-' -f1)
    log_info "更新后 PVE 版本: ${GREEN}$current_pve_version${NC}"
    
    # 2. 安装和运行 pve8to9 检查工具
    log_info "安装 pve8to9 升级检查工具..."
    if ! apt install -y pve8to9; then
        log_warn "pve8to9 工具安装失败，尝试手动安装..."
        # 尝试手动添加 PVE 8 仓库安装 pve8to9
        if ! apt install -y pve8to9; then
            log_error "无法安装 pve8to9 检查工具,奇怪！请检查网络连接或源配置，或者前往作者的GitHub反馈issue.."
            return 1
        fi
    fi
    
    log_info "运行升级前检查..."
    echo -e "${CYAN}pve8to9 检查结果：${NC}"
    # 运行 pve8to9 检查，但不直接退出，而是捕获输出并分析
    echo -e "检查结果会保存到 /tmp/pve8to9_check.log 文件中，如出现故障建议查看该文件以获取详细信息"
    echo -e "再次提示，脚本只能做到把错误扔给你，无法修复问题，请根据提示自行解决(或前往作者issue反馈问题)..."
    local check_result=$(pve8to9 | tee /tmp/pve8to9_check.log)
    echo "$check_result"
    
    # 检查是否有 FAIL 标记（这意味着有严重错误需要修复）
    if echo "$check_result" | grep -E -i "FAIL" > /dev/null; then
        log_error "pve8to9 检查发现严重错误!! 一般是软件包冲突或是其他报错!建议修复后再进行升级！"
        echo -e "${YELLOW}升级检查结果详情：${NC}"
        cat /tmp/pve8to9_check.log
        read -p "您确定要忽略这些错误并继续升级吗？这不是在开玩笑！(y/N): " force_upgrade
        if [[ "$force_upgrade" != "y" && "$force_upgrade" != "Y" ]]; then
            log_info "由于存在严重错误，已取消升级操作...返回主界面"
            return 1
        fi
    else
        log_success "pve8to9 检查通过，没有发现严重错误，太好了！"
        
        # 检查是否有 WARNING 标记
        if echo "$check_result" | grep -E -i "WARN" > /dev/null; then
            log_warn "pve8to9 检查发现一些警告信息，请查看以上详情并根据需要处理。(有些可能是软件包没升级上去，不是关键软件包可以无视先升级喔)"
            read -p "是否继续升级？(Y/n): " continue_check
            if [[ "$continue_check" == "n" || "$continue_check" == "N" ]]; then
                log_info "已取消升级操作"
                return 0
            fi
        fi
    fi
    
    # 3. 安装 CPU 微码（如果提示需要）
    log_info "检查是否需要安装 CPU 微码..."
    if command -v lscpu &> /dev/null; then
        local cpu_vendor=$(lscpu | grep "Vendor ID" | awk '{print $3}')
        if [[ "$cpu_vendor" == "GenuineIntel" ]]; then
            log_info "检测到 Intel CPU，安装 Intel 微码..."
            apt install -y intel-microcode
        elif [[ "$cpu_vendor" == "AuthenticAMD" ]]; then
            log_info "检测到 AMD CPU，安装 AMD 微码..."
            apt install -y amd64-microcode
        fi
    fi
    
    # 4. 检查当前启动方式并更新引导配置
    log_info "检查系统启动方式..."
    local boot_method="unknown"
    if [[ -d "/boot/efi" ]]; then
        boot_method="efi"
        log_info "检测到 EFI 启动模式"
        # 为 EFI 系统配置 GRUB
        echo 'grub-efi-amd64 grub2/force_efi_extra_removable boolean true' | debconf-set-selections -v -u
    else
        boot_method="bios"
        log_info "检测到 BIOS 启动模式"
        log_tips "怎么还在用BIOS启用呀？建议升级到UEFI启动方式，提升系统兼容性和安全性"
    fi
    
    # 5. 备份当前源文件
    log_info "备份当前源文件..."
    local backup_dir="/etc/pve-tools-9-bak"
    mkdir -p "$backup_dir"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    # 备份各种源文件
    if [[ -f "/etc/apt/sources.list" ]]; then
        cp /etc/apt/sources.list "${backup_dir}/sources.list.backup.${timestamp}"
    fi
    
    if [[ -f "/etc/apt/sources.list.d/pve-enterprise.list" ]]; then
        cp /etc/apt/sources.list.d/pve-enterprise.list "${backup_dir}/pve-enterprise.list.backup.${timestamp}"
    fi
    
    # 6. 更新源到 Debian 13 (Trixie) 并添加 PVE 9.x 源
    log_info "更新软件源到 Debian 13 (Trixie)..."
    
    # 将所有 bookworm 源替换为 trixie
    log_step "替换 sources.list 和 pve-enterprise.list 中的 bookworm 为 trixie"
    sed -i 's/bookworm/trixie/g' /etc/apt/sources.list 2>/dev/null || true
    sed -i 's/bookworm/trixie/g' /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null || true
    
    # 创建 PVE 9.x 的 sources 配置文件
    log_step "创建 PVE 9.x 的 sources 配置文件..."
    cat > /etc/apt/sources.list.d/proxmox.sources << EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    
    # 创建 Ceph Squid 源配置文件
    log_step "创建 Ceph Squid 源配置文件..."
    cat > /etc/apt/sources.list.d/ceph.sources << EOF
Types: deb
URIs: http://download.proxmox.com/debian/ceph-squid
Suites: trixie
Components: no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    
    log_info "软件源已更新到 Debian 13 (Trixie) 和 PVE 9.x 配置"
    
    # 7. 再次运行升级前检查确认源更新无误
    log_info "再次运行 pve8to9 检查以确认源配置..."
    local final_check_result=$(pve8to9)
    if echo "$final_check_result" | grep -E -i "FAIL" > /dev/null; then
        log_error "pve8to9 最终检查发现错误，请手动检查源配置后再继续"
        echo "$final_check_result"
        return 1
    else
        log_success "源更新配置检查通过"
    fi
    
    # 8. 更新包列表并开始升级
    log_info "更新包列表..."
    if ! apt update; then
        log_error "更新包列表失败，请检查网络连接和源配置"
        return 1
    fi
    
    log_info "开始 PVE 9.x 升级过程，这可能需要较长时间..."
    log_warn "如果你正在使用Web UI内置的终端，建议改用SSH连接以防止连接中断"
    echo -e "${YELLOW}升级过程中可能会出现多个提示，通常按回车键或选择默认选项即可${NC}"
    
    # 使用非交互模式升级，自动回答问题
    DEBIAN_FRONTEND=noninteractive apt dist-upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
    
    if [[ $? -ne 0 ]]; then
        log_error "PVE 升级过程失败，请查看日志并手动处理...如果是在看不明白可以试试问AI或者提交issue"
        return 1
    fi
    
    # 9. 清理无用包
    log_info "清理无用软件包..."
    apt autoremove -y
    apt autoclean
    
    # 10. 检查升级结果
    local new_pve_version=$(pveversion | head -n1 | cut -d'/' -f2 | cut -d'-' -f1)
    local new_major_version=$(echo $new_pve_version | cut -d'.' -f1)
    
    if [[ "$new_major_version" == "9" ]]; then
        log_success "（撒花）PVE 升级成功！新的 PVE 版本: ${GREEN}$new_pve_version${NC}"
        
        # 运行最终的升级后检查
        log_info "运行升级后检查..."
        pve8to9 2>/dev/null || true
        
        log_info "系统将在 30 秒后重启以完成升级..."
        log_success "如果一切顺利，重启后就能体验到PVE9啦！"
        log_warn "如果升级后出现问题，例如卡内核卡Grub，请先使用LiveCD抢修内核，提取日志文件后联系作者寻求帮助"
        echo -e "${YELLOW}按 Ctrl+C 可取消自动重启${NC}"
        sleep 30
        
        # 重启系统以完成升级
        log_info "正在重启系统以完成 PVE 9.x 升级..."
        reboot
    else
        log_error "升级完成后检查发现，PVE 版本仍为 $new_pve_version，升级可能未完全成功"
        log_tips "请手动检查系统状态，并确认是否需要重试升级"
        return 1
    fi
}

# 显示系统信息
show_system_info() {
    log_step "为您展示系统运行状况"
    echo
    echo -e "${UI_BORDER}"
    echo -e "${CYAN}│${NC} ${YELLOW}系统信息概览${NC} ${CYAN}                                  │${NC}"
    echo -e "${UI_DIVIDER}"
    echo -e "PVE 版本: ${GREEN}$(pveversion | head -n1)${NC}"
    echo -e "内核版本: ${GREEN}$(uname -r)${NC}"
    echo -e "CPU 信息: ${GREEN}$(lscpu | grep 'Model name' | sed 's/Model name:[ \t]*//')${NC}"
    echo -e "CPU 核心: ${GREEN}$(nproc) 核心${NC}"
    echo -e "系统架构: ${GREEN}$(dpkg --print-architecture)${NC}"
    echo -e "系统启动: ${GREEN}$(uptime -p | sed 's/up //')${NC}"
    echo -e "引导类型: ${GREEN}$(if [ -d /sys/firmware/efi ]; then echo UEFI; else echo BIOS; fi)${NC}"
    echo -e "系统负载: ${GREEN}$(uptime | awk -F'load average:' '{print $2}')${NC}"
    echo -e "内存使用: ${GREEN}$(free -h | grep Mem | awk '{print $3"/"$2}')${NC}"
    echo -e "磁盘使用:"
    df -h | grep -E '^/dev/' | awk '{print "  "$1" "$3"/"$2" ("$5")"}'
    echo -e "网络接口:"
    ip -br addr show | awk '{print "  "$1" "$3}'
    echo -e "当前时间: ${GREEN}$(date)${NC}"
    echo -e "${UI_FOOTER}"
}

# 主菜单
show_menu() {
    show_menu_header "请选择您需要的功能："
    
    # Using the enhanced aligned menu function for better visual consistency
    create_aligned_menu \
        "1"  "更换软件源 ${GREEN}(强烈推荐，让下载飞起来)${NC}" \
        "2"  "删除订阅弹窗 ${GREEN}(告别烦人提醒)${NC} | ${RED}（谨慎操作）并且只能在SSH环境下使用否则会被截断${NC}" \
        "3"  "合并 local 与 local-lvm ${CYAN}(小硬盘救星)${NC}" \
        "4"  "删除 Swap 分区 ${CYAN}(释放更多空间)${NC}" \
        "5"  "更新系统 ${GREEN}(保持最新状态)${NC}" \
        "6"  "显示系统信息 ${BLUE}(查看运行状况)${NC}" \
        "7"  "一键配置 ${MAGENTA}(换源+删弹窗+更新，懒人必选，推荐在SSH下使用)${NC}" \
        "8"  "硬件直通配置 ${BLUE}(PCI设备直通设置)${NC}" \
        "9"  "CPU电源模式 ${BLUE}(调整CPU性能模式)${NC}" \
        "10" "温度监控设置 ${BLUE}(CPU/硬盘温度显示)${NC}" \
        "11" "温度监控移除 ${BLUE}(移除温度监控功能)${NC}" \
        "12" "添加ceph-squid源 ${BLUE}(PVE8/9专用)${NC}" \
        "13" "添加ceph-quincy源 ${BLUE}(PVE7/8专用)${NC}" \
        "14" "卸载Ceph ${BLUE}(完全移除Ceph)${NC}" \
        "15" "内核管理 ${MAGENTA}(内核切换/更新/清理)${NC}" \
        "16" "PVE8 升级到 PVE9 ${RED}(PVE8专用)${NC}" \
        "0"  "退出脚本" \
        "520" "给作者点个Star吧，谢谢喵~ ${NC}"
    
    show_menu_footer
    echo
    echo -e "${CYAN}小贴士：新装系统推荐选择 7 进行一键配置${NC}"
    echo -n -e "${GREEN}请输入您的选择 [0-16, 520]: ${NC}"
}

# 一键配置
quick_setup() {
    log_step "开始一键配置"
    log_step "天涯若比邻，海内存知己，坐和放宽，让我来搞定一切。"
    echo
    change_sources
    echo
    remove_subscription_popup
    echo
    update_system
    echo
    log_success "一键配置全部完成！您的 PVE 已经完美优化"
    echo -e "${CYAN}现在您可以愉快地使用 PVE 了！${NC}"
}

# 通用UI函数
show_menu_header() {
    local title="$1"
    echo -e "${UI_BORDER}"
    local border_length=50  # Fixed length of the border
    local content_length=$(echo -n "$title" | wc -c)
    local padding_length=$((border_length - 4 - content_length))  # 4 accounts for │ and NC tags
    printf "${CYAN}│${NC} %s%*s ${CYAN}│${NC}\n" "$title" $padding_length ""
    echo -e "${UI_DIVIDER}"
}

show_menu_footer() {
    echo -e "${UI_FOOTER}"
}

show_menu_option() {
    local num="$1"
    local desc="$2"
    local color="${3:-$GREEN}" # Default to green if no color specified
    printf "  ${color}%-3s${NC}. %s\n" "$num" "$desc"
}

# Enhanced function to create aligned menu options
create_aligned_menu() {
    local max_num_length=0
    local max_desc_length=0
    local temp_nums=()
    local temp_descs=()
    local temp_colors=()
    
    # Read all parameters into arrays
    local i=0
    while [[ $# -gt 0 ]]; do
        temp_nums[i]="$1"
        shift
        temp_descs[i]="$1"
        shift
        temp_colors[i]="${1:-$GREEN}"
        shift
        ((i++))
    done
    
    # Find max lengths for alignment
    for num in "${temp_nums[@]}"; do
        if [[ ${#num} -gt $max_num_length ]]; then
            max_num_length=${#num}
        fi
    done
    
    # Create aligned menu
    for ((j=0; j<${#temp_nums[@]}; j++)); do
        printf "  ${temp_colors[j]}%-${max_num_length}s${NC}. %s\n" "${temp_nums[j]}" "${temp_descs[j]}"
    done
}

# 镜像源选择函数
select_mirror() {
    while true; do
        clear
        show_banner
        show_menu_header "请选择镜像源"
        create_aligned_menu \
            "1" "中科大镜像源" \
            "2" "清华Tuna镜像源" \
            "3" "Debian默认源 ${YELLOW}非必要请勿使用本源${NC}"
        echo -e "${UI_DIVIDER}"
        echo -e "${YELLOW}注意：选择后将作为后续所有软件源操作的基础${NC}"
        show_menu_footer
        echo
        
        read -p "请选择 [1-3]: " mirror_choice
        
        case $mirror_choice in
            1)
                SELECTED_MIRROR=$MIRROR_USTC
                log_success "已选择中科大镜像源"
                break
                ;;
            2)
                SELECTED_MIRROR=$MIRROR_TUNA
                log_success "已选择清华Tuna镜像源"
                break
                ;;
            3)
                SELECTED_MIRROR=$MIRROR_DEBIAN
                log_success "已选择Debian默认源"
                break
                ;;
            *)
                log_error "无效选择，请重新输入"
                pause_function
                ;;
        esac
    done
}

# 版本检查函数
check_update() {
    log_info "正在检查更新..."
    
    # 下载版本文件的函数（带超时）
    download_version_file() {
        local url="$1"
        local timeout=10
        
        if command -v curl &> /dev/null; then
            curl -s --connect-timeout $timeout --max-time $timeout "$url" 2>/dev/null
        elif command -v wget &> /dev/null; then
            wget -q -T $timeout -O - "$url" 2>/dev/null
        else
            echo ""
        fi
    }
    
    # 显示进度提示
    echo -ne "${CYAN}[....]${NC} 正在检查更新...\033[0K\r"
    
    # 首先尝试从GitHub下载版本文件
    remote_content=$(download_version_file "$VERSION_FILE_URL")
    
    # 如果GitHub下载失败，自动尝试镜像源
    if [ -z "$remote_content" ]; then
        echo -ne "${YELLOW}[WARN]${NC} GitHub连接失败，尝试镜像源...\033[0K\r"
        mirror_url="https://ghfast.top/Mapleawaa/PVE-Tools-9/main/VERSION"
        remote_content=$(download_version_file "$mirror_url")
    fi
    
    # 清除进度显示
    echo -ne "\033[0K\r"
    
    # 如果所有下载都失败
    if [ -z "$remote_content" ]; then
        log_warn "网络连接失败，跳过版本检查"
        echo -e "${YELLOW}提示：您可以手动访问以下地址检查更新：${NC}"
        echo -e "${BLUE}https://github.com/Mapleawaa/PVE-Tools-9${NC}"
        echo -e "${YELLOW}按回车键继续...${NC}"
        read -r
        return
    fi
    
    # 提取版本号和更新日志
    remote_version=$(echo "$remote_content" | head -1 | tr -d '[:space:]')
    changelog=$(echo "$remote_content" | tail -n +2)
    
    if [ -z "$remote_version" ]; then
        log_warn "获取的版本信息格式不正确"
        return
    fi
    
    # 比较版本
    if [ "$(printf '%s\n' "$remote_version" "$CURRENT_VERSION" | sort -V | tail -n1)" != "$CURRENT_VERSION" ]; then
        echo -e "${YELLOW}----------------------------------------------${NC}"
        echo -e "${GREEN}发现新版本！推荐更新哦，新增功能和修复BUG喵${NC}"
        echo -e "当前版本: ${YELLOW}$CURRENT_VERSION${NC}"
        echo -e "最新版本: ${GREEN}$remote_version${NC}"
        echo -e "${YELLOW}更新内容：${NC}"
        echo -e "$changelog"
        echo -e "${YELLOW}----------------------------------------------${NC}"
        echo -e "${MAGENTA}请访问项目页面获取最新版本：${NC}"
        echo -e "${BLUE}https://github.com/Mapleawaa/PVE-Tools-9${NC}"
        echo -e "${YELLOW}按回车键继续...${NC}"
        read -r
    else
        log_success "当前已是最新版本 ($CURRENT_VERSION) 放心用吧"
    fi
}

# 主程序
main() {
    check_root
    check_debug_mode "$@"
    check_pve_version
    
    # 检查更新
    check_update
    
    # 选择镜像源
    select_mirror
    
    while true; do
        show_banner
        show_menu
        choice=$(get_menu_choice "${GREEN}请输入您的选择 [0-16, 520]: ${NC}" "0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 520" "0")
        echo
        echo
        
        case $choice in
            1)
                change_sources
                ;;
            2)
                remove_subscription_popup
                ;;
            3)
                merge_local_storage
                ;;
            4)
                remove_swap
                ;;
            5)
                update_system
                ;;
            6)
                show_system_info
                ;;
            7)
                quick_setup
                ;;
            8)
                hw_passth
                ;;
            9)
                cpupower
                ;;
            10)
                cpu_add
                ;;
            11)
                cpu_del
                ;;
            12)
                pve9_ceph
                ;;
            13)
                pve8_ceph
                ;;
            14)
                remove_ceph
                ;;
            15)
                kernel_management_menu
                ;;
            16)
                pve8_to_pve9_upgrade
                ;;
            520)
                echo -e "${BLUE}项目地址：https://github.com/Mapleawaa/PVE-Tools-9${NC}"
                echo -e "${MAGENTA}有你真好~"
                ;;
            0)
                echo -e "${GREEN}感谢使用,谢谢喵${NC}"
                echo -e "${CYAN}再见！${NC}"
                exit 0
                ;;
            *)
                log_error "哎呀，这个选项不存在呢"
                log_warn "请输入 0-16 之间的数字"
                ;;
        esac
        
        echo
        pause_function
    done
}

# 运行主程序
main "$@"
