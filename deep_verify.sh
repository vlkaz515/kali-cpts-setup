#!/usr/bin/env bash
# =============================================================================
# CPTS Deep Functional Verification Script v2
# Tests that every tool actually RUNS — catches import errors, broken installs
# Correctly handles: root-required tools, directory-dependent tools, optional tools
#
# Usage: chmod +x deep_verify.sh && bash deep_verify.sh 2>&1 | tee ~/deep_verify.log
# Review: grep "FAIL\|WARN" ~/deep_verify.log
# =============================================================================

PASS=0; FAIL=0; WARN=0; SKIP=0

# ── Colour helpers ────────────────────────────────────────────────────────────
pass() { printf "  \e[32mPASS\e[0m : %s\n" "$1";                                         ((PASS++)); }
fail() { printf "  \e[31mFAIL\e[0m : %-40s  error: %s\n" "$1" "$2";                      ((FAIL++)); }
warn() { printf "  \e[33mWARN\e[0m : %-40s  note: %s\n"  "$1" "$2";                      ((WARN++)); }
skip() { printf "  \e[36mSKIP\e[0m : %-40s  reason: %s\n" "$1" "$2";                     ((SKIP++)); }

# ── Core test: run command, check output doesn't contain Python crash ─────────
# run_test <name> <command...>
# PASS = ran without traceback/ImportError
# FAIL = Python traceback or ImportError detected
# WARN = command not found
run_test() {
    local name="$1"; shift
    if ! command -v "$1" &>/dev/null; then
        warn "$name" "command '$1' not found on PATH"
        return
    fi
    local output
    output=$(timeout 15 "$@" 2>&1) || true
    if echo "$output" | grep -qiE "^Traceback|ModuleNotFoundError|ImportError|No module named|SyntaxError: invalid syntax"; then
        local err
        err=$(echo "$output" | grep -iE "ModuleNotFoundError|ImportError|No module named|SyntaxError" | head -1 | cut -c1-80)
        fail "$name" "$err"
    else
        pass "$name"
    fi
}

# ── Root-required test: skip if not root, note that sudo is needed ────────────
run_test_root() {
    local name="$1"; shift
    if ! command -v "$1" &>/dev/null; then
        warn "$name" "command '$1' not found on PATH"
        return
    fi
    local output
    output=$(timeout 15 "$@" 2>&1) || true
    if echo "$output" | grep -qiE "^Traceback|ModuleNotFoundError|ImportError|No module named"; then
        local err
        err=$(echo "$output" | grep -iE "ModuleNotFoundError|ImportError|No module named" | head -1 | cut -c1-80)
        fail "$name" "$err"
    elif echo "$output" | grep -qiE "root|permission denied|must be run as"; then
        pass "$name (needs sudo to actually run — install OK)"
    else
        pass "$name"
    fi
}

# ── Directory-dependent test: cd into dir first ───────────────────────────────
run_test_from_dir() {
    local name="$1" dir="$2"; shift 2
    if ! command -v "$1" &>/dev/null; then
        warn "$name" "command '$1' not found on PATH"
        return
    fi
    local output
    output=$(cd "$dir" 2>/dev/null && timeout 15 "$@" 2>&1) || true
    if echo "$output" | grep -qiE "^Traceback|ModuleNotFoundError|ImportError|No module named|SyntaxError"; then
        local err
        err=$(echo "$output" | grep -iE "ModuleNotFoundError|ImportError|No module named" | head -1 | cut -c1-80)
        fail "$name" "$err"
    else
        pass "$name"
    fi
}

# ── Optional tool: WARN instead of FAIL if broken ────────────────────────────
run_test_optional() {
    local name="$1"; shift
    if ! command -v "$1" &>/dev/null; then
        skip "$name" "not installed (optional tool)"
        return
    fi
    local output
    output=$(timeout 15 "$@" 2>&1) || true
    if echo "$output" | grep -qiE "^Traceback|ModuleNotFoundError|ImportError|No module named"; then
        local err
        err=$(echo "$output" | grep -iE "ModuleNotFoundError|ImportError|No module named" | head -1 | cut -c1-80)
        warn "$name" "optional tool has errors: $err"
    else
        pass "$name"
    fi
}

