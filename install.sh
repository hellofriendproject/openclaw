#!/bin/bash
set -euo pipefail

# 🦞 OpenClaw Installer cho Linux Ubuntu (Tự động 100% từ fork repo)
# Code sẽ được clone vào thư mục nơi bạn chạy lệnh (ví dụ: `$(pwd)/openclaw`);
# người dùng có thể mở, sửa nguồn hoặc cấu hình trực tiếp.
# Kéo lệnh & chạy:
#   curl -fsSL https://raw.githubusercontent.com/hellofriendproject/openclaw/refs/heads/main/install.sh | bash

# Mã màu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Cấu hình
REPO_URL="https://github.com/hellofriendproject/openclaw.git"
# cài vào thư mục hiện tại (mặc định); người dùng có thể ghi đè
# bằng biến môi trường OPENCLAW_INSTALL_DIR
INSTALL_DIR="${OPENCLAW_INSTALL_DIR:-$PWD/openclaw}"
BIN_DIR="${HOME}/.local/bin"
GATEWAY_PORT=18789

# ============================================================================
# HÀM LOGGING
# ============================================================================

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*"
}

log_step() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}▶ $*${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# đảm bảo có quyền root hoặc sudo để thao tác hệ thống
if [[ $EUID -ne 0 ]] && ! command_exists sudo; then
    log_error "Script cần quyền root hoặc sudo."
    log_error "Hãy chạy lại với 'sudo' hoặc đăng nhập root trước khi gọi curl."
    exit 1
fi

# ============================================================================
# BƯỚC 1: ChuẨN BỊ MÔI TRƯỜNG
# ============================================================================

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO="${ID}"
    else
        log_error "Không thể phát hiện bản phân phối Linux"
        exit 1
    fi
}

install_dependencies() {
    log_step "BƯỚC 1: Chuẩn bị môi trường"
    
    detect_distro
    
    if [[ "$DISTRO" != "ubuntu" && "$DISTRO" != "debian" ]]; then
        log_warn "Script được tối ưu cho Ubuntu/Debian, bạn dùng: $DISTRO"
    fi
    
    local need_install=0
    
    if ! command_exists node; then
        log_info "Node.js chưa cài đặt"
        need_install=1
    fi
    
    if ! command_exists git; then
        log_info "Git chưa cài đặt"
        need_install=1
    fi
    
    if ! command_exists python3; then
        log_info "Python3 chưa cài đặt"
        need_install=1
    fi
    
    if [[ $need_install -eq 1 ]]; then
        # sudo đã được xác nhận ở đầu script, nên chúng ta có thể gọi trực tiếp
        log_info "Cập nhật package manager..."
        sudo apt-get update -qq 2>/dev/null || true
        
        log_info "Cài đặt build tools cơ bản..."
        sudo apt-get install -y -qq build-essential python3 git curl 2>/dev/null || true
        
        if ! command_exists node; then
            log_info "Thêm NodeSource repository cho Node.js 22..."
            curl -fsSL https://deb.nodesource.com/setup_22.x 2>/dev/null | sudo -E bash - 2>/dev/null || true
            log_info "Cài đặt Node.js..."
            sudo apt-get install -y -qq nodejs 2>/dev/null || true
        fi
    fi
    
    log_success "Môi trường sẵn sàng"
}

# ============================================================================
# BƯỚC 2: KIỂM TRA YÊU CẦU
# ============================================================================

check_requirements() {
    log_step "BƯỚC 2: Kiểm tra yêu cầu hệ thống"
    
    # Kiểm tra OS
    if ! [[ "$OSTYPE" == "linux-gnu"* ]]; then
        log_error "Script yêu cầu Linux (bạn có: $OSTYPE)"
        exit 1
    fi
    log_success "OS: Linux ✓"
    
    # Kiểm tra Node.js
    if ! command_exists node; then
        log_error "Node.js không được tìm thấy"
        exit 1
    fi
    local node_version=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [[ $node_version -lt 20 ]]; then
        log_error "Yêu cầu Node.js 20+ (bạn có: $(node -v))"
        exit 1
    fi
    log_success "Node.js $(node -v) ✓"
    
    # Kiểm tra npm
    if ! command_exists npm; then
        log_error "npm không được tìm thấy"
        exit 1
    fi
    log_success "npm $(npm -v) ✓"
    
    # Kiểm tra git
    if ! command_exists git; then
        log_error "Git không được tìm thấy"
        exit 1
    fi
    log_success "$(git --version) ✓"
    
    # Cài pnpm nếu chưa có
    if ! command_exists pnpm; then
        log_info "Cài đặt pnpm@10..."
        npm install -g pnpm@10 >/dev/null 2>&1
    fi
    log_success "pnpm $(pnpm --version) ✓"
}

