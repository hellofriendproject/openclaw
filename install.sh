#!/bin/bash
set -euo pipefail

# Trình cài đặt OpenClaw cho Linux Ubuntu (Bản rút gọn)
# Cách sử dụng: curl -fsSL https://raw.githubusercontent.com/hellofriendproject/openclaw/refs/heads/main/install.sh | bash

# Mã màu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Cấu hình
REPO_URL="https://github.com/hellofriendproject/openclaw.git"
INSTALL_DIR="${HOME}/.local/share/openclaw"
BIN_DIR="${HOME}/.local/bin"
DOWNLOADER=""

# Các hàm logging
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

# Kiểm tra lệnh có tồn tại
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Phát hiện công cụ tải về
detect_downloader() {
    if command_exists curl; then
        DOWNLOADER="curl"
        return 0
    fi
    if command_exists wget; then
        DOWNLOADER="wget"
        return 0
    fi
    log_error "Cần curl hoặc wget"
    exit 1
}

# Tải tập tin
download_file() {
    local url="$1"
    local output="$2"
    if [[ -z "$DOWNLOADER" ]]; then
        detect_downloader
    fi
    if [[ "$DOWNLOADER" == "curl" ]]; then
        curl -fsSL --proto '=https' --tlsv1.2 --retry 3 "$url" -o "$output"
    else
        wget -q --https-only "$url" -O "$output"
    fi
}

# Phát hiện distro
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO="${ID}"
    else
        log_error "Không thể phát hiện bản phân phối Linux"
        exit 1
    fi
}

# Cài đặt dependencies cho Ubuntu/Debian
install_dependencies() {
    detect_distro
    
    if [[ "$DISTRO" != "ubuntu" && "$DISTRO" != "debian" ]]; then
        log_warn "Script này được tối ưu hóa cho Ubuntu/Debian"
    fi
    
    local need_install=0
    
    if ! command_exists node; then
        log_info "Đang cài đặt Node.js..."
        need_install=1
    fi
    
    if ! command_exists git; then
        log_info "Đang cài đặt git..."
        need_install=1
    fi
    
    if ! command_exists python3; then
        log_info "Đang cài đặt python3..."
        need_install=1
    fi
    
    if [[ $need_install -eq 1 ]]; then
        if command_exists sudo; then
            sudo apt-get update -qq 2>/dev/null || true
            sudo apt-get install -y -qq build-essential python3 git curl 2>/dev/null || true
            
            if ! command_exists node; then
                curl -fsSL https://deb.nodesource.com/setup_22.x 2>/dev/null | sudo -E bash - 2>/dev/null || true
                sudo apt-get install -y -qq nodejs 2>/dev/null || true
            fi
        else
            log_error "Vui lòng cài đặt Node.js, git, và build-essential"
            exit 1
        fi
    fi
}


# Kiểm tra yêu cầu
check_requirements() {
    log_info "Đang kiểm tra yêu cầu..."
    
    if ! command_exists node; then
        log_error "Node.js không được tìm thấy"
        exit 1
    fi
    
    if ! command_exists git; then
        log_error "Git không được tìm thấy"
        exit 1
    fi
    
    local node_version=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [[ $node_version -lt 20 ]]; then
        log_error "Yêu cầu Node.js 20+ (bạn có $(node -v))"
        exit 1
    fi
    
    log_success "Node.js $(node -v)"
    log_success "npm $(npm -v | head -1)"
    log_success "git $(git --version | head -1)"
}

# Thiết lập thư mục
setup_directories() {
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BIN_DIR"
}

# Clone hoặc cập nhật repository
setup_repository() {
    log_info "Thiết lập repository..."
    
    if [[ ! -d "$INSTALL_DIR" ]]; then
        log_info "Đang sao chép OpenClaw..."
        git clone "$REPO_URL" "$INSTALL_DIR" 2>&1 | tail -3 || true
    else
        log_info "Đang cập nhật OpenClaw..."
        cd "$INSTALL_DIR"
        git fetch origin main 2>&1 | tail -2 || true
        git reset --hard origin/main 2>&1 | tail -2 || true
    fi
    
    log_success "Repository sẵn sàng"
}

