#!/bin/bash
set -euo pipefail

# OpenClaw Installer for Linux Ubuntu (Simplified)
# Usage: curl -fsSL https://raw.githubusercontent.com/hellofriendproject/openclaw/refs/heads/main/install.sh | bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
REPO_URL="https://github.com/hellofriendproject/openclaw.git"
INSTALL_DIR="${HOME}/.local/share/openclaw"
BIN_DIR="${HOME}/.local/bin"
DOWNLOADER=""

# Logging functions
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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect downloader
detect_downloader() {
    if command_exists curl; then
        DOWNLOADER="curl"
        return 0
    fi
    if command_exists wget; then
        DOWNLOADER="wget"
        return 0
    fi
    log_error "curl or wget required"
    exit 1
}

# Download file
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

# Detect distro
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO="${ID}"
    else
        log_error "Cannot detect Linux distribution"
        exit 1
    fi
}

# Install dependencies for Ubuntu/Debian
install_dependencies() {
    detect_distro
    
    if [[ "$DISTRO" != "ubuntu" && "$DISTRO" != "debian" ]]; then
        log_warn "This script is optimized for Ubuntu/Debian"
    fi
    
    local need_install=0
    
    if ! command_exists node; then
        log_info "Installing Node.js..."
        need_install=1
    fi
    
    if ! command_exists git; then
        log_info "Installing git..."
        need_install=1
    fi
    
    if ! command_exists python3; then
        log_info "Installing python3..."
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
            log_error "Please install Node.js, git, and build-essential"
            exit 1
        fi
    fi
}


# Check requirements
check_requirements() {
    log_info "Checking requirements..."
    
    if ! command_exists node; then
        log_error "Node.js not found"
        exit 1
    fi
    
    if ! command_exists git; then
        log_error "Git not found"
        exit 1
    fi
    
    local node_version=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [[ $node_version -lt 20 ]]; then
        log_error "Node.js 20+ required (you have $(node -v))"
        exit 1
    fi
    
    log_success "Node.js $(node -v)"
    log_success "npm $(npm -v | head -1)"
    log_success "git $(git --version | head -1)"
}

# Setup directories
setup_directories() {
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BIN_DIR"
}

# Clone or update repository
setup_repository() {
    log_info "Setting up repository..."
    
    if [[ ! -d "$INSTALL_DIR" ]]; then
        log_info "Cloning OpenClaw..."
        git clone "$REPO_URL" "$INSTALL_DIR" 2>&1 | tail -3 || true
    else
        log_info "Updating OpenClaw..."
        cd "$INSTALL_DIR"
        git fetch origin main 2>&1 | tail -2 || true
        git reset --hard origin/main 2>&1 | tail -2 || true
    fi
    
    log_success "Repository ready"
}

# Install project dependencies
install_project_deps() {
    log_info "Installing project dependencies..."
    cd "$INSTALL_DIR"
    
    if [[ -f "pnpm-lock.yaml" ]]; then
        if ! command_exists pnpm; then
            log_info "Installing pnpm..."
            npm install -g pnpm@10 >/dev/null 2>&1
        fi
        log_info "Running pnpm install..."
        pnpm install --frozen-lockfile 2>&1 | tail -5 || true
    else
        log_info "Running npm install..."
        npm install --omit=dev 2>&1 | tail -5 || true
    fi
    
    log_success "Dependencies installed"
}

# Build project
build_project() {
    log_info "Building OpenClaw..."
    cd "$INSTALL_DIR"
    
    if [[ -f "pnpm-lock.yaml" ]]; then
        pnpm build 2>&1 | tail -10 || true
    else
        npm run build 2>&1 | tail -10 || true
    fi
    
    if [[ ! -f "dist/entry.js" ]]; then
        log_error "Build failed - dist/entry.js not found"
        exit 1
    fi
    
    log_success "Build complete"
}

# Create wrapper binary
create_wrapper() {
    log_info "Creating openclaw wrapper..."
    
    local username=$(whoami)
    cat > "$BIN_DIR/openclaw" <<EOF
#!/bin/bash
exec node "${INSTALL_DIR}/dist/entry.js" "\$@"
EOF
    
    chmod +x "$BIN_DIR/openclaw"
    log_success "Wrapper created at $BIN_DIR/openclaw"
}

# Test installation
test_installation() {
    log_info "Testing installation..."
    
    export PATH="$BIN_DIR:$PATH"
    
    if "$BIN_DIR/openclaw" --version >/dev/null 2>&1; then
        local version=$("$BIN_DIR/openclaw" --version 2>/dev/null || echo "unknown")
        log_success "OpenClaw installed: $version"
    else
        log_warn "Could not verify openclaw binary"
    fi
}

# Update PATH
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

# Main installation flow
main() {
    clear
    
    log_info ""
    log_info "╔════════════════════════════════════╗"
    log_info "║     OpenClaw Installer (Ubuntu)    ║"
    log_info "╚════════════════════════════════════╝"
    log_info ""
    
    log_info "Repository: $REPO_URL"
    log_info "Install to: $INSTALL_DIR"
    log_info ""
    
    # Check OS
    if ! [[ "$OSTYPE" == "linux-gnu"* ]]; then
        log_error "This script requires Linux (you have $OSTYPE)"
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
    log_success "Installation complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Reload shell: source ~/.bashrc"
    log_info "  2. Test: openclaw --help"
    log_info "  3. Docs: https://docs.openclaw.ai/"
    log_info ""
}

# Run main
main "$@"
