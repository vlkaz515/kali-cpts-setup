#!/usr/bin/env bash
# =============================================================================
# CPTS Patch — Linux Privilege Escalation Module
# Adds tools missing from previous setup versions
# Run on existing installs to bring them up to date
# Usage: chmod +x patch_linprivesc.sh && ./patch_linprivesc.sh
# =============================================================================

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log()     { echo -e "${GREEN}[+]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
info()    { echo -e "${CYAN}[*]${NC} $*"; }
section() { echo -e "\n${BOLD}${CYAN}══════ $* ══════${NC}\n"; }

LIN="$HOME/tools/transfer/linux"
mkdir -p "$LIN"

# =============================================================================
section "1 — APT TOOLS"
# =============================================================================

info "Installing lynis and strace..."
sudo apt-get install -y -qq lynis strace 2>/dev/null
command -v lynis  &>/dev/null && log "lynis installed"   || warn "lynis failed"
command -v strace &>/dev/null && log "strace installed"  || warn "strace failed"

# =============================================================================
section "2 — LINUX TRANSFER EXPLOITS"
# =============================================================================

# logrotten — logrotate privilege escalation
info "logrotten..."
curl -fsSL "https://raw.githubusercontent.com/whotwagner/logrotten/master/logrotten.c" \
    -o "$LIN/logrotten.c" && log "logrotten.c (compile on target: gcc -o logrotten logrotten.c)"

# screen 4.5.0 SUID exploit
info "screen_exploit.sh..."
curl -fsSL "https://www.exploit-db.com/raw/41154" \
    -o "$LIN/screen_exploit.sh" 2>/dev/null || \
curl -fsSL "https://raw.githubusercontent.com/XiphosResearch/exploits/master/screen2root/screenroot.sh" \
    -o "$LIN/screen_exploit.sh" 2>/dev/null || warn "screen_exploit.sh download failed"
[[ -f "$LIN/screen_exploit.sh" ]] && chmod +x "$LIN/screen_exploit.sh" && \
    log "screen_exploit.sh (Screen 4.5.0 SUID → root)"

# sudo-hax-me-a-sandwich — CVE-2021-3156 Baron Samedit
info "CVE-2021-3156 (Baron Samedit / sudo-hax-me-a-sandwich)..."
if [[ ! -d "$LIN/sudo-hax-me-a-sandwich/.git" ]]; then
    git clone -q --depth=1 https://github.com/blasty/CVE-2021-3156 \
        "$LIN/sudo-hax-me-a-sandwich" && \
        log "sudo-hax-me-a-sandwich (CVE-2021-3156 heap overflow in sudo → root)"
else
    git -C "$LIN/sudo-hax-me-a-sandwich" pull -q && log "sudo-hax-me-a-sandwich updated"
fi

# PwnKit — CVE-2021-4034
info "CVE-2021-4034 (PwnKit)..."
if [[ ! -d "$LIN/CVE-2021-4034/.git" ]]; then
    git clone -q --depth=1 https://github.com/ly4k/PwnKit \
        "$LIN/CVE-2021-4034" && \
        log "CVE-2021-4034 PwnKit (pkexec memory corruption → root)"
else
    git -C "$LIN/CVE-2021-4034" pull -q && log "CVE-2021-4034 updated"
fi

# DirtyPipe — CVE-2022-0847
info "CVE-2022-0847 (DirtyPipe)..."
if [[ ! -d "$LIN/DirtyPipe/.git" ]]; then
    git clone -q --depth=1 \
        https://github.com/AlexisAhmed/CVE-2022-0847-DirtyPipe-Exploits \
        "$LIN/DirtyPipe" && \
        log "DirtyPipe CVE-2022-0847 (write to read-only pipe → root, 2 PoCs)"
else
    git -C "$LIN/DirtyPipe" pull -q && log "DirtyPipe updated"
fi

# CVE-2021-22555 — Netfilter heap overflow kernels 2.6-5.11
info "CVE-2021-22555 (Netfilter heap overflow)..."
curl -fsSL \
    "https://raw.githubusercontent.com/google/security-research/master/pocs/linux/cve-2021-22555/exploit.c" \
    -o "$LIN/CVE-2021-22555.c" 2>/dev/null && \
    log "CVE-2021-22555.c (kernels 2.6-5.11, compile: gcc -o exploit CVE-2021-22555.c -m32 -static)"

# CVE-2022-25636 — Netfilter OOB write kernels 5.4-5.6.10
info "CVE-2022-25636 (Netfilter OOB write)..."
if [[ ! -d "$LIN/CVE-2022-25636/.git" ]]; then
    git clone -q --depth=1 https://github.com/Bonfee/CVE-2022-25636 \
        "$LIN/CVE-2022-25636" && \
        log "CVE-2022-25636 (kernels 5.4-5.6.10 Netfilter OOB write → root)"
else
    git -C "$LIN/CVE-2022-25636" pull -q && log "CVE-2022-25636 updated"
fi

# CVE-2023-32233 — Netfilter Use-After-Free kernels up to 6.3.1
info "CVE-2023-32233 (Netfilter UAF)..."
if [[ ! -d "$LIN/CVE-2023-32233/.git" ]]; then
    git clone -q --depth=1 https://github.com/Liuk3r/CVE-2023-32233 \
        "$LIN/CVE-2023-32233" && \
        log "CVE-2023-32233 (kernels up to 6.3.1 Netfilter UAF → root)"
else
    git -C "$LIN/CVE-2023-32233" pull -q && log "CVE-2023-32233 updated"
fi

# kubeletctl — Kubernetes Kubelet API tool
info "kubeletctl..."
KUBELET_VER=$(curl -s https://api.github.com/repos/cyberark/kubeletctl/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
KUBELET_VER="${KUBELET_VER:-v1.11}"
curl -fsSL \
    "https://github.com/cyberark/kubeletctl/releases/download/${KUBELET_VER}/kubeletctl_linux_amd64" \
    -o "$LIN/kubeletctl" && chmod +x "$LIN/kubeletctl" && \
    log "kubeletctl (Kubernetes Kubelet API — list pods, exec in containers)"

# =============================================================================
section "DONE"
# =============================================================================

echo ""
log "Linux transfer folder contents:"
ls "$LIN" | column
echo ""
log "Update your GitHub repo with the new setup.sh and deep_verify.sh"
log "Next fresh installs will include all these automatically"