# Cài đặt dependencies dự án
install_project_deps() {
    log_info "Đang cài đặt dependencies dự án..."
    cd "$INSTALL_DIR"
    
    if [[ -f "pnpm-lock.yaml" ]]; then
        if ! command_exists pnpm; then
            log_info "Đang cài đặt pnpm..."
            npm install -g pnpm@10 >/dev/null 2>&1
        fi
        log_info "Đang chạy pnpm install..."
        pnpm install --frozen-lockfile 2>&1 | tail -5 || true
    else
        log_info "Đang chạy npm install..."
        npm install --omit=dev 2>&1 | tail -5 || true
    fi
    
    log_success "Dependencies đã được cài đặt"
}

# Xây dựng dự án
build_project() {
    log_info "Đang xây dựng OpenClaw..."
    cd "$INSTALL_DIR"
    
    if [[ -f "pnpm-lock.yaml" ]]; then
        pnpm build 2>&1 | tail -10 || true
    else
        npm run build 2>&1 | tail -10 || true
    fi
    
    if [[ ! -f "dist/entry.js" ]]; then
        log_error "Build thất bại - dist/entry.js không được tìm thấy"
        exit 1
    fi
    
    log_success "Build hoàn tất"
}

# Tạo binary wrapper
create_wrapper() {
    log_info "Đang tạo wrapper openclaw..."
    
    local username=$(whoami)
    cat > "$BIN_DIR/openclaw" <<EOF
#!/bin/bash
exec node "${INSTALL_DIR}/dist/entry.js" "\$@"
EOF
    
    chmod +x "$BIN_DIR/openclaw"
    log_success "Wrapper được tạo tại $BIN_DIR/openclaw"
}

# Kiểm tra cài đặt
test_installation() {
    log_info "Đang kiểm tra cài đặt..."
    
    export PATH="$BIN_DIR:$PATH"
    
    if "$BIN_DIR/openclaw" --version >/dev/null 2>&1; then
        local version=$("$BIN_DIR/openclaw" --version 2>/dev/null || echo "unknown")
        log_success "OpenClaw đã được cài đặt: $version"
    else
        log_warn "Không thể xác minh binary openclaw"
    fi
}

# Cập nhật PATH
update_path() {
    local bashrc="$HOME/.bashrc"
    local zshrc="$HOME/.zshrc"
    local export_line="export PATH=\"$BIN_DIR:\$PATH\""
    
    if [[ -f "$bashrc" ]]; then
        if ! grep -q "$BIN_DIR" "$bashrc"; then
            echo "" >> "$bashrc"
            echo "# OpenClaw" >> "$bashrc"
            echo "$export_line" >> "$bashrc"
        fi
    fi
    
    if [[ -f "$zshrc" ]]; then
        if ! grep -q "$BIN_DIR" "$zshrc"; then
            echo "" >> "$zshrc"
            echo "# OpenClaw" >> "$zshrc"
            echo "$export_line" >> "$zshrc"
        fi
    fi
}

# Luồng cài đặt chính
main() {
    clear
    
    log_info ""
    log_info "╔════════════════════════════════════╗"
    log_info "║   Trình cài đặt OpenClaw (Ubuntu)  ║"
    log_info "╚════════════════════════════════════╝"
    log_info ""
    
    log_info "Repository: $REPO_URL"
    log_info "Cài đặt tại: $INSTALL_DIR"
    log_info ""
    
    # Kiểm tra hệ điều hành
    if ! [[ "$OSTYPE" == "linux-gnu"* ]]; then
        log_error "Script này yêu cầu Linux (bạn có $OSTYPE)"
        exit 1
    fi
    
    install_dependencies
    check_requirements
    setup_directories
    setup_repository
    install_project_deps
    build_project
    create_wrapper
    update_path
    test_installation
    
    log_info ""
    log_success "Cài đặt hoàn tất!"
    log_info ""
    log_info "Bước tiếp theo:"
    log_info "  1. Tải lại shell: source ~/.bashrc"
    log_info "  2. Kiểm tra: openclaw --help"
    log_info "  3. Tài liệu: https://docs.openclaw.ai/"
    log_info ""
}

# Chạy chương trình chính
main "$@" 