# ============================================================================
# BƯỚC 3: TẢI XUỐNG MÃ NGUỒN
# ============================================================================

setup_directories() {
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BIN_DIR"
}

setup_repository() {
    log_step "BƯỚC 3: Tải xuống mã nguồn"
    
    # Xóa thư mục bị hỏng nếu có
    if [[ -d "$INSTALL_DIR" && ! -d "$INSTALL_DIR/.git" ]]; then
        log_warn "Thư mục bị hỏng, đang xóa..."
        rm -rf "$INSTALL_DIR" 2>/dev/null || true
    fi
    
    if [[ ! -d "$INSTALL_DIR" ]]; then
        log_info "Sao chép code từ fork: $REPO_URL"
        if ! git clone "$REPO_URL" "$INSTALL_DIR" 2>&1 | grep -E "Cloning|done" | tail -1; then
            log_error "Git clone thất bại - kiểm tra kết nối mạng hoặc URL"
            exit 1
        fi
    else
        log_info "Repository đã tồn tại, cập nhật..."
        cd "$INSTALL_DIR" || exit 1
        git fetch origin main 2>&1 | tail -1 || true
        git reset --hard origin/main >/dev/null 2>&1 || true
    fi
    
    log_success "Mã nguồn: $INSTALL_DIR"
}

# ============================================================================
# BƯỚC 4-6: BUILD (theo README)
# ============================================================================

install_project_deps() {
    log_step "BƯỚC 4: Cài đặt dependencies dự án"
    
    if [[ ! -f "$INSTALL_DIR/package.json" ]]; then
        log_error "Không tìm thấy package.json tại: $INSTALL_DIR"
        exit 1
    fi
    
    cd "$INSTALL_DIR" || exit 1
    
    log_info "Chạy: pnpm install --frozen-lockfile"
    if ! pnpm install --frozen-lockfile 2>&1 | tail -3; then
        log_error "pnpm install thất bại"
        exit 1
    fi
    
    log_success "Dependencies cài đặt xong"
}

build_ui() {
    log_step "BƯỚC 5: Xây dựng UI"
    
    cd "$INSTALL_DIR" || exit 1
    
    log_info "Chạy: pnpm ui:build (tự cài UI deps trên lần chạy đầu)"
    if pnpm ui:build 2>&1 | tail -3; then
        log_success "UI build thành công"
    else
        log_warn "UI build gặp lỗi nhưng tiếp tục (CLI vẫn hoạt động)"
    fi
}

build_project() {
    log_step "BƯỚC 6: Xây dựng OpenClaw"
    
    cd "$INSTALL_DIR" || exit 1
    
    if [[ ! -f "package.json" ]]; then
        log_error "Không tìm thấy package.json"
        exit 1
    fi
    
    log_info "Chạy: pnpm build"
    if ! pnpm build 2>&1 | tail -10; then
        log_error "pnpm build thất bại"
        exit 1
    fi
    
    if [[ ! -f "dist/entry.js" ]]; then
        log_error "Build thất bại - dist/entry.js không tìm thấy"
        exit 1
    fi
    
    log_success "Build hoàn tất"
}

# ============================================================================
# BƯỚC 7: TẠO WRAPPER
# ============================================================================

create_wrapper() {
    log_step "BƯỚC 7: Tạo openclaw command"
    
    cat > "$BIN_DIR/openclaw" <<'EOF'
#!/bin/bash
exec node "$(dirname "$0")/../share/openclaw/dist/entry.js" "$@"
EOF
    
    chmod +x "$BIN_DIR/openclaw"
    log_success "Wrapper tạo tại: $BIN_DIR/openclaw"
}

# ============================================================================
# BƯỚC 8: CẬP NHẬT PATH
# ============================================================================

