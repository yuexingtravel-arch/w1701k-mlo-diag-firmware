param(
    [string]$MloSection = "mlo1",
    [string]$MloProfile = "Gemtek_W1701K_MLO",
    [string]$FallbackProfile = "Gemtek_W1701K",
    [string]$WifiInterface = "WLAN 3",
    [string]$ApAddress = "192.0.2.2",
    [string]$RouterAddress = "192.0.2.1",
    [string]$KeyPath = (Join-Path $env:USERPROFILE ".ssh\codex_lan_ed25519"),
    [string]$EvidenceDirectory = (Join-Path $PSScriptRoot "evidence")
)

$ErrorActionPreference = "Stop"
$ssh = "$env:WINDIR\System32\OpenSSH\ssh.exe"
$sshBase = @("-i", $KeyPath, "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=5", "root@$ApAddress")
$criticalPattern = "panic|oops|rcu.*stall|mt7996_mcu_rx_event|ps.sync|firmware.*(assert|reset)|watchdog.*(reset|bite)|netdev watchdog|tx timeout"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$logPath = Join-Path $EvidenceDirectory "mlo-association-rebuild-$stamp.log"

function Write-Record([string]$Text) {
    $line = "{0:o} {1}" -f (Get-Date), $Text
    $line | Tee-Object -FilePath $logPath -Append
}

function Invoke-Ap([string]$Command) {
    $output = @(& $ssh @sshBase $Command 2>&1)
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join " | ") }
}

function Wait-Ap([int]$Seconds = 60) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $r = Invoke-Ap "true"
        if ($r.ExitCode -eq 0) { return $true }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Get-WlanText { (@(& netsh.exe wlan show interfaces) -join [Environment]::NewLine) }

function Connect-Profile([string]$Name, [int]$Seconds = 90) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    $attempt = 0
    do {
        $attempt++
        if ($attempt -eq 1 -or ($attempt % 5) -eq 0) {
            & netsh.exe wlan connect "name=$Name" "interface=$WifiInterface" 2>&1 | Out-Null
        }
        Start-Sleep -Seconds 1
        $text = Get-WlanText
        if ($text -match "(?m)^\s*SSID\s*:\s*$([regex]::Escape($Name))\s*$") { return $text }
    } while ((Get-Date) -lt $deadline)
    throw "Timed out connecting to $Name"
}

function Wait-LinkCount([int]$Expected, [int]$Seconds = 60) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    $last = ""
    do {
        $last = Get-WlanText
        $count = @([regex]::Matches($last, "LinkID:")).Count
        if ($count -eq $Expected) { return [pscustomobject]@{ Count=$count; Text=$last } }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    [pscustomobject]@{ Count=$count; Text=$last }
}

function Connect-MloFresh([int]$Seconds = 90) {
    # FastConnect 7800 may expose only the current BSS while associated.
    # Disconnect once so Windows performs a full scan and discovers both MLD links.
    & netsh.exe wlan disconnect "interface=$WifiInterface" 2>&1 | Out-Null
    Start-Sleep -Seconds 6
    & netsh.exe wlan show networks mode=bssid "interface=$WifiInterface" 2>&1 | Out-Null
    Connect-Profile $MloProfile $Seconds
}

function Get-ApLinks {
    $r = Invoke-Ap "iw dev ap-mld0 info 2>&1"
    if ($r.ExitCode -ne 0) { return [pscustomobject]@{ Count=0; Output=$r.Output } }
    [pscustomobject]@{ Count=@([regex]::Matches($r.Output, "link ID\s+\d+")).Count; Output=$r.Output }
}

function Set-Mlo([bool]$Enabled) {
    $disabled = if ($Enabled) { 0 } else { 1 }
    $mlo = if ($Enabled) { 1 } else { 0 }
    $r = Invoke-Ap "uci set wireless.$MloSection.disabled=$disabled; uci set wireless.$MloSection.mlo=$mlo; wifi reload"
    if ($r.ExitCode -ne 0) { throw "MLO state change failed: $($r.Output)" }
    Start-Sleep -Seconds 12
    if (-not (Wait-Ap 60)) { throw "AP management did not return" }
}

