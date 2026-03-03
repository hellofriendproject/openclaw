#!/bin/bash
set -euo pipefail
R="https://github.com/hellofriendproject/openclaw.git"; I="$HOME/.local/share/openclaw"; B="$HOME/.local/bin"
c(){ command -v "$1" >/dev/null 2>&1;}
e(){ c "$1" || (c sudo && sudo apt-get update -qq && sudo apt-get install -y -qq "$2" || { echo "❌ Cài $1 đi"; exit 1; });}
n(){ c node && [[ $(node -v|cut -d. -f1|tr -d 'v') -ge 20 ]] || { echo "❌ Cần Node >=20"; exit 1; };}
e git git; e curl curl; n; e npm npm; c pnpm || npm i -g pnpm@10
mkdir -p "$I" "$B"; [[ -d $I && ! -d $I/.git ]] && rm -rf "$I"
[[ ! -d $I ]] && git clone "$R" "$I" || (cd "$I" && git fetch origin main && git reset --hard origin/main)
cd "$I" && pnpm i --frozen-lockfile && pnpm build
printf "#!/bin/bash\nexec node $I/dist/entry.js \"\$@\"" > "$B/openclaw" && chmod +x "$B/openclaw"
for f in "$HOME/.bashrc" "$HOME/.zshrc"; do [[ -f $f ]] && ! grep -q "$B" "$f" && echo "export PATH=\"$B:\$PATH\"" >> "$f"; done
export PATH="$B:$PATH"
echo -e "\n🛠️ Setup..." && sleep 1 && "$B/openclaw" onboard
echo -e "\n🚀 Run..." && exec "$B/openclaw" gateway
