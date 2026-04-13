#!/usr/bin/env bash
# =============================================================================
# CPTS Patch — Windows Privilege Escalation Module
# Adds tools from sections 21-31 of the Windows PrivEsc module
# Run on existing installs to bring them up to date
# Usage: chmod +x patch_winprivesc.sh && ./patch_winprivesc.sh
# =============================================================================

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()     { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
info()    { echo -e "${CYAN}[*]${NC} $*"; }
section() { echo -e "\n${BOLD}${CYAN}══════ $* ══════${NC}\n"; }

WIN="$HOME/tools/transfer/windows"
mkdir -p "$WIN"

# =============================================================================
section "1 — APT TOOLS"
# =============================================================================

info "Installing guestmount and restic..."
sudo apt-get install -y -qq libguestfs-tools restic 2>/dev/null
command -v guestmount &>/dev/null && \
    log "guestmount installed (mount VMDK/VHDX for offline hash extraction)" || \
    warn "guestmount failed — try: sudo apt install libguestfs-tools"
command -v restic &>/dev/null && \
    log "restic installed (backup tool — can restore SAM/NTDS from snapshots)" || \
    warn "restic failed"

# keepass2john is part of john — verify it's present
find /usr -name "keepass2john*" 2>/dev/null | head -1 | grep -q "keepass2john" && \
    log "keepass2john already present (part of john package)" || \
    warn "keepass2john not found — check john install"

# =============================================================================
section "2 — WINDOWS TRANSFER FILES"
# =============================================================================

# SharpChrome — extract Chrome/Chromium saved logins and cookies
info "SharpChrome..."
GHOSTPACK="https://github.com/r3motecontrol/Ghostpack-CompiledBinaries/raw/master"
curl -fsSL "$GHOSTPACK/SharpChrome.exe" \
    -o "$WIN/SharpChrome.exe" 2>/dev/null && \
    log "SharpChrome.exe (extract Chrome saved logins/cookies)" || \
    warn "SharpChrome.exe: not in Ghostpack compiled binaries — may need manual compile"

# SessionGopher — extract PuTTY/WinSCP/FileZilla/RDP creds from registry
info "SessionGopher..."
curl -fsSL \
    "https://raw.githubusercontent.com/Arvanaghi/SessionGopher/master/SessionGopher.ps1" \
    -o "$WIN/SessionGopher.ps1" && \
    log "SessionGopher.ps1 (extract saved PuTTY/WinSCP/FileZilla/RDP credentials)"

# MailSnipper — search Exchange inbox for credentials
info "MailSnipper..."
curl -fsSL \
    "https://raw.githubusercontent.com/dafthack/MailSniper/master/MailSniper.ps1" \
    -o "$WIN/MailSniper.ps1" && \
    log "MailSniper.ps1 (search Exchange inbox for credentials/sensitive data)"

# Invoke-ClipboardLogger — monitor clipboard content
info "Invoke-ClipboardLogger..."
curl -fsSL \
    "https://raw.githubusercontent.com/EmpireProject/Empire/master/data/module_source/collection/Invoke-ClipboardLogger.ps1" \
    -o "$WIN/Invoke-ClipboardLogger.ps1" 2>/dev/null || \
curl -fsSL \
    "https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/master/Exfiltration/Invoke-ClipboardLogger.ps1" \
    -o "$WIN/Invoke-ClipboardLogger.ps1" 2>/dev/null && \
    log "Invoke-ClipboardLogger.ps1 (monitor/capture clipboard content)"

# cookieextractor.py — extract Firefox cookies from SQLite
info "cookieextractor.py..."
curl -fsSL \
    "https://raw.githubusercontent.com/Georgetown-University-Libraries/File-Analyzer/master/demo/src/main/edu/georgetown/library/fileAnalyzer/demo/cookieextractor.py" \
    -o "$WIN/cookieextractor.py" 2>/dev/null || \
# Fallback — write a functional Firefox cookie extractor directly
cat > "$WIN/cookieextractor.py" << 'PYEOF'
#!/usr/bin/env python3
# Firefox cookie extractor — reads cookies.sqlite from Firefox profile
# Usage: python3 cookieextractor.py <path_to_cookies.sqlite>
import sys
import sqlite3
import os

def extract_cookies(db_path):
    if not os.path.exists(db_path):
        print(f"[-] File not found: {db_path}")
        sys.exit(1)
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("SELECT host, name, value, path, expiry, isSecure, isHttpOnly FROM moz_cookies")
    print(f"{'Host':<40} {'Name':<30} {'Value':<50}")
    print("-" * 120)
    for row in c.fetchall():
        print(f"{str(row[0]):<40} {str(row[1]):<30} {str(row[2]):<50}")
    conn.close()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 cookieextractor.py <cookies.sqlite>")
        print("Firefox profile: %APPDATA%\\Mozilla\\Firefox\\Profiles\\*.default\\cookies.sqlite")
        sys.exit(1)
    extract_cookies(sys.argv[1])
PYEOF
log "cookieextractor.py (extract Firefox cookies from SQLite database)"

# Invoke-SharpChromium — PowerShell wrapper for Chromium cookie/cred extraction
info "Invoke-SharpChromium..."
curl -fsSL \
    "https://raw.githubusercontent.com/S3cur3Th1sSh1t/PowerSharpPack/master/PowerSharpBinaries/Invoke-SharpChromium.ps1" \
    -o "$WIN/Invoke-SharpChromium.ps1" 2>/dev/null && \
    log "Invoke-SharpChromium.ps1 (PowerShell wrapper to extract/decrypt Chromium creds)"

# mremoteng_decrypt — decrypt mRemoteNG saved passwords
info "mremoteng_decrypt.py..."
curl -fsSL \
    "https://raw.githubusercontent.com/haseebT/mRemoteNG-Decrypt/master/mremoteng_decrypt.py" \
    -o "$WIN/mremoteng_decrypt.py" && \
    log "mremoteng_decrypt.py (decrypt mRemoteNG saved connection passwords)"

# PSSQLite — PowerShell SQLite module (for Sticky Notes extraction)
info "PSSQLite..."
if [[ ! -d "$WIN/PSSQLite/.git" ]]; then
    git clone -q --depth=1 https://github.com/RamblingCookieMonster/PSSQLite \
        "$WIN/PSSQLite" && \
        log "PSSQLite/ (PowerShell SQLite module — query Sticky Notes, browser DBs)"
fi

# PowerUp.ps1 — find service misconfigs, AlwaysInstallElevated, etc.
info "PowerUp.ps1..."
curl -fsSL \
    "https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/master/Privesc/PowerUp.ps1" \
    -o "$WIN/PowerUp.ps1" && \
    log "PowerUp.ps1 (service misconfigs, AlwaysInstallElevated, Write-UserAddMSI)"

# Sherlock — find missing patches on legacy Windows (Server 2008, Win7)
info "Sherlock.ps1..."
curl -fsSL \
    "https://raw.githubusercontent.com/rasta-mouse/Sherlock/master/Sherlock.ps1" \
    -o "$WIN/Sherlock.ps1" && \
    log "Sherlock.ps1 (find missing patches on legacy Windows/Server 2008)"

# Windows-Exploit-Suggester — cross-reference systeminfo vs MS vuln DB
info "Windows-Exploit-Suggester..."
if [[ ! -d "$WIN/Windows-Exploit-Suggester/.git" ]]; then
    git clone -q --depth=1 \
        https://github.com/AonCyberLabs/Windows-Exploit-Suggester \
        "$WIN/Windows-Exploit-Suggester" && \
        log "Windows-Exploit-Suggester (takes systeminfo output → suggests exploits)"
fi

# Invoke-MS16-032 — Secondary Logon privesc (Windows 7 / Server 2008)
info "Invoke-MS16-032.ps1..."
curl -fsSL \
    "https://raw.githubusercontent.com/EmpireProject/Empire/master/data/module_source/privesc/Invoke-MS16032.ps1" \
    -o "$WIN/Invoke-MS16-032.ps1" 2>/dev/null || \
curl -fsSL \
    "https://raw.githubusercontent.com/FuzzySecurity/PowerShell-Suite/master/Invoke-MS16-032.ps1" \
    -o "$WIN/Invoke-MS16-032.ps1" 2>/dev/null && \
    log "Invoke-MS16-032.ps1 (Secondary Logon privesc — Windows 7/Server 2008)"

# HiveNightmare / SeriousSAM — CVE-2021-36934
info "HiveNightmare (CVE-2021-36934)..."
if [[ ! -d "$WIN/HiveNightmare/.git" ]]; then
    git clone -q --depth=1 https://github.com/GossiTheDog/HiveNightmare \
        "$WIN/HiveNightmare" && \
        log "HiveNightmare/ (CVE-2021-36934 — copy SAM/SYSTEM as unprivileged user)"
fi
# Also grab the standalone exe if available
HIVENIGHTMARE_URL=$(curl -s https://api.github.com/repos/GossiTheDog/HiveNightmare/releases/latest \
    | grep browser_download_url | grep ".exe" | head -1 | cut -d'"' -f4)
[[ -n "$HIVENIGHTMARE_URL" ]] && \
    curl -fsSL "$HIVENIGHTMARE_URL" -o "$WIN/HiveNightmare.exe" && \
    log "HiveNightmare.exe downloaded"

# Bypass-UAC scripts — from Empire/UACME
info "Bypass-UAC scripts..."
curl -fsSL \
    "https://raw.githubusercontent.com/EmpireProject/Empire/master/data/module_source/privesc/Bypass-UAC.ps1" \
    -o "$WIN/Bypass-UAC.ps1" 2>/dev/null && \
    log "Bypass-UAC.ps1 (UAC bypass for post-exploitation)"

# net-creds — sniff credentials from interface or pcap
info "net-creds..."
NET_CREDS="$HOME/tools/net-creds"
if [[ ! -d "$NET_CREDS/.git" ]]; then
    git clone -q --depth=1 https://github.com/DanMcInerney/net-creds "$NET_CREDS"
fi
# Install deps in venv
python3 -m venv "$HOME/tools/venvs/net-creds"
"$HOME/tools/venvs/net-creds/bin/pip" install -q --upgrade pip setuptools scapy 2>/dev/null
sudo tee /usr/local/bin/net-creds > /dev/null <<EOF
#!/usr/bin/env bash
exec "$HOME/tools/venvs/net-creds/bin/python3" "$NET_CREDS/net-creds.py" "\$@"
EOF
sudo chmod +x /usr/local/bin/net-creds
log "net-creds installed (sniff credentials from live interface or pcap)"

# Explorer++ portable — already a browser download, note it
warn "Explorer++: download portable binary manually from https://explorerplusplus.com/download"
warn "  Place in $WIN/ExplorerPlusPlus.exe for transfer to restricted targets"

# =============================================================================
section "DONE"
# =============================================================================

echo ""
log "Windows transfer folder additions:"
ls "$WIN" | column
echo ""
log "Kali tools added: guestmount, restic, net-creds"
log "Update your GitHub repo with the new setup.sh and deep_verify.sh"
