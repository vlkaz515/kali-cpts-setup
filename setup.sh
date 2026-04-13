#!/usr/bin/env bash
# =============================================================================
# CPTS Kali Linux Tool Setup Script v3.0 — FINAL
# Tested and verified on Kali 2026.1 (Python 3.13)
# Run as normal kali user — NOT as root/sudo
# Usage: chmod +x setup.sh && ./setup.sh 2>&1 | tee ~/setup.log
# =============================================================================

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
info()    { echo -e "${CYAN}[*]${NC} $*"; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"; \
            echo -e "${BOLD}${CYAN}  $*${NC}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}\n"; }

TOOLS="$HOME/tools"
VENVS="$TOOLS/venvs"
WIN="$TOOLS/transfer/windows"
LIN="$TOOLS/transfer/linux"

mkdir -p "$VENVS" "$WIN" "$LIN"
export PATH="/usr/local/bin:$HOME/.local/bin:$HOME/go/bin:$HOME/.cargo/bin:$PATH"
export GOPATH="$HOME/go"
mkdir -p "$GOPATH"

# ── Helper: install Python tool from git repo ─────────────────────────────────
# Creates venv, installs deps, writes global wrapper to /usr/local/bin
# IMPORTANT: setuptools always installed first to fix Python 3.13 distutils removal
install_git_tool() {
    local name="$1" url="$2" entry="$3"
    local dest="$TOOLS/$name" venv="$VENVS/$name"
    info "$name..."
    [[ -d "$dest/.git" ]] && git -C "$dest" pull -q || \
        git clone --depth=1 -q "$url" "$dest"
    python3 -m venv "$venv"
    "$venv/bin/pip" install -q --upgrade pip setuptools
    [[ -f "$dest/requirements.txt" ]] && \
        "$venv/bin/pip" install -q -r "$dest/requirements.txt" 2>/dev/null || true
    [[ -f "$dest/setup.py" || -f "$dest/pyproject.toml" ]] && \
        "$venv/bin/pip" install -q -e "$dest" 2>/dev/null || true
    sudo tee "/usr/local/bin/$name" > /dev/null <<EOF
#!/usr/bin/env bash
exec "$venv/bin/python3" "$dest/$entry" "\$@"
EOF
    sudo chmod +x "/usr/local/bin/$name"
    log "$name → /usr/local/bin/$name"
}

# ── Helper: install single pip package with venv + global wrapper ─────────────
install_pip_tool() {
    local name="$1" pkg="${2:-$1}"
    local venv="$VENVS/$name"
    info "$name..."
    python3 -m venv "$venv"
    "$venv/bin/pip" install -q --upgrade pip setuptools "$pkg"
    local bin
    bin=$(find "$venv/bin" -maxdepth 1 -name "$name" 2>/dev/null | head -1)
    [[ -z "$bin" ]] && bin="$venv/bin/$name"
    sudo tee "/usr/local/bin/$name" > /dev/null <<EOF
#!/usr/bin/env bash
exec "$bin" "\$@"
EOF
    sudo chmod +x "/usr/local/bin/$name"
    log "$name installed"
}

# =============================================================================
section "1 — SYSTEM UPDATE & KALI APT PACKAGES"
# =============================================================================

sudo apt-get update -qq
sudo apt-get upgrade -y -qq

sudo apt-get install -y -qq \
    nmap gobuster ffuf hydra medusa netcat-openbsd ncat \
    smbclient smbmap crackmapexec \
    john hashcat exploitdb metasploit-framework \
    responder bloodhound \
    evil-winrm wpscan sqlmap \
    wireshark tshark \
    proxychains4 socat \
    dnsenum fierce \
    onesixtyone snmp braa \
    python3-pip python3-venv python3-dev \
    golang-go cargo \
    ruby-full \
    sshuttle rdesktop freerdp2-x11 \
    ettercap-text-only bettercap \
    crowbar smtp-user-enum swaks sqsh \
    curl wget git vim jq rlwrap \
    build-essential libssl-dev libffi-dev libpcap-dev \
    dnsutils whois net-tools cifs-utils \
    gvm zaproxy burpsuite \
    wordlists cupp gpp-decrypt \
    automake autoconf \
    netexec \
    recon-ng theharvester ssh-audit \
    seclists \
    lynis strace \
    libguestfs-tools restic \
    2>/dev/null || warn "Some apt packages may have failed — check individually"

[[ -f /usr/share/wordlists/rockyou.txt.gz ]] && \
    sudo gunzip -f /usr/share/wordlists/rockyou.txt.gz 2>/dev/null || true

log "APT packages done"

# =============================================================================
section "2 — NEO4J (BloodHound backend)"
# =============================================================================

if ! command -v neo4j &>/dev/null; then
    info "Installing Neo4j..."
    # Use timeout to prevent hanging on network issues
    if timeout 30 wget -q -O - https://debian.neo4j.com/neotechnology.gpg.key | \
        sudo apt-key add - 2>/dev/null; then
        echo 'deb https://debian.neo4j.com stable latest' | \
            sudo tee /etc/apt/sources.list.d/neo4j.list > /dev/null
        sudo apt-get update -qq
        sudo apt-get install -y -qq neo4j 2>/dev/null && \
            log "Neo4j installed" || \
            warn "Neo4j install failed — run manually: sudo apt install neo4j"
    else
        warn "Neo4j GPG key download failed — trying apt directly..."
        sudo apt-get install -y -qq neo4j 2>/dev/null && \
            log "Neo4j installed via apt" || \
            warn "Neo4j not available — install manually if needed for BloodHound"
    fi
else
    log "Neo4j already installed"
fi

# =============================================================================
section "3 — GO TOOLS"
# =============================================================================

if ! command -v go &>/dev/null; then
    sudo apt-get install -y -qq golang-go
fi

# subfinder
info "subfinder..."
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest 2>/dev/null
[[ -f "$GOPATH/bin/subfinder" ]] && \
    sudo cp "$GOPATH/bin/subfinder" /usr/local/bin/subfinder
log "subfinder installed"