function Restore-SafeState {
    try {
        & netsh.exe wlan disconnect "interface=$WifiInterface" 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        try { Connect-Profile $FallbackProfile 60 | Out-Null } catch { Write-Record "FALLBACK_WARNING $($_.Exception.Message)" }
        $r = Invoke-Ap "uci revert wireless; uci set wireless.$MloSection.disabled=1; uci set wireless.$MloSection.mlo=0; uci commit wireless; wifi reload"
        if ($r.ExitCode -ne 0) { return $false }
        Start-Sleep -Seconds 10
        if (-not (Wait-Ap 60)) { return $false }
        $v = Invoke-Ap "uci -q get wireless.$MloSection.disabled; uci -q get wireless.$MloSection.mlo; uci changes wireless | wc -l; if iw dev ap-mld0 info >/dev/null 2>&1; then echo MLD_PRESENT; else echo MLD_ABSENT; fi"
        return ($v.ExitCode -eq 0 -and $v.Output -match "^1 \| 0 \| 0 \| MLD_ABSENT$")
    } catch {
        Write-Record "RESTORE_ERROR $($_.Exception.Message)"
        return $false
    }
}

$passed = $false
$restored = $false
$boot0 = (Invoke-Ap "cat /proc/sys/kernel/random/boot_id").Output.Trim()
$critical0 = [int](Invoke-Ap "dmesg | grep -Eic '$criticalPattern' || true").Output.Trim()

try {
    $base = Invoke-Ap "uci -q get wireless.$MloSection.disabled; uci -q get wireless.$MloSection.mlo; uci changes wireless | wc -l"
    if ($base.Output -notmatch "^1 \| 0 \| 0$") { throw "Safe baseline is absent: $($base.Output)" }
    Connect-Profile $FallbackProfile 60 | Out-Null

    $t0 = Get-Date
    Set-Mlo $true
    $ap1 = Get-ApLinks
    if ($ap1.Count -ne 2) { throw "Initial AP MLD has $($ap1.Count) links" }
    Connect-MloFresh 90 | Out-Null
    $win1 = Wait-LinkCount 2 60
    if ($win1.Count -ne 2) { throw "Initial Windows MLO association has $($win1.Count) links" }
    $initialSeconds = [math]::Round(((Get-Date)-$t0).TotalSeconds,1)
    Write-Record "INITIAL_PASS ap_links=2 windows_links=2 elapsed_s=$initialSeconds"
    $win1.Text | Set-Content -LiteralPath (Join-Path $EvidenceDirectory "mlo-association-initial-$stamp.txt") -Encoding utf8

    # Move management to the fallback AP, fully remove the MLD, then rebuild it.
    & netsh.exe wlan disconnect "interface=$WifiInterface" 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    Connect-Profile $FallbackProfile 60 | Out-Null
    Set-Mlo $false
    if ((Get-ApLinks).Count -ne 0) { throw "MLD teardown did not remove ap-mld0" }
    Write-Record "TEARDOWN_PASS ap_links=0"

    $t1 = Get-Date
    Set-Mlo $true
    $ap2 = Get-ApLinks
    if ($ap2.Count -ne 2) { throw "Rebuilt AP MLD has $($ap2.Count) links" }
    Connect-MloFresh 90 | Out-Null
    $win2 = Wait-LinkCount 2 60
    $rebuildSeconds = [math]::Round(((Get-Date)-$t1).TotalSeconds,1)
    $win2.Text | Set-Content -LiteralPath (Join-Path $EvidenceDirectory "mlo-association-rebuilt-$stamp.txt") -Encoding utf8
    if ($win2.Count -ne 2) { throw "Rebuilt Windows MLO association has $($win2.Count) links after $rebuildSeconds seconds" }

    $pingAp = Test-Connection -TargetName $ApAddress -Count 20 -TimeoutSeconds 1 -ErrorAction SilentlyContinue
    $pingRouter = Test-Connection -TargetName $RouterAddress -Count 20 -TimeoutSeconds 1 -ErrorAction SilentlyContinue
    if (@($pingAp).Count -ne 20 -or @($pingRouter).Count -ne 20) { throw "Post-rebuild connectivity samples were lost" }

    $boot1 = (Invoke-Ap "cat /proc/sys/kernel/random/boot_id").Output.Trim()
    $critical1 = [int](Invoke-Ap "dmesg | grep -Eic '$criticalPattern' || true").Output.Trim()
    if ($boot1 -ne $boot0) { throw "AP rebooted during association/rebuild test" }
    if ($critical1 -gt $critical0) { throw "New critical kernel messages appeared" }
    Write-Record "REBUILD_PASS ap_links=2 windows_links=2 elapsed_s=$rebuildSeconds ping_ap=20/20 ping_router=20/20 boot_unchanged=true new_critical=0"
    $passed = $true
}
finally {
    $restored = Restore-SafeState
    Write-Record "FINAL safe_state_restored=$restored fallback_requested=true"
}

if (-not $restored) { throw "Could not restore committed MLO-off safe state" }
if (-not $passed) { throw "Association/rebuild test failed" }
Write-Record "RESULT PASS"




