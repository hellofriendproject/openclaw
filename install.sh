#!/bin/bash
set -euo pipefail

# Minimal OpenClaw installer (no daemon, non-interactive)
# Usage: curl -fsSL <url>/install.sh | bash

REPO="https://github.com/hellofriendproject/openclaw.git"
INSTALL_DIR="$HOME/.local/share/openclaw"
BIN_DIR="$HOME/.local/bin"

cmd_exists(){ command -v "$1" >/dev/null 2>&1; }

ensure_cmd(){
    if ! cmd_exists "$1"; then
        if cmd_exists sudo && [[ -f /etc/os-release ]]; then
            sudo apt-get update -qq
            sudo apt-get install -y -qq "$2"
        else
            echo "please install $1 and re-run."
            exit 1
        fi
    fi
}

check_node(){
    if ! cmd_exists node; then
        echo "node is required"; exit 1
    fi
    v=$(node -v | cut -d'v' -f2 | cut -d. -f1)
    if [[ "$v" -lt 20 ]]; then
        echo "node 20+ required (have $(node -v))"; exit 1
    fi
}

# prerequisites
ensure_cmd git git
ensure_cmd curl curl
check_node
ensure_cmd npm npm
if ! cmd_exists pnpm; then
    echo "installing pnpm..."
    npm install -g pnpm@10 >/dev/null 2>&1
fi

mkdir -p "$INSTALL_DIR" "$BIN_DIR"

# clone or update
if [[ -d "$INSTALL_DIR" && ! -d "$INSTALL_DIR/.git" ]]; then
    rm -rf "$INSTALL_DIR"
fi

if [[ ! -d "$INSTALL_DIR" ]]; then
    git clone "$REPO" "$INSTALL_DIR"
else
    cd "$INSTALL_DIR" && git fetch origin main && git reset --hard origin/main
fi

cd "$INSTALL_DIR"
pnpm install --frozen-lockfile
pnpm build

cat > "$BIN_DIR/openclaw" <<'EOF'
#!/bin/bash
exec node "$(dirname "$0")/../share/openclaw/dist/entry.js" "$@"
EOF

chmod +x "$BIN_DIR/openclaw"

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$rc" && ! $(grep -q "$BIN_DIR" "$rc" || true) ]]; then
        printf '\n# OpenClaw\nexport PATH="%s:$PATH"\n' "$BIN_DIR" >> "$rc"
    fi
done

export PATH="$BIN_DIR:$PATH"

echo
cat <<'MSG'
✅ OpenClaw installed in $INSTALL_DIR

To configure and start using the CLI, run:
  openclaw onboard

(daemon support was removed; run the gateway manually if needed.)
MSG