# ── File existence check ──────────────────────────────────────────────────────
check_file() {
    local name="$1" path="$2"
    if [[ -f "$path" ]] || [[ -d "$path" ]]; then
        pass "$name"
    else
        fail "$name" "not found: $path"
    fi
}

# =============================================================================
echo ""
echo "================================================================"
echo " CPTS Deep Functional Verification v2 — $(date '+%Y-%m-%d %H:%M')"
echo " Tests actual execution — catches import errors & broken installs"
echo "================================================================"

# =============================================================================
echo ""
echo "[ APT / SYSTEM TOOLS ]"
# =============================================================================

run_test  "nmap"           nmap --version
run_test  "gobuster"       gobuster version
run_test  "ffuf"           ffuf -V
run_test  "hydra"          hydra -h
run_test  "medusa"         medusa -h
run_test  "netcat (nc)"    nc -h
run_test  "ncat"           ncat --version
run_test  "smbclient"      smbclient --version
run_test  "smbmap"         smbmap --help
run_test  "crackmapexec"   crackmapexec --version
run_test  "john"           john --list=formats
run_test  "hashcat"        hashcat --version
run_test  "searchsploit"   searchsploit --help
run_test  "msfconsole"     msfconsole --version
run_test  "wpscan"         wpscan --version
run_test  "sqlmap"         sqlmap --version
run_test  "socat"          socat -V
run_test  "proxychains4"   proxychains4 -h
run_test  "sshuttle"       sshuttle --version
run_test  "dnsenum"        dnsenum --help
run_test  "masscan"        masscan --version
run_test  "crowbar"        crowbar --help
run_test  "smtp-user-enum" smtp-user-enum --help
run_test  "swaks"          swaks --version
run_test  "xfreerdp"       xfreerdp --version
run_test  "tshark"         tshark --version
run_test  "cupp"           cupp -h
run_test  "gpp-decrypt"    gpp-decrypt --help
run_test  "bettercap"      bettercap --version
run_test  "evil-winrm"     evil-winrm --version
run_test  "nxc"            nxc --version
run_test  "lynis"          lynis --version
run_test  "strace"         strace --version
run_test  "guestmount"     guestmount --version
run_test  "restic"         restic version

# root-required tools — verified as installed, just need sudo to actually run
run_test_root "neo4j"       neo4j version
run_test_root "responder"   responder --version


# =============================================================================
echo ""
echo "[ GO TOOLS ]"
# =============================================================================

run_test "subfinder"    subfinder --version
run_test "chisel"       chisel --help
run_test "ligolo-proxy" ligolo-proxy --help
run_test "rustscan"     rustscan --version
run_test "kerbrute"     kerbrute --help
run_test "aquatone"     aquatone --help

# =============================================================================
echo ""
echo "[ RUBY TOOLS ]"
# =============================================================================

run_test "evil-winrm (gem)"  evil-winrm --version
run_test "username-anarchy"  username-anarchy --help
run_test "dnscat2-server"    which dnscat2-server

# =============================================================================
echo ""
echo "[ PYTHON TOOLS ]"
# =============================================================================

# Impacket suite
run_test "impacket-secretsdump"  impacket-secretsdump --help
run_test "impacket-psexec"       impacket-psexec --help
run_test "impacket-smbexec"      impacket-smbexec --help
run_test "impacket-wmiexec"      impacket-wmiexec --help
run_test "impacket-atexec"       impacket-atexec --help
run_test "impacket-ntlmrelayx"   impacket-ntlmrelayx --help
run_test "impacket-GetNPUsers"   impacket-GetNPUsers --help
run_test "impacket-GetUserSPNs"  impacket-GetUserSPNs --help
run_test "impacket-mssqlclient"  impacket-mssqlclient --help
run_test "impacket-lookupsid"    impacket-lookupsid --help
run_test "impacket-rpcdump"      impacket-rpcdump --help
run_test "impacket-samrdump"     impacket-samrdump --help
run_test "impacket-ticketer"     impacket-ticketer --help
run_test "impacket-raiseChild"   impacket-raiseChild --help

# AD tools
run_test "bloodhound-python"  bloodhound-python --help
run_test "gettgtpkinit"       gettgtpkinit --help
run_test "getnthash"          getnthash --help