# chisel — fetch exact version tag first, use correct zip format
info "chisel..."
CHISEL_VER=$(curl -s https://api.github.com/repos/jpillora/chisel/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
CHISEL_VER="${CHISEL_VER:-v1.11.5}"
CHISEL_NUM="${CHISEL_VER#v}"
# Linux
curl -fsSL "https://github.com/jpillora/chisel/releases/download/${CHISEL_VER}/chisel_${CHISEL_NUM}_linux_amd64.gz" \
    -o /tmp/chisel_linux.gz && gunzip -f /tmp/chisel_linux.gz && \
    sudo mv /tmp/chisel_linux /usr/local/bin/chisel && \
    sudo chmod +x /usr/local/bin/chisel
cp /usr/local/bin/chisel "$LIN/chisel"
# Windows (zip since v1.10+)
curl -fsSL "https://github.com/jpillora/chisel/releases/download/${CHISEL_VER}/chisel_${CHISEL_NUM}_windows_amd64.zip" \
    -o /tmp/chisel_win.zip && \
    unzip -q -o /tmp/chisel_win.zip chisel.exe -d /tmp && \
    mv /tmp/chisel.exe "$WIN/chisel.exe"
log "chisel installed"

# ligolo-ng
info "ligolo-ng..."
LIGOLO_VER=$(curl -s https://api.github.com/repos/nicocha30/ligolo-ng/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
LIGOLO_VER="${LIGOLO_VER:-v0.6.2}"
VER="${LIGOLO_VER#v}"
curl -fsSL "https://github.com/nicocha30/ligolo-ng/releases/download/${LIGOLO_VER}/ligolo-ng_proxy_${VER}_linux_amd64.tar.gz" \
    -o /tmp/ligolo_proxy.tar.gz
tar -xzf /tmp/ligolo_proxy.tar.gz -C /tmp
sudo mv /tmp/proxy /usr/local/bin/ligolo-proxy && \
    sudo chmod +x /usr/local/bin/ligolo-proxy
curl -fsSL "https://github.com/nicocha30/ligolo-ng/releases/download/${LIGOLO_VER}/ligolo-ng_agent_${VER}_linux_amd64.tar.gz" \
    -o /tmp/ligolo_agent_lin.tar.gz
tar -xzf /tmp/ligolo_agent_lin.tar.gz -C /tmp
mv /tmp/agent "$LIN/ligolo-agent" && chmod +x "$LIN/ligolo-agent"
curl -fsSL "https://github.com/nicocha30/ligolo-ng/releases/download/${LIGOLO_VER}/ligolo-ng_agent_${VER}_windows_amd64.zip" \
    -o /tmp/ligolo_win.zip
unzip -q -o /tmp/ligolo_win.zip -d /tmp/ligolo_win
find /tmp/ligolo_win -name "agent.exe" -exec mv {} "$WIN/ligolo-agent.exe" \;
log "ligolo-ng installed"

# kerbrute
info "kerbrute..."
KERBRUTE_VER=$(curl -s https://api.github.com/repos/ropnop/kerbrute/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
KERBRUTE_VER="${KERBRUTE_VER:-v1.0.3}"
curl -fsSL "https://github.com/ropnop/kerbrute/releases/download/${KERBRUTE_VER}/kerbrute_linux_amd64" \
    -o /tmp/kerbrute && sudo mv /tmp/kerbrute /usr/local/bin/kerbrute && \
    sudo chmod +x /usr/local/bin/kerbrute
log "kerbrute installed"

# rustscan
info "rustscan..."
RUSTSCAN_VER=$(curl -s https://api.github.com/repos/RustScan/RustScan/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
RUSTSCAN_VER="${RUSTSCAN_VER:-2.3.0}"
curl -fsSL "https://github.com/RustScan/RustScan/releases/download/${RUSTSCAN_VER}/rustscan_${RUSTSCAN_VER}_amd64.deb" \
    -o /tmp/rustscan.deb && sudo dpkg -i /tmp/rustscan.deb
log "rustscan installed"

# aquatone
info "aquatone..."
AQUATONE_VER=$(curl -s https://api.github.com/repos/michenriksen/aquatone/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
AQUATONE_VER="${AQUATONE_VER:-v1.7.0}"
curl -fsSL "https://github.com/michenriksen/aquatone/releases/download/${AQUATONE_VER}/aquatone_linux_amd64_${AQUATONE_VER#v}.zip" \
    -o /tmp/aquatone.zip && \
    unzip -q -o /tmp/aquatone.zip -d /tmp/aquatone_dir && \
    sudo mv /tmp/aquatone_dir/aquatone /usr/local/bin/aquatone && \
    sudo chmod +x /usr/local/bin/aquatone
log "aquatone installed"

# masscan
if ! command -v masscan &>/dev/null; then
    info "masscan (building from source)..."
    git clone -q --depth=1 https://github.com/robertdavidgraham/masscan /tmp/masscan_build
    make -C /tmp/masscan_build -j"$(nproc)" -s
    sudo mv /tmp/masscan_build/bin/masscan /usr/local/bin/masscan
    rm -rf /tmp/masscan_build
    log "masscan installed"
fi

# =============================================================================
section "4 — RUBY TOOLS"
# =============================================================================

sudo gem install evil-winrm --no-document -q 2>/dev/null && \
    log "evil-winrm (gem) installed"

info "username-anarchy..."
[[ ! -d "$TOOLS/username-anarchy/.git" ]] && \
    git clone -q --depth=1 https://github.com/urbanadventurer/username-anarchy \
        "$TOOLS/username-anarchy"
sudo tee /usr/local/bin/username-anarchy > /dev/null <<EOF
#!/usr/bin/env bash
exec ruby "$TOOLS/username-anarchy/username-anarchy" "\$@"
EOF
sudo chmod +x /usr/local/bin/username-anarchy
log "username-anarchy installed"

info "dnscat2..."
[[ ! -d "$TOOLS/dnscat2/.git" ]] && \
    git clone -q --depth=1 https://github.com/iagox86/dnscat2.git "$TOOLS/dnscat2"
cd "$TOOLS/dnscat2/server"
sudo gem install bundler --no-document -q 2>/dev/null || true
bundle install -q 2>/dev/null || warn "dnscat2 bundle issues — may need manual fix"
cd - > /dev/null
sudo tee /usr/local/bin/dnscat2-server > /dev/null <<EOF
#!/usr/bin/env bash
cd "$TOOLS/dnscat2/server" && exec ruby dnscat2.rb "\$@"
EOF
sudo chmod +x /usr/local/bin/dnscat2-server
[[ ! -d "$WIN/dnscat2-powershell/.git" ]] && \
    git clone -q --depth=1 https://github.com/lukebaggett/dnscat2-powershell \
        "$WIN/dnscat2-powershell"
log "dnscat2-server installed"

# =============================================================================
section "5 — IMPACKET"
# =============================================================================

info "Impacket..."
IMP="$TOOLS/impacket"
IMP_VENV="$VENVS/impacket"
[[ -d "$IMP/.git" ]] && git -C "$IMP" pull -q || \
    git clone --depth=1 -q https://github.com/fortra/impacket "$IMP"
python3 -m venv "$IMP_VENV"
"$IMP_VENV/bin/pip" install -q --upgrade pip setuptools
"$IMP_VENV/bin/pip" install -q -e "$IMP"
for script in "$IMP/examples/"*.py; do
    bname=$(basename "$script" .py)
    sudo tee "/usr/local/bin/impacket-$bname" > /dev/null <<WRAP
#!/usr/bin/env bash
exec "$IMP_VENV/bin/python3" "$script" "\$@"
WRAP
    sudo chmod +x "/usr/local/bin/impacket-$bname"
done
log "Impacket installed — all scripts wrapped as impacket-<n>"

# =============================================================================
section "6 — PYTHON TOOLS"
# =============================================================================

# NetExec — apt first, git fallback
info "NetExec (nxc)..."
if sudo apt-get install -y -qq netexec 2>/dev/null; then
    log "nxc installed via apt"
else
    NXC="$TOOLS/netexec"; NXC_VENV="$VENVS/netexec"
    [[ -d "$NXC/.git" ]] && git -C "$NXC" pull -q || \
        git clone --depth=1 -q https://github.com/Pennyw0rth/NetExec "$NXC"
    python3 -m venv "$NXC_VENV"
    "$NXC_VENV/bin/pip" install -q --upgrade pip setuptools
    "$NXC_VENV/bin/pip" install -q -e "$NXC"
    sudo tee /usr/local/bin/nxc > /dev/null <<EOF
#!/usr/bin/env bash
exec "$NXC_VENV/bin/nxc" "\$@"
EOF
    sudo chmod +x /usr/local/bin/nxc
    log "nxc installed via git+venv"
fi

# BloodHound Python ingestor
info "bloodhound-python..."
BHP="$TOOLS/BloodHound.py"; BHP_VENV="$VENVS/bloodhound-python"
[[ -d "$BHP/.git" ]] && git -C "$BHP" pull -q || \
    git clone --depth=1 -q https://github.com/dirkjanm/BloodHound.py "$BHP"
python3 -m venv "$BHP_VENV"
"$BHP_VENV/bin/pip" install -q --upgrade pip setuptools
"$BHP_VENV/bin/pip" install -q -e "$BHP"
sudo tee /usr/local/bin/bloodhound-python > /dev/null <<EOF
#!/usr/bin/env bash
exec "$BHP_VENV/bin/bloodhound-python" "\$@"
EOF
sudo chmod +x /usr/local/bin/bloodhound-python
log "bloodhound-python installed"

# PKINITtools
info "PKINITtools..."
PKIN="$TOOLS/PKINITtools"; PKIN_VENV="$VENVS/PKINITtools"
[[ -d "$PKIN/.git" ]] && git -C "$PKIN" pull -q || \
    git clone --depth=1 -q https://github.com/dirkjanm/PKINITtools "$PKIN"
python3 -m venv "$PKIN_VENV"
"$PKIN_VENV/bin/pip" install -q --upgrade pip setuptools impacket minikerberos
for script in "$PKIN/"*.py; do
    bname=$(basename "$script" .py)
    sudo tee "/usr/local/bin/$bname" > /dev/null <<WRAP
#!/usr/bin/env bash
exec "$PKIN_VENV/bin/python3" "$script" "\$@"
WRAP
    sudo chmod +x "/usr/local/bin/$bname"
done
log "PKINITtools installed"



# noPac — CVE-2021-42278/42287: escalate standard domain user to Domain Admin
# NOTE: May have issues on Python 3.13 due to impacket pkg_resources dependency
# Alternative if broken: use impacket-addcomputer + impacket-getST (already installed)
info "noPac..."
NPAC="$TOOLS/noPac"; NPAC_VENV="$VENVS/noPac"
[[ -d "$NPAC/.git" ]] && git -C "$NPAC" pull -q || \
    git clone --depth=1 -q https://github.com/Ridter/noPac "$NPAC"
python3 -m venv "$NPAC_VENV"
"$NPAC_VENV/bin/pip" install -q --upgrade pip setuptools
"$NPAC_VENV/bin/pip" install -q impacket
[[ -f "$NPAC/requirements.txt" ]] && \
    "$NPAC_VENV/bin/pip" install -q -r "$NPAC/requirements.txt" 2>/dev/null || true
# Force setuptools reinstall AFTER all other installs
# impacket's version.py uses pkg_resources which requires setuptools
"$NPAC_VENV/bin/pip" install -q --force-reinstall setuptools
# Patch impacket version.py to not use pkg_resources (removed in Python 3.13)
IMPACKET_VER=$(find "$NPAC_VENV" -path "*/impacket/version.py" 2>/dev/null | head -1)
if [[ -n "$IMPACKET_VER" ]]; then
    sed -i 's/import pkg_resources/try:\n    import pkg_resources\nexcept ImportError:\n    pkg_resources = None/' \
        "$IMPACKET_VER" 2>/dev/null || \
    python3 -c "
content = open('$IMPACKET_VER').read()
content = content.replace('import pkg_resources', 'try:\n    import pkg_resources\nexcept ImportError:\n    pkg_resources = None')
open('$IMPACKET_VER', 'w').write(content)
"
fi
sudo tee /usr/local/bin/noPac > /dev/null <<EOF
#!/usr/bin/env bash
cd "$NPAC" && exec "$NPAC_VENV/bin/python3" "$NPAC/noPac.py" "\$@"
EOF
sudo ln -sf /usr/local/bin/noPac /usr/local/bin/nopac
sudo chmod +x /usr/local/bin/noPac
log "noPac installed"

# PetitPotam — needs impacket in its own venv
info "PetitPotam..."
PT="$TOOLS/PetitPotam"; PT_VENV="$VENVS/PetitPotam"
[[ -d "$PT/.git" ]] && git -C "$PT" pull -q || \
    git clone --depth=1 -q https://github.com/topotam/PetitPotam "$PT"
python3 -m venv "$PT_VENV"
"$PT_VENV/bin/pip" install -q --upgrade pip setuptools impacket
sudo tee /usr/local/bin/petitpotam > /dev/null <<EOF
#!/usr/bin/env bash
exec "$PT_VENV/bin/python3" "$PT/PetitPotam.py" "\$@"
EOF
sudo chmod +x /usr/local/bin/petitpotam
log "PetitPotam installed"

# adidnsdump
install_git_tool "adidnsdump" \
    "https://github.com/dirkjanm/adidnsdump" \
    "adidnsdump/adidnsdump.py"

# Bashfuscator — needs setuptools for setup.py
info "Bashfuscator..."
BFUSC="$TOOLS/Bashfuscator"; BFUSC_VENV="$VENVS/Bashfuscator"
[[ -d "$BFUSC/.git" ]] && git -C "$BFUSC" pull -q || \
    git clone --depth=1 -q https://github.com/Bashfuscator/Bashfuscator "$BFUSC"
python3 -m venv "$BFUSC_VENV"
"$BFUSC_VENV/bin/pip" install -q --upgrade pip setuptools
"$BFUSC_VENV/bin/pip" install -q -e "$BFUSC"
sudo tee /usr/local/bin/bashfuscator > /dev/null <<EOF
#!/usr/bin/env bash
exec "$BFUSC_VENV/bin/python3" "$BFUSC/bashfuscator/bin/bashfuscator" "\$@"
EOF
sudo chmod +x /usr/local/bin/bashfuscator
log "bashfuscator installed"

# o365spray
install_git_tool "o365spray" \
    "https://github.com/0xZDH/o365spray" \
    "o365spray.py"

# EyeWitness — must run from Python/ subdir, needs psutil
info "EyeWitness..."
EW="$TOOLS/EyeWitness"; EW_VENV="$VENVS/EyeWitness"
[[ -d "$EW/.git" ]] && git -C "$EW" pull -q || \
    git clone --depth=1 -q https://github.com/RedSiege/EyeWitness "$EW"
python3 -m venv "$EW_VENV"
"$EW_VENV/bin/pip" install -q --upgrade pip setuptools
"$EW_VENV/bin/pip" install -q psutil selenium fuzzywuzzy python-Levenshtein \
    netaddr requests 2>/dev/null || true
[[ -f "$EW/Python/requirements.txt" ]] && \
    "$EW_VENV/bin/pip" install -q -r "$EW/Python/requirements.txt" 2>/dev/null || true
# IMPORTANT: wrapper must cd into Python/ subdir (local module imports)
sudo tee /usr/local/bin/eyewitness > /dev/null <<EOF
#!/usr/bin/env bash
cd "$EW/Python" && exec "$EW_VENV/bin/python3" "$EW/Python/EyeWitness.py" "\$@"
EOF
sudo chmod +x /usr/local/bin/eyewitness
log "eyewitness installed"

# FinalRecon
install_git_tool "FinalRecon" \
    "https://github.com/thewhiteh4t/FinalRecon" \
    "finalrecon.py"

# SpiderFoot — install deps explicitly, requirements.txt alone misses some
install_git_tool "SpiderFoot" \
    "https://github.com/smicallef/spiderfoot" \
    "sf.py"
"$VENVS/SpiderFoot/bin/pip" install -q \
    cherrypy cherrypy_cors dnspython cryptography \
    --only-binary=:all: lxml 2>/dev/null || \
"$VENVS/SpiderFoot/bin/pip" install -q \
    cherrypy cherrypy_cors dnspython cryptography 2>/dev/null || true

sudo tee /usr/local/bin/spiderfoot > /dev/null <<EOF
#!/usr/bin/env bash
exec "$VENVS/SpiderFoot/bin/python3" "$TOOLS/SpiderFoot/sf.py" "\$@"
EOF
sudo chmod +x /usr/local/bin/spiderfoot

# XSStrike — must run from its own directory (local core/ package)
info "XSStrike..."
XS="$TOOLS/XSStrike"; XS_VENV="$VENVS/XSStrike"
[[ -d "$XS/.git" ]] && git -C "$XS" pull -q || \
    git clone --depth=1 -q https://github.com/s0md3v/XSStrike "$XS"
python3 -m venv "$XS_VENV"
"$XS_VENV/bin/pip" install -q --upgrade pip setuptools
[[ -f "$XS/requirements.txt" ]] && \
    "$XS_VENV/bin/pip" install -q -r "$XS/requirements.txt" 2>/dev/null || true
# IMPORTANT: wrapper must cd into tool dir (local core/ imports)
sudo tee /usr/local/bin/xsstrike > /dev/null <<EOF
#!/usr/bin/env bash
cd "$XS" && exec "$XS_VENV/bin/python3" "$XS/xsstrike.py" "\$@"
EOF
sudo chmod +x /usr/local/bin/xsstrike
log "xsstrike installed"

# droopescan — needs cement==2.10.14 + Python 3.13 compat patches
info "droopescan..."
DS="$TOOLS/droopescan"; DS_VENV="$VENVS/droopescan"
[[ -d "$DS/.git" ]] && git -C "$DS" pull -q || \
    git clone --depth=1 -q https://github.com/droope/droopescan "$DS"
python3 -m venv "$DS_VENV"
"$DS_VENV/bin/pip" install -q --upgrade pip setuptools
"$DS_VENV/bin/pip" install -q "cement==2.10.14"
[[ -f "$DS/requirements.txt" ]] && \
    "$DS_VENV/bin/pip" install -q -r "$DS/requirements.txt" 2>/dev/null || true
"$DS_VENV/bin/pip" install -q -e "$DS" 2>/dev/null || true

# Patch cement's ext_plugin.py for Python 3.12+ compatibility
# cement 2.x uses the removed 'imp' module — patch it to use importlib instead
CEMENT_PLUGIN=$(find "$DS_VENV" -name "ext_plugin.py" 2>/dev/null | head -1)
if [[ -n "$CEMENT_PLUGIN" ]]; then
    python3 << PATCHEOF
path = "$CEMENT_PLUGIN"
with open(path, "r") as f:
    content = f.read()

# Fix imports
content = content.replace("import imp\n", "import importlib.util\nimport importlib.machinery\nimport os\n")
content = content.replace("from imp import reload\n", "from importlib import reload\n")

# Fix imp.find_module call — replace with os.path check
old = "        f, path, desc = imp.find_module(plugin_name, [plugin_dir])"
new = "        plugin_file = os.path.join(plugin_dir, plugin_name + '.py')\n        if not os.path.exists(plugin_file):\n            return False\n        path = plugin_file"
content = content.replace(old, new)

# Fix imp.load_module call — replace with importlib equivalent
old2 = "        mod = imp.load_module(plugin_name, f, path, desc)"
new2 = "        spec = importlib.util.spec_from_file_location(plugin_name, path)\n        mod = importlib.util.module_from_spec(spec)\n        spec.loader.exec_module(mod)"
content = content.replace(old2, new2)

with open(path, "w") as f:
    f.write(content)
print("cement ext_plugin.py patched for Python 3.13")
PATCHEOF
fi
sudo tee /usr/local/bin/droopescan > /dev/null <<EOF
#!/usr/bin/env bash
exec "$DS_VENV/bin/python3" "$DS/droopescan" "\$@"
EOF
sudo chmod +x /usr/local/bin/droopescan
log "droopescan installed"

# enum4linux-ng
install_git_tool "enum4linux-ng" \
    "https://github.com/cddmp/enum4linux-ng" \
    "enum4linux-ng.py"

# PCredz — wrapper uses lowercase pcredz
info "PCredz..."
PC="$TOOLS/PCredz"; PC_VENV="$VENVS/PCredz"
[[ -d "$PC/.git" ]] && git -C "$PC" pull -q || \
    git clone --depth=1 -q https://github.com/lgandx/PCredz "$PC"
python3 -m venv "$PC_VENV"
"$PC_VENV/bin/pip" install -q --upgrade pip setuptools
[[ -f "$PC/requirements.txt" ]] && \
    "$PC_VENV/bin/pip" install -q -r "$PC/requirements.txt" 2>/dev/null || true
sudo tee /usr/local/bin/pcredz > /dev/null <<EOF
#!/usr/bin/env bash
exec "$PC_VENV/bin/python3" "$PC/Pcredz" "\$@"
EOF
sudo chmod +x /usr/local/bin/pcredz
log "pcredz installed"

# mimipenguin — needs root to actually run, install only
info "mimipenguin..."
MM="$TOOLS/mimipenguin"; MM_VENV="$VENVS/mimipenguin"
[[ -d "$MM/.git" ]] && git -C "$MM" pull -q || \
    git clone --depth=1 -q https://github.com/huntergregal/mimipenguin "$MM"
python3 -m venv "$MM_VENV"
"$MM_VENV/bin/pip" install -q --upgrade pip setuptools passlib
"$MM_VENV/bin/pip" install -q legacycrypt 2>/dev/null || true
sudo tee /usr/local/bin/mimipenguin > /dev/null <<EOF
#!/usr/bin/env bash
exec "$MM_VENV/bin/python3" "$MM/mimipenguin.py" "\$@"
EOF
sudo chmod +x /usr/local/bin/mimipenguin
log "mimipenguin installed (run with sudo)"

# firefox_decrypt
install_git_tool "firefox_decrypt" \
    "https://github.com/unode/firefox_decrypt" \
    "firefox_decrypt.py"

# ssh-audit — install via pip (more reliable than git on Python 3.13)
info "ssh-audit..."
SA_VENV="$VENVS/ssh-audit"
python3 -m venv "$SA_VENV"
"$SA_VENV/bin/pip" install -q --upgrade pip setuptools ssh-audit
sudo tee /usr/local/bin/ssh-audit > /dev/null <<EOF
#!/usr/bin/env bash
exec "$SA_VENV/bin/ssh-audit" "\$@"
EOF
sudo chmod +x /usr/local/bin/ssh-audit
log "ssh-audit installed"

# odat — optional, needs Oracle Instant Client for cx_Oracle
info "odat (optional — needs Oracle Instant Client)..."
OD="$TOOLS/odat"; OD_VENV="$VENVS/odat"
[[ -d "$OD/.git" ]] && git -C "$OD" pull -q || \
    git clone --depth=1 -q https://github.com/quentinhardy/odat "$OD"
python3 -m venv "$OD_VENV"
"$OD_VENV/bin/pip" install -q --upgrade pip setuptools
"$OD_VENV/bin/pip" install -q python-libnmap colorlog termcolor passlib \
    pycryptodome scapy 2>/dev/null || true
"$OD_VENV/bin/pip" install -q cx_Oracle 2>/dev/null || \
    warn "odat: cx_Oracle needs Oracle Instant Client — see setup instructions"
sudo tee /usr/local/bin/odat > /dev/null <<EOF
#!/usr/bin/env bash
# NOTE: Requires Oracle Instant Client system libraries
# https://oracle.github.io/odpi/doc/installation.html
exec "$OD_VENV/bin/python3" "$OD/odat.py" "\$@"
EOF
sudo chmod +x /usr/local/bin/odat
log "odat installed (cx_Oracle optional)"

# rpivot — Python 2 only, replaced with helpful wrapper pointing to alternatives
sudo tee /usr/local/bin/rpivot-server > /dev/null <<'EOF'
#!/usr/bin/env bash
echo "[!] rpivot requires Python 2.7 (EOL) — not available on modern Kali"
echo "[!] Use these alternatives instead:"
echo "    chisel  : chisel server --reverse -v -p 1080 --socks5"
echo "    ligolo  : ligolo-proxy -selfcert -laddr 0.0.0.0:11601"
echo "    ssh     : ssh -D 9050 -N user@pivot"
exit 1
EOF
sudo tee /usr/local/bin/rpivot-client > /dev/null <<'EOF'
#!/usr/bin/env bash
echo "[!] rpivot requires Python 2.7 (EOL) — not available on modern Kali"
echo "[!] Use chisel or ligolo-ng instead"
exit 1
EOF
sudo chmod +x /usr/local/bin/rpivot-server /usr/local/bin/rpivot-client
log "rpivot replaced with helpful error + alternatives"

# LaZagne
info "lazagne..."
LAZ="$TOOLS/LaZagne"; LAZ_VENV="$VENVS/LaZagne"
[[ -d "$LAZ/.git" ]] && git -C "$LAZ" pull -q || \
    git clone --depth=1 -q https://github.com/AlessandroZ/LaZagne "$LAZ"
python3 -m venv "$LAZ_VENV"
"$LAZ_VENV/bin/pip" install -q --upgrade pip setuptools
"$LAZ_VENV/bin/pip" install -q -r "$LAZ/Linux/requirements.txt" 2>/dev/null || true
sudo tee /usr/local/bin/lazagne > /dev/null <<EOF
#!/usr/bin/env bash
exec "$LAZ_VENV/bin/python3" "$LAZ/Linux/laZagne.py" "\$@"
EOF
sudo chmod +x /usr/local/bin/lazagne
log "lazagne installed"

# MANSPIDER
info "MANSPIDER..."
MAN="$TOOLS/MANSPIDER"; MAN_VENV="$VENVS/MANSPIDER"
[[ -d "$MAN/.git" ]] && git -C "$MAN" pull -q || \
    git clone --depth=1 -q https://github.com/blacklanternsecurity/MANSPIDER "$MAN"
python3 -m venv "$MAN_VENV"
"$MAN_VENV/bin/pip" install -q --upgrade pip setuptools
"$MAN_VENV/bin/pip" install -q \
    git+https://github.com/blacklanternsecurity/MANSPIDER 2>/dev/null || \
"$MAN_VENV/bin/pip" install -q -e "$MAN" 2>/dev/null || true
sudo tee /usr/local/bin/manspider > /dev/null <<EOF
#!/usr/bin/env bash
exec "$MAN_VENV/bin/manspider" "\$@"
EOF
sudo chmod +x /usr/local/bin/manspider
log "manspider installed"

# Single-package pip tools — setuptools always installed for pkg_resources
install_pip_tool "uploadserver"
install_pip_tool "hashid"
install_pip_tool "pypykatz"
# shodan needs setuptools for pkg_resources
SHODAN_VENV="$VENVS/shodan"
python3 -m venv "$SHODAN_VENV"
"$SHODAN_VENV/bin/pip" install -q --upgrade pip
"$SHODAN_VENV/bin/pip" install -q --upgrade setuptools
"$SHODAN_VENV/bin/pip" install -q shodan
# Force setuptools reinstall to ensure pkg_resources is available
"$SHODAN_VENV/bin/pip" install -q --force-reinstall setuptools
sudo tee /usr/local/bin/shodan > /dev/null <<EOF
#!/usr/bin/env bash
exec "$SHODAN_VENV/bin/shodan" "\$@"
EOF
sudo chmod +x /usr/local/bin/shodan
log "shodan installed"

# openvasreporting — needs pyyaml
info "openvasreporting..."
OVR_VENV="$VENVS/openvasreporting"
python3 -m venv "$OVR_VENV"
"$OVR_VENV/bin/pip" install -q --upgrade pip setuptools pyyaml defusedxml
"$OVR_VENV/bin/pip" install -q openvasreporting 2>/dev/null || \
"$OVR_VENV/bin/pip" install -q \
    git+https://github.com/TheGroundZero/openvasreporting 2>/dev/null || \
    warn "openvasreporting: install failed — low priority tool"
OVR_BIN=$(find "$OVR_VENV/bin" -name "openvas*" 2>/dev/null | head -1)
if [[ -n "$OVR_BIN" ]]; then
    sudo tee /usr/local/bin/openvasreporting > /dev/null <<EOF
#!/usr/bin/env bash
exec "$OVR_BIN" "\$@"
EOF
    sudo chmod +x /usr/local/bin/openvasreporting
    log "openvasreporting installed"
fi

# subbrute
info "subbrute..."
[[ ! -d "$TOOLS/subbrute/.git" ]] && \
    git clone -q --depth=1 https://github.com/TheRook/subbrute "$TOOLS/subbrute"
python3 -m venv "$VENVS/subbrute"
"$VENVS/subbrute/bin/pip" install -q --upgrade pip setuptools
sudo tee /usr/local/bin/subbrute > /dev/null <<EOF
#!/usr/bin/env bash
exec "$VENVS/subbrute/bin/python3" "$TOOLS/subbrute/subbrute.py" "\$@"
EOF
sudo chmod +x /usr/local/bin/subbrute
log "subbrute installed"

# ptunnel-ng
info "ptunnel-ng..."
PTU="$TOOLS/ptunnel-ng"
[[ -d "$PTU/.git" ]] && git -C "$PTU" pull -q || \
    git clone --depth=1 -q https://github.com/utoni/ptunnel-ng "$PTU"
sudo apt-get install -y -qq automake autoconf libpcap-dev 2>/dev/null
cd "$PTU"
if sudo ./autogen.sh > /tmp/ptunnel_build.log 2>&1; then
    log "ptunnel-ng built"
else
    autoreconf -fi >> /tmp/ptunnel_build.log 2>&1
    ./configure >> /tmp/ptunnel_build.log 2>&1
    make -j"$(nproc)" >> /tmp/ptunnel_build.log 2>&1 || \
        warn "ptunnel-ng build failed — check /tmp/ptunnel_build.log"
fi
cd - > /dev/null
PTBIN=$(find "$PTU" -name "ptunnel-ng" -type f 2>/dev/null | head -1)
if [[ -n "$PTBIN" ]]; then
    sudo tee /usr/local/bin/ptunnel-ng > /dev/null <<EOF
#!/usr/bin/env bash
exec "$PTBIN" "\$@"
EOF
    sudo chmod +x /usr/local/bin/ptunnel-ng
    log "ptunnel-ng installed"
fi

# net-creds — sniff credentials from live interface or pcap file (needs root)
info "net-creds..."
NETCREDS="$TOOLS/net-creds"
[[ -d "$NETCREDS/.git" ]] && git -C "$NETCREDS" pull -q || \
    git clone --depth=1 -q https://github.com/DanMcInerney/net-creds "$NETCREDS"
python3 -m venv "$VENVS/net-creds"
"$VENVS/net-creds/bin/pip" install -q --upgrade pip setuptools scapy 2>/dev/null || true
sudo tee /usr/local/bin/net-creds > /dev/null <<EOF
#!/usr/bin/env bash
exec "$VENVS/net-creds/bin/python3" "$NETCREDS/net-creds.py" "\$@"
EOF
sudo chmod +x /usr/local/bin/net-creds
log "net-creds installed (run with sudo: sudo net-creds -i tun0)"

# reverse_shell_splunk template
[[ ! -d "$TOOLS/reverse_shell_splunk/.git" ]] && \
    git clone -q --depth=1 https://github.com/0xjpuff/reverse_shell_splunk \
        "$TOOLS/reverse_shell_splunk"
log "reverse_shell_splunk cloned"

# =============================================================================
section "7 — LINUX TRANSFER FILES"
# =============================================================================

info "Downloading linux transfer files..."

# linpeas — try new repo first, fall back to old
curl -fsSL "https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh" \
    -o "$LIN/linpeas.sh" 2>/dev/null || \
curl -fsSL "https://github.com/carlospolop/PEASS-ng/releases/latest/download/linpeas.sh" \
    -o "$LIN/linpeas.sh" 2>/dev/null || warn "linpeas.sh download failed"
[[ -f "$LIN/linpeas.sh" ]] && chmod +x "$LIN/linpeas.sh" && log "linpeas.sh"

curl -fsSL "https://raw.githubusercontent.com/rebootuser/LinEnum/master/LinEnum.sh" \
    -o "$LIN/LinEnum.sh" && chmod +x "$LIN/LinEnum.sh" && log "LinEnum.sh"

curl -fsSL "https://github.com/diego-treitos/linux-smart-enumeration/releases/latest/download/lse.sh" \
    -o "$LIN/lse.sh" && chmod +x "$LIN/lse.sh" && log "lse.sh"

curl -fsSL "https://github.com/DominicBreuker/pspy/releases/latest/download/pspy64" \
    -o "$LIN/pspy64" && chmod +x "$LIN/pspy64" && log "pspy64"
curl -fsSL "https://github.com/DominicBreuker/pspy/releases/latest/download/pspy32" \
    -o "$LIN/pspy32" && chmod +x "$LIN/pspy32" && log "pspy32"

curl -fsSL "https://github.com/andrew-d/static-binaries/raw/master/binaries/linux/x86_64/socat" \
    -o "$LIN/socat" 2>/dev/null || \
curl -fsSL "https://github.com/ernw/static-toolbox/releases/latest/download/socat" \
    -o "$LIN/socat" 2>/dev/null || warn "socat static download failed"
[[ -f "$LIN/socat" ]] && chmod +x "$LIN/socat" && log "socat (static)"

curl -fsSL "https://github.com/andrew-d/static-binaries/raw/master/binaries/linux/x86_64/ncat" \
    -o "$LIN/ncat" 2>/dev/null || warn "ncat static download failed"
[[ -f "$LIN/ncat" ]] && chmod +x "$LIN/ncat" && log "ncat (static)"

# ── Linux Privilege Escalation Exploits ──────────────────────────────────────

# logrottten — logrotate privilege escalation
curl -fsSL "https://raw.githubusercontent.com/whotwagner/logrotten/master/logrotten.c" \
    -o "$LIN/logrotten.c" && log "logrotten.c (compile on target: gcc -o logrotten logrotten.c)"

# screen 4.5.0 SUID exploit
curl -fsSL "https://www.exploit-db.com/raw/41154" \
    -o "$LIN/screen_exploit.sh" 2>/dev/null || \
curl -fsSL "https://raw.githubusercontent.com/XiphosResearch/exploits/master/screen2root/screenroot.sh" \
    -o "$LIN/screen_exploit.sh" 2>/dev/null || warn "screen_exploit.sh download failed"
[[ -f "$LIN/screen_exploit.sh" ]] && chmod +x "$LIN/screen_exploit.sh" && log "screen_exploit.sh"

# sudo-hax-me-a-sandwich — CVE-2021-3156 Baron Samedit
if [[ ! -d "$LIN/sudo-hax-me-a-sandwich/.git" ]]; then
    git clone -q --depth=1 https://github.com/blasty/CVE-2021-3156 \
        "$LIN/sudo-hax-me-a-sandwich" && log "sudo-hax-me-a-sandwich (CVE-2021-3156)"
fi

# PwnKit — CVE-2021-4034 pkexec privilege escalation
if [[ ! -d "$LIN/CVE-2021-4034/.git" ]]; then
    git clone -q --depth=1 https://github.com/ly4k/PwnKit \
        "$LIN/CVE-2021-4034" && log "CVE-2021-4034 PwnKit"
fi

# DirtyPipe — CVE-2022-0847
if [[ ! -d "$LIN/DirtyPipe/.git" ]]; then
    git clone -q --depth=1 https://github.com/AlexisAhmed/CVE-2022-0847-DirtyPipe-Exploits \
        "$LIN/DirtyPipe" && log "DirtyPipe (CVE-2022-0847)"
fi

# CVE-2021-22555 — Netfilter heap overflow (kernels 2.6-5.11)
curl -fsSL "https://raw.githubusercontent.com/google/security-research/master/pocs/linux/cve-2021-22555/exploit.c" \
    -o "$LIN/CVE-2021-22555.c" 2>/dev/null && \
    log "CVE-2021-22555.c (compile: gcc -o exploit CVE-2021-22555.c -m32 -static)"

# CVE-2022-25636 — Netfilter heap out-of-bounds write (kernels 5.4-5.6.10)
if [[ ! -d "$LIN/CVE-2022-25636/.git" ]]; then
    git clone -q --depth=1 https://github.com/Bonfee/CVE-2022-25636 \
        "$LIN/CVE-2022-25636" && log "CVE-2022-25636"
fi

# CVE-2023-32233 — Netfilter Use-After-Free (kernels up to 6.3.1)
if [[ ! -d "$LIN/CVE-2023-32233/.git" ]]; then
    git clone -q --depth=1 https://github.com/Liuk3r/CVE-2023-32233 \
        "$LIN/CVE-2023-32233" && log "CVE-2023-32233"
fi

# kubeletctl — Kubernetes Kubelet API interaction tool
KUBELET_VER=$(curl -s https://api.github.com/repos/cyberark/kubeletctl/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
KUBELET_VER="${KUBELET_VER:-v1.11}"
curl -fsSL "https://github.com/cyberark/kubeletctl/releases/download/${KUBELET_VER}/kubeletctl_linux_amd64" \
    -o "$LIN/kubeletctl" && chmod +x "$LIN/kubeletctl" && log "kubeletctl"

log "Linux transfer folder done"

# =============================================================================
section "8 — WINDOWS TRANSFER FILES"
# =============================================================================

info "Downloading windows transfer files..."

# winPEAS — try new repo first
for f in winPEASx64.exe winPEASx86.exe winPEAS.bat; do
    curl -fsSL "https://github.com/peass-ng/PEASS-ng/releases/latest/download/$f" \
        -o "$WIN/$f" 2>/dev/null || \
    curl -fsSL "https://github.com/carlospolop/PEASS-ng/releases/latest/download/$f" \
        -o "$WIN/$f" 2>/dev/null || warn "$f download failed"
done
log "winPEAS downloaded"

curl -fsSL "https://github.com/AlessandroZ/LaZagne/releases/latest/download/LaZagne.exe" \
    -o "$WIN/LaZagne.exe" && log "LaZagne.exe"

GHOSTPACK="https://github.com/r3motecontrol/Ghostpack-CompiledBinaries/raw/master"
curl -fsSL "$GHOSTPACK/Rubeus.exe"     -o "$WIN/Rubeus.exe"     && log "Rubeus.exe"
curl -fsSL "$GHOSTPACK/Seatbelt.exe"   -o "$WIN/Seatbelt.exe"   && log "Seatbelt.exe"
curl -fsSL "$GHOSTPACK/SharpDPAPI.exe" -o "$WIN/SharpDPAPI.exe" && log "SharpDPAPI.exe"

# SharpHound — copy from Kali package (most reliable), fallback to SpecterOps
if [[ -f "/usr/share/sharphound/SharpHound.exe" ]]; then
    cp /usr/share/sharphound/SharpHound.exe "$WIN/SharpHound.exe"
    cp /usr/share/sharphound/SharpHound.ps1 "$WIN/SharpHound.ps1" 2>/dev/null || true
    log "SharpHound.exe (from /usr/share/sharphound)"
else
    SH_URL=$(curl -s https://api.github.com/repos/SpecterOps/SharpHound/releases/latest \
        | grep browser_download_url | grep "windows_x86.zip" | grep -v debug \
        | head -1 | cut -d'"' -f4)
    [[ -n "$SH_URL" ]] && \
        curl -fsSL "$SH_URL" -o /tmp/sharphound.zip && \
        unzip -q -o /tmp/sharphound.zip -d /tmp/sharphound_dir && \
        find /tmp/sharphound_dir -name "SharpHound.exe" -exec mv {} "$WIN/SharpHound.exe" \; && \
        log "SharpHound.exe (from SpecterOps)"
fi

# Mimikatz
MIMI_URL=$(curl -s https://api.github.com/repos/gentilkiwi/mimikatz/releases/latest \
    | grep browser_download_url | grep "mimikatz_trunk.zip" | cut -d'"' -f4)
if [[ -n "$MIMI_URL" ]]; then
    curl -fsSL "$MIMI_URL" -o /tmp/mimikatz.zip && \
        unzip -q -o /tmp/mimikatz.zip -d "$WIN/mimikatz" && log "Mimikatz"
else
    warn "Mimikatz: GitHub API rate limited — download manually"
    warn "  https://github.com/gentilkiwi/mimikatz/releases/latest"
fi

SNAFFLER_URL=$(curl -s https://api.github.com/repos/SnaffCon/Snaffler/releases/latest \
    | grep browser_download_url | grep "Snaffler.exe" | head -1 | cut -d'"' -f4)
[[ -n "$SNAFFLER_URL" ]] && \
    curl -fsSL "$SNAFFLER_URL" -o "$WIN/Snaffler.exe" && log "Snaffler.exe"

SOCKS_URL=$(curl -s https://api.github.com/repos/nccgroup/SocksOverRDP/releases/latest \
    | grep browser_download_url | grep "SocksOverRDP-x64.zip" | cut -d'"' -f4)
[[ -n "$SOCKS_URL" ]] && \
    curl -fsSL "$SOCKS_URL" -o "$WIN/SocksOverRDP-x64.zip" && log "SocksOverRDP-x64.zip"

curl -fsSL "https://eternallybored.org/misc/netcat/netcat-win32-1.12.zip" \
    -o /tmp/nc_win.zip && \
    unzip -q -o /tmp/nc_win.zip nc64.exe -d /tmp && \
    mv /tmp/nc64.exe "$WIN/nc.exe" && log "nc.exe"

curl -fsSL "https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/master/Recon/PowerView.ps1" \
    -o "$WIN/PowerView.ps1" && log "PowerView.ps1"
curl -fsSL "https://raw.githubusercontent.com/samratashok/nishang/master/Shells/Invoke-PowerShellTcp.ps1" \
    -o "$WIN/Invoke-PowerShellTcp.ps1" && log "Invoke-PowerShellTcp.ps1"
curl -fsSL "https://the.earth.li/~sgtatham/putty/latest/w64/plink.exe" \
    -o "$WIN/plink.exe" && log "plink.exe"
curl -fsSL "https://raw.githubusercontent.com/unode/firefox_decrypt/main/firefox_decrypt.py" \
    -o "$WIN/firefox_decrypt.py" && log "firefox_decrypt.py"

[[ ! -d "$WIN/PowerHuntShares/.git" ]] && \
    git clone -q --depth=1 https://github.com/NetSPI/PowerHuntShares \
        "$WIN/PowerHuntShares" && log "PowerHuntShares"
[[ ! -d "$WIN/Invoke-DOSfuscation/.git" ]] && \
    git clone -q --depth=1 https://github.com/danielbohannon/Invoke-DOSfuscation \
        "$WIN/Invoke-DOSfuscation" && log "Invoke-DOSfuscation"

# ── Windows Privilege Escalation Tools ───────────────────────────────────────

# SharpChrome — extract Chrome/Chromium saved logins and cookies
GHOSTPACK="https://github.com/r3motecontrol/Ghostpack-CompiledBinaries/raw/master"
curl -fsSL "$GHOSTPACK/SharpChrome.exe" \
    -o "$WIN/SharpChrome.exe" 2>/dev/null && log "SharpChrome.exe"

# SessionGopher — extract PuTTY/WinSCP/FileZilla/RDP creds from registry
curl -fsSL \
    "https://raw.githubusercontent.com/Arvanaghi/SessionGopher/master/SessionGopher.ps1" \
    -o "$WIN/SessionGopher.ps1" && log "SessionGopher.ps1"

# MailSniper — search Exchange inbox for credentials
curl -fsSL \
    "https://raw.githubusercontent.com/dafthack/MailSniper/master/MailSniper.ps1" \
    -o "$WIN/MailSniper.ps1" && log "MailSniper.ps1"

# Invoke-ClipboardLogger — monitor clipboard content
curl -fsSL \
    "https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/master/Exfiltration/Invoke-ClipboardLogger.ps1" \
    -o "$WIN/Invoke-ClipboardLogger.ps1" 2>/dev/null && log "Invoke-ClipboardLogger.ps1"

# cookieextractor.py — extract Firefox cookies from SQLite
cat > "$WIN/cookieextractor.py" << 'PYEOF'
#!/usr/bin/env python3
# Firefox cookie extractor
# Usage: python3 cookieextractor.py <path_to_cookies.sqlite>
# Profile path: %APPDATA%\Mozilla\Firefox\Profiles\*.default\cookies.sqlite
import sys, sqlite3, os

def extract_cookies(db_path):
    if not os.path.exists(db_path):
        print(f"[-] File not found: {db_path}"); sys.exit(1)
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT host, name, value FROM moz_cookies")
    print(f"{'Host':<40} {'Name':<30} {'Value'}")
    print("-" * 100)
    for row in c.fetchall():
        print(f"{str(row[0]):<40} {str(row[1]):<30} {str(row[2])}")
    conn.close()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 cookieextractor.py <cookies.sqlite>"); sys.exit(1)
    extract_cookies(sys.argv[1])
PYEOF
log "cookieextractor.py"

# Invoke-SharpChromium — PowerShell wrapper for Chromium extraction
curl -fsSL \
    "https://raw.githubusercontent.com/S3cur3Th1sSh1t/PowerSharpPack/master/PowerSharpBinaries/Invoke-SharpChromium.ps1" \
    -o "$WIN/Invoke-SharpChromium.ps1" 2>/dev/null && log "Invoke-SharpChromium.ps1"

# mremoteng_decrypt — decrypt mRemoteNG saved passwords
curl -fsSL \
    "https://raw.githubusercontent.com/haseebT/mRemoteNG-Decrypt/master/mremoteng_decrypt.py" \
    -o "$WIN/mremoteng_decrypt.py" && log "mremoteng_decrypt.py"

# PSSQLite — PowerShell SQLite module (Sticky Notes, browser DBs)
[[ ! -d "$WIN/PSSQLite/.git" ]] && \
    git clone -q --depth=1 https://github.com/RamblingCookieMonster/PSSQLite \
        "$WIN/PSSQLite" && log "PSSQLite/"

# PowerUp.ps1 — service misconfigs, AlwaysInstallElevated
curl -fsSL \
    "https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/master/Privesc/PowerUp.ps1" \
    -o "$WIN/PowerUp.ps1" && log "PowerUp.ps1"

# Sherlock — find missing patches on legacy Windows
curl -fsSL \
    "https://raw.githubusercontent.com/rasta-mouse/Sherlock/master/Sherlock.ps1" \
    -o "$WIN/Sherlock.ps1" && log "Sherlock.ps1"

# Windows-Exploit-Suggester
[[ ! -d "$WIN/Windows-Exploit-Suggester/.git" ]] && \
    git clone -q --depth=1 \
        https://github.com/AonCyberLabs/Windows-Exploit-Suggester \
        "$WIN/Windows-Exploit-Suggester" && log "Windows-Exploit-Suggester/"

# Invoke-MS16-032 — Secondary Logon privesc Windows 7/Server 2008
curl -fsSL \
    "https://raw.githubusercontent.com/FuzzySecurity/PowerShell-Suite/master/Invoke-MS16-032.ps1" \
    -o "$WIN/Invoke-MS16-032.ps1" 2>/dev/null && log "Invoke-MS16-032.ps1"

# HiveNightmare — CVE-2021-36934 copy SAM/SYSTEM as unprivileged user
[[ ! -d "$WIN/HiveNightmare/.git" ]] && \
    git clone -q --depth=1 https://github.com/GossiTheDog/HiveNightmare \
        "$WIN/HiveNightmare" && log "HiveNightmare/"

# Bypass-UAC
curl -fsSL \
    "https://raw.githubusercontent.com/EmpireProject/Empire/master/data/module_source/privesc/Bypass-UAC.ps1" \
    -o "$WIN/Bypass-UAC.ps1" 2>/dev/null && log "Bypass-UAC.ps1"

log "Windows transfer folder done"

# =============================================================================
section "9 — SECLISTS & WORDLISTS"
# =============================================================================

if [[ ! -d "/usr/share/seclists" ]]; then
    info "Cloning SecLists..."
    sudo git clone -q --depth=1 https://github.com/danielmiessler/SecLists \
        /usr/share/seclists && log "SecLists → /usr/share/seclists"
else
    log "SecLists already present"
fi

# =============================================================================
section "10 — GVM/OPENVAS"
# =============================================================================

if command -v gvm-setup &>/dev/null; then
    info "Running gvm-setup (may take several minutes)..."
    sudo gvm-setup 2>/dev/null || \
        warn "gvm-setup had issues — run: sudo gvm-setup manually"
else
    warn "gvm not found — run: sudo apt install gvm && sudo gvm-setup"
fi

# =============================================================================
section "11 — PROXYCHAINS CONFIG"
# =============================================================================

PROXY_CONF="/etc/proxychains4.conf"
[[ -f "$PROXY_CONF" ]] && \
    sudo sed -i 's/^#quiet_mode/quiet_mode/' "$PROXY_CONF" && \
    log "proxychains4 quiet_mode enabled"

# =============================================================================
section "12 — FINAL PERMISSIONS"
# =============================================================================

sudo chmod +x /usr/local/bin/* 2>/dev/null || true

# =============================================================================
section "DONE"
# =============================================================================

echo ""
log "══════════════════════════════════════════════════════"
log " Setup complete!"
log ""
log " Next steps:"
log "   1. cat cpts_zshrc.zsh >> ~/.zshrc && source ~/.zshrc"
log "   2. bash deep_verify.sh 2>&1 | tee ~/deep_verify.log"
log "   3. grep 'FAIL' ~/deep_verify.log"
log ""
log " Manual steps:"
log "   Nessus  : https://www.tenable.com/downloads/nessus"
log "             sudo dpkg -i Nessus-*.deb"
log "             sudo systemctl start nessusd"
log "             Browse: https://localhost:8834"
log "   Shodan  : shodan init <YOUR_API_KEY>"
log "   GVM     : sudo gvm-start"
log "   Ligolo  : ligolo-setup  (alias — creates tun interface)"
log "══════════════════════════════════════════════════════"
echo ""
echo "Windows transfer ($WIN):"
ls "$WIN" | column
echo ""
echo "Linux transfer ($LIN):"
ls "$LIN" | column