update_path() {
    local bashrc="$HOME/.bashrc"
    local zshrc="$HOME/.zshrc"
    local export_line="export PATH=\"$BIN_DIR:\$PATH\""
    
    if [[ -f "$bashrc" ]]; then
        if ! grep -q "$BIN_DIR" "$bashrc"; then
            echo "" >> "$bashrc"
            echo "# OpenClaw - Added by installer" >> "$bashrc"
            echo "$export_line" >> "$bashrc"
        fi
    fi
    
    if [[ -f "$zshrc" ]]; then
        if ! grep -q "$BIN_DIR" "$zshrc"; then
            echo "" >> "$zshrc"
            echo "# OpenClaw - Added by installer" >> "$zshrc"
            echo "$export_line" >> "$zshrc"
        fi
    fi
    
    export PATH="$BIN_DIR:$PATH"
    log_success "PATH đã cập nhật"
}

# ============================================================================
# BƯỚC 9: TẠO ONBOARDING (Tự động setup daemon + gateway)
# ============================================================================

setup_onboarding() {
    log_step "BƯỚC 8: Setup anh-onboarding (daemon + gateway)"
    
    cd "$INSTALL_DIR" || exit 1
    
    log_info "Chạy: pnpm openclaw onboard --install-daemon"
    log_info "💡 Hướng dẫn: Làm theo các bước onboarding, xác nhận settings"
    log_info ""
    
    if pnpm openclaw onboard --install-daemon; then
        log_success "Onboarding hoàn tất"
        return 0
    else
        log_warn "Onboarding gặp lỗi nhưng OpenClaw vẫn được cài"
        # Lỗi phổ biến: wizard sẽ cố đặt plugins.slots.memory="memory-core"
        # dù plugin chưa được cài, dẫn tới "plugin not found" như bạn thấy.
        # Chúng ta xoá luôn cấu hình đó để tránh lỗi tái diễn.
        log_info "Đang dọn dẹp cấu hình cũ (plugins.slots.memory) nếu có..."
        openclaw config unset plugins.slots.memory >/dev/null 2>&1 || true
        log_warn "Nếu bạn cần tính năng memory, cài plugin tương ứng trước khi chạy lại onboarding."
        return 1
    fi
}

# ============================================================================
# BƯỚC 10: KHỞI ĐỘNG GATEWAY
# ============================================================================

# return 0 if user has configured gateway.mode (non‑empty), 1 otherwise
gateway_configured() {
    # avoid error output if config command fails
    local mode
    mode=$(openclaw config get gateway.mode 2>/dev/null || true)
    [[ -n "$mode" ]]
}

start_gateway() {
    log_step "BƯỚC 9: Khởi động Gateway"
    
    sleep 2
    
    log_info "Chạy: openclaw gateway --port $GATEWAY_PORT"
    log_info ""
    log_info "💡 Gateway đang chạy tại: http://127.0.0.1:$GATEWAY_PORT"
    log_info "   (Nếu từ remote, dùng SSH tunnel: ssh -N -L $GATEWAY_PORT:127.0.0.1:$GATEWAY_PORT user@host)"
    log_info ""
    
    openclaw gateway --port "$GATEWAY_PORT" --verbose || true
}

# ============================================================================
# MAIN FLOW
# ============================================================================

main() {
    clear

    echo -e "${GREEN}🦞 OpenClaw Installer — Ubuntu/Debian (tự động)${NC}"
    
    log_info "Repository: $REPO_URL"
    log_info "Cài đặt tại: $INSTALL_DIR"
    log_info "Wrapper: $BIN_DIR/openclaw"
    log_info ""
    
    # Kiểm tra OS
    if ! [[ "$OSTYPE" == "linux-gnu"* ]]; then
        log_error "Script yêu cầu Linux (bạn có: $OSTYPE)"
        exit 1
    fi
    
    # Chạy các bước
    install_dependencies
    check_requirements
    setup_directories
    setup_repository
    install_project_deps
    build_ui
    build_project
    create_wrapper
    update_path

    # Chạy onboarding (tương tác). KHÔNG tự động khởi động gateway.
    # Người dùng sẽ khởi động gateway thủ công sau khi xác nhận settings.
    if setup_onboarding; then
        log_success "Onboarding hoàn tất"
        echo ""
        echo -e "${GREEN}🎉 Onboarding xong.${NC} Khởi động gateway thủ công:"
        echo -e "  ${CYAN}pnpm openclaw gateway --port $GATEWAY_PORT${NC}  (hoặc ${CYAN}openclaw gateway --port $GATEWAY_PORT${NC})"
        echo ""
    else
        log_warn "Onboarding chưa hoàn tất; chạy lại khi sẵn sàng: ${CYAN}pnpm openclaw onboard --install-daemon${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}✓ Cài đặt hoàn tất!${NC}"
    echo ""
}

# Chạy main
main "$@" 