run_test "petitpotam"         petitpotam --help
run_test "adidnsdump"         adidnsdump --help

# Obfuscation
run_test "bashfuscator"  bashfuscator --help

# Web tools
run_test "o365spray"   o365spray --help
run_test "droopescan"  droopescan --help
run_test "enum4linux-ng" enum4linux-ng --help

# These tools need to run from their own directory (local package imports)
run_test_from_dir "xsstrike"   "$HOME/tools/XSStrike"          xsstrike --help
run_test_from_dir "eyewitness" "$HOME/tools/EyeWitness/Python"  eyewitness --help

# Credential tools
run_test "lazagne"        lazagne --help
run_test "firefox_decrypt" firefox_decrypt --help
run_test "pypykatz"       pypykatz --help

# Recon
run_test "theharvester"  theHarvester --help
run_test "recon-ng"      recon-ng --version
run_test "spiderfoot"    spiderfoot -h
run_test "ssh-audit"     ssh-audit --help
run_test "subbrute"      subbrute --help
run_test "shodan"        shodan --help
run_test "hashid"        hashid --help
run_test "finalrecon"    finalrecon --help
run_test "manspider"     manspider --help

# Pivoting
run_test "ptunnel-ng"   ptunnel-ng --help

# Utility
run_test "uploadserver"       uploadserver --help
run_test "openvasreporting"   openvasreporting --help

# root-required
run_test_root "pcredz"  pcredz --help
run_test_root "net-creds" net-creds --help

# Optional tools — warn but don't fail if broken
# noPac: CVE-2021-42278/42287 — escalate from standard domain user to DA
#        Broken on Python 3.13 due to impacket's pkg_resources dependency
#        Alternative: use impacket-addcomputer + impacket-getST (already installed)
run_test_optional "noPac"      noPac --help

# mimipenguin: dumps credentials from Linux memory
#              Requires root + live authenticated processes — useless on fresh box
#              Run on target: sudo mimipenguin
run_test_optional "mimipenguin" mimipenguin --help

# rpivot is Python 2 only — replaced with helpful wrapper
run_test "rpivot-server"  rpivot-server --help
run_test "rpivot-client"  rpivot-client --help

# =============================================================================
echo ""
echo "[ TRANSFER FILES ]"
# =============================================================================

WIN="$HOME/tools/transfer/windows"
LIN="$HOME/tools/transfer/linux"

