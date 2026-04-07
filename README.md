# CPTS Kali Linux Tool Setup

Tested on Kali 2026.1 (Python 3.13, kernel 6.x)

## Files

| File | Purpose |
|------|---------|
| `setup.sh` | Main installer — run this first |
| `cpts_zshrc.zsh` | Shell config — append to ~/.zshrc |
| `deep_verify.sh` | Functional verification — run after setup |

## Usage

### Fresh Kali install

```bash
# Clone your repo
git clone https://github.com/YOU/kali-cpts-setup
cd kali-cpts-setup

# Run setup (takes 15-30 mins depending on connection)
chmod +x setup.sh deep_verify.sh
./setup.sh 2>&1 | tee ~/setup.log

# Add shell config
cat cpts_zshrc.zsh >> ~/.zshrc && source ~/.zshrc

# Verify everything works
bash deep_verify.sh 2>&1 | tee ~/deep_verify.log
grep "FAIL" ~/deep_verify.log
```

### Expected verify results
- PASS: All tools
- SKIP: Nessus, OpenVAS/GVM, BloodHound GUI, Shodan API key (manual steps)
- WARN: odat (needs Oracle Instant Client), mimipenguin (needs root + live system)

## Manual steps after setup

### Nessus (commercial vuln scanner)
```bash
# Download from https://www.tenable.com/downloads/nessus
sudo dpkg -i Nessus-*.deb
sudo systemctl start nessusd
# Browse to https://localhost:8834
```

### Shodan CLI
```bash
shodan init <YOUR_API_KEY>
```

### GVM/OpenVAS
```bash
sudo gvm-start
# Browse to https://127.0.0.1:9392
```

### BloodHound
```bash
bloodhound-start   # alias in cpts_zshrc.zsh
# Default creds: neo4j:neo4j (change on first login)
```

### Ligolo-ng TUN interface (run once per boot)
```bash
ligolo-setup   # alias in cpts_zshrc.zsh
```

### odat (Oracle attack tool)
Requires Oracle Instant Client:
https://oracle.github.io/odpi/doc/installation.html

## Transfer folders
After setup, two folders are ready to serve:

```bash
# Serve windows tools to a target
serve-win   # alias — starts HTTP server on :8080

# Serve linux tools to a target  
serve-lin   # alias — starts HTTP server on :8080
```

### ~/tools/transfer/windows/
- winPEASx64.exe / winPEASx86.exe / winPEAS.bat
- Mimikatz (folder)
- Rubeus.exe, Seatbelt.exe, SharpDPAPI.exe, SharpHound.exe
- LaZagne.exe, Snaffler.exe
- chisel.exe, ligolo-agent.exe, nc.exe, plink.exe
- PowerView.ps1, Invoke-PowerShellTcp.ps1, SharpHound.ps1
- firefox_decrypt.py
- SocksOverRDP-x64.zip
- PowerHuntShares/, dnscat2-powershell/, Invoke-DOSfuscation/

### ~/tools/transfer/linux/
- linpeas.sh, LinEnum.sh, lse.sh
- pspy64, pspy32
- chisel, ligolo-agent
- socat (static), ncat (static)

## Key aliases (from cpts_zshrc.zsh)

| Alias | Does |
|-------|------|
| `serve-win` | HTTP server for windows transfer folder |
| `serve-lin` | HTTP server for linux transfer folder |
| `serve-here` | HTTP server in current directory |
| `listen <port>` | nc listener |
| `myip` | Show tun0 IP |
| `revshell <ip> <port>` | Print reverse shell one-liners |
| `upgrade-shell` | Print TTY upgrade commands |
| `ligolo-setup` | Create ligolo tun interface |
| `bloodhound-start` | Start neo4j + bloodhound |
| `nxc` / `cme` | NetExec |
| `secretsdump` | impacket-secretsdump |
| `pc` | proxychains4 -q |
| `rscan <ip>` | RustScan → nmap pipeline |