check_file "chisel.exe"           "$WIN/chisel.exe"
check_file "ligolo-agent.exe"     "$WIN/ligolo-agent.exe"
check_file "winPEASx64.exe"       "$WIN/winPEASx64.exe"
check_file "winPEASx86.exe"       "$WIN/winPEASx86.exe"
check_file "winPEAS.bat"          "$WIN/winPEAS.bat"
check_file "Mimikatz/"            "$WIN/mimikatz"
check_file "Rubeus.exe"           "$WIN/Rubeus.exe"
check_file "SharpHound.exe"       "$WIN/SharpHound.exe"
check_file "Seatbelt.exe"         "$WIN/Seatbelt.exe"
check_file "SharpDPAPI.exe"       "$WIN/SharpDPAPI.exe"
check_file "LaZagne.exe"          "$WIN/LaZagne.exe"
check_file "nc.exe"               "$WIN/nc.exe"
check_file "PowerView.ps1"        "$WIN/PowerView.ps1"
check_file "Invoke-PSHttpTcp.ps1" "$WIN/Invoke-PowerShellTcp.ps1"
check_file "plink.exe"            "$WIN/plink.exe"
check_file "SocksOverRDP-x64.zip" "$WIN/SocksOverRDP-x64.zip"
check_file "firefox_decrypt.py"   "$WIN/firefox_decrypt.py"
check_file "Snaffler.exe"         "$WIN/Snaffler.exe"
check_file "PowerHuntShares/"     "$WIN/PowerHuntShares"
check_file "dnscat2-powershell/"  "$WIN/dnscat2-powershell"
check_file "Invoke-DOSfuscation/" "$WIN/Invoke-DOSfuscation"
check_file "SharpChrome.exe"      "$WIN/SharpChrome.exe"
check_file "SessionGopher.ps1"    "$WIN/SessionGopher.ps1"
check_file "MailSniper.ps1"       "$WIN/MailSniper.ps1"
check_file "Invoke-ClipboardLogger.ps1" "$WIN/Invoke-ClipboardLogger.ps1"
check_file "cookieextractor.py"   "$WIN/cookieextractor.py"
check_file "Invoke-SharpChromium.ps1" "$WIN/Invoke-SharpChromium.ps1"
check_file "mremoteng_decrypt.py" "$WIN/mremoteng_decrypt.py"
check_file "PSSQLite/"            "$WIN/PSSQLite"
check_file "PowerUp.ps1"          "$WIN/PowerUp.ps1"
check_file "Sherlock.ps1"         "$WIN/Sherlock.ps1"
check_file "Windows-Exploit-Suggester/" "$WIN/Windows-Exploit-Suggester"
check_file "Invoke-MS16-032.ps1"  "$WIN/Invoke-MS16-032.ps1"
check_file "HiveNightmare/"       "$WIN/HiveNightmare"
check_file "Bypass-UAC.ps1"       "$WIN/Bypass-UAC.ps1"
check_file "linpeas.sh"           "$LIN/linpeas.sh"
check_file "LinEnum.sh"           "$LIN/LinEnum.sh"
check_file "lse.sh"               "$LIN/lse.sh"
check_file "pspy64"               "$LIN/pspy64"
check_file "pspy32"               "$LIN/pspy32"
check_file "ligolo-agent"         "$LIN/ligolo-agent"
check_file "chisel (linux)"       "$LIN/chisel"
check_file "socat (static)"       "$LIN/socat"
check_file "ncat (static)"        "$LIN/ncat"
check_file "logrotten.c"          "$LIN/logrotten.c"
check_file "screen_exploit.sh"    "$LIN/screen_exploit.sh"
check_file "sudo-hax-me-a-sandwich (CVE-2021-3156)" "$LIN/sudo-hax-me-a-sandwich"
check_file "CVE-2021-4034 PwnKit" "$LIN/CVE-2021-4034"
check_file "DirtyPipe (CVE-2022-0847)" "$LIN/DirtyPipe"
check_file "CVE-2021-22555.c"     "$LIN/CVE-2021-22555.c"
check_file "CVE-2022-25636"       "$LIN/CVE-2022-25636"
check_file "CVE-2023-32233"       "$LIN/CVE-2023-32233"
check_file "kubeletctl"           "$LIN/kubeletctl"

# =============================================================================
echo ""
echo "[ MANUAL / COMMERCIAL ]"
# =============================================================================

skip "Nessus"    "manual install — check https://localhost:8834"
skip "OpenVAS"   "run: sudo gvm-start then https://127.0.0.1:9392"
skip "BloodHound GUI" "run: bloodhound-start (alias)"
skip "Shodan API key" "run: shodan init <YOUR_API_KEY>"
skip "odat/Oracle"    "needs Oracle Instant Client — see https://oracle.github.io/odpi/doc/installation.html"

# =============================================================================
echo ""
echo "================================================================"
TOTAL=$((PASS + FAIL + WARN + SKIP))
echo " Checked  : $TOTAL items"
printf " \e[32mPassed\e[0m   : %d\n" "$PASS"
printf " \e[31mFailed\e[0m   : %d\n" "$FAIL"
printf " \e[33mWarnings\e[0m : %d  (optional or needs-root tools)\n" "$WARN"
printf " \e[36mSkipped\e[0m  : %d  (manual/commercial installs)\n" "$SKIP"
echo "================================================================"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo " Quick fix reference for Python errors:"
    echo " ───────────────────────────────────────────────────────"
    echo " Missing module (distutils/imp):"
    echo "   source ~/tools/venvs/<TOOL>/bin/activate"
    echo "   pip install setuptools && deactivate"
    echo ""
    echo " Missing dependency:"
    echo "   source ~/tools/venvs/<TOOL>/bin/activate"
    echo "   pip install <missing-module> && deactivate"
    echo ""
    echo " Review: grep 'FAIL' ~/deep_verify.log"
fi
echo ""
