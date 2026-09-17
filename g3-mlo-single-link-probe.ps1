param(
    [ValidateSet(1,2)][int]$LinkId = 1,
    [ValidateRange(10,100)][int]$BeaconCount = 20,
    [ValidateRange(10,60)][int]$MonitorSeconds = 15,
    [ValidateRange(1000,10000)][int]$MaxOutageMilliseconds = 3000,
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
$sshBase = @("-i", $KeyPath, "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "root@$ApAddress")
$criticalPattern = "panic|oops|rcu.*stall|mt7996_mcu_rx_event|ps.sync|firmware.*(assert|reset)|watchdog.*(reset|bite)|netdev watchdog|tx timeout"
$cli = "/usr/sbin/hostapd_cli -p /var/run/hostapd -i ap-mld0 -l$LinkId"
$removeLog = "/tmp/mlo-remove-link-$LinkId.log"

function Get-WlanText {
    return (@(& netsh.exe wlan show interfaces) -join [Environment]::NewLine)
}

function Connect-Profile([string]$Name, [int]$TimeoutSeconds = 45) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
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
    throw "Timed out connecting to $Name after $attempt attempts"
}

function Wait-WindowsLinkCount([int]$Expected, [int]$TimeoutSeconds = 45) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $text = Get-WlanText
        $count = @([regex]::Matches($text, "LinkID:")).Count
        if ($count -eq $Expected) { return [pscustomobject]@{ Count = $count; Text = $text } }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    return [pscustomobject]@{ Count = $count; Text = $text }
}

function Invoke-ApCommand([string]$Command) {
    $output = @(& $ssh @sshBase $Command 2>&1)
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join " | ") }
}

function Wait-ApSsh([int]$TimeoutSeconds = 45) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $result = Invoke-ApCommand "true"
        if ($result.ExitCode -eq 0) { return $true }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Get-ApBootId {
    $result = Invoke-ApCommand "cat /proc/sys/kernel/random/boot_id"
    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output)) {
        throw "Cannot read AP boot ID: $($result.Output)"
    }
    return $result.Output.Trim()
}

function Get-CriticalLogCount {
    $result = Invoke-ApCommand "dmesg | grep -Eic '$criticalPattern' || true"
    if ($result.ExitCode -ne 0) { throw "Cannot read AP kernel log: $($result.Output)" }
    return [int]$result.Output.Trim()
}

function Get-ApLinkState {
    $result = Invoke-ApCommand "iw dev ap-mld0 info 2>&1"
    if ($result.ExitCode -ne 0) {
        return [pscustomobject]@{ Count = 0; Output = $result.Output }
    }
    $count = @([regex]::Matches($result.Output, "link ID\s+\d+")).Count
    return [pscustomobject]@{ Count = $count; Output = $result.Output }
}

function Set-TestMloState([bool]$Enabled) {
    $disabledValue = if ($Enabled) { 0 } else { 1 }
    $mloValue = if ($Enabled) { 1 } else { 0 }
    $command = "uci set wireless.$MloSection.disabled=$disabledValue; uci set wireless.$MloSection.mlo=$mloValue; wifi reload"
    $result = Invoke-ApCommand $command
    if ($result.ExitCode -ne 0) { throw "Cannot set temporary MLO state: $($result.Output)" }
    Start-Sleep -Seconds 15
    if (-not (Wait-ApSsh 45)) { throw "AP management did not return after wifi reload" }
}

function Measure-Continuity([int]$DurationSeconds, [int]$IntervalMilliseconds = 100, [int]$TimeoutMilliseconds = 250) {
    $targets = @($ApAddress, $RouterAddress)
    $samples = [System.Collections.Generic.List[object]]::new()
    $pinger = [System.Net.NetworkInformation.Ping]::new()
    $deadline = (Get-Date).AddSeconds($DurationSeconds)
    try {
        while ((Get-Date) -lt $deadline) {
            foreach ($target in $targets) {
                $sentAt = Get-Date
                $ok = $false
                $latency = $null
                try {
                    $reply = $pinger.Send($target, $TimeoutMilliseconds)
                    $ok = ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
                    if ($ok) { $latency = $reply.RoundtripTime }
                } catch {
                    $ok = $false
                }
                $samples.Add([pscustomobject]@{
                    Time = $sentAt
                    Target = $target
                    Success = $ok
                    LatencyMs = $latency
                })
            }
            Start-Sleep -Milliseconds $IntervalMilliseconds
        }
    } finally {
        $pinger.Dispose()
    }
    return $samples.ToArray()
}

function Get-ContinuitySummary([object[]]$Samples, [string]$Target) {
    $selected = @($Samples | Where-Object Target -eq $Target | Sort-Object Time)
    if ($selected.Count -eq 0) { throw "No continuity samples for $Target" }
    $lossStart = $null
    $maxGap = 0.0
    $consecutive = 0
    $maxConsecutive = 0
    foreach ($sample in $selected) {
        if (-not $sample.Success) {
            if ($null -eq $lossStart) { $lossStart = $sample.Time }
            $consecutive++
            if ($consecutive -gt $maxConsecutive) { $maxConsecutive = $consecutive }
        } else {
            if ($null -ne $lossStart) {
                $gap = ($sample.Time - $lossStart).TotalMilliseconds
                if ($gap -gt $maxGap) { $maxGap = $gap }
            }
            $lossStart = $null
            $consecutive = 0
        }
    }
    if ($null -ne $lossStart) {
        $gap = ($selected[-1].Time - $lossStart).TotalMilliseconds + 250
        if ($gap -gt $maxGap) { $maxGap = $gap }
    }
    return [pscustomobject]@{
        Target = $Target
        Samples = $selected.Count
        Lost = @($selected | Where-Object { -not $_.Success }).Count
        MaxConsecutiveLosses = $maxConsecutive
        MaxGapMilliseconds = [math]::Round($maxGap)
    }
}

function Restore-SafeState {
    try {
        & netsh.exe wlan disconnect "interface=$WifiInterface" 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        try { Connect-Profile $FallbackProfile 45 | Out-Null } catch { Write-Output "FALLBACK_CONNECT_WARNING $($_.Exception.Message)" }

        $command = "uci revert wireless; uci set wireless.$MloSection.disabled=1; uci set wireless.$MloSection.mlo=0; uci commit wireless; wifi reload"
        $result = Invoke-ApCommand $command
        if ($result.ExitCode -ne 0) { return $false }
        Start-Sleep -Seconds 8
        if (-not (Wait-ApSsh 45)) { return $false }

        $verify = Invoke-ApCommand "uci -q get wireless.$MloSection.disabled; uci -q get wireless.$MloSection.mlo; uci changes wireless | wc -l; if iw dev ap-mld0 info >/dev/null 2>&1; then echo MLD_PRESENT; else echo MLD_ABSENT; fi"
        return ($verify.ExitCode -eq 0 -and $verify.Output -match "^1 \| 0 \| 0 \| MLD_ABSENT$")
    } catch {
        Write-Output "SAFE_RESTORE_ERROR $($_.Exception.Message)"
        return $false
    }
}

$restored = $false
$passed = $false
$oldBootId = Get-ApBootId
$oldCriticalCount = Get-CriticalLogCount

try {
    $baseline = Invoke-ApCommand "uci -q get wireless.$MloSection.disabled; uci -q get wireless.$MloSection.mlo; uci changes wireless | wc -l"
    if ($baseline.ExitCode -ne 0 -or $baseline.Output -notmatch "^1 \| 0 \| 0$") {
        throw "Test requires committed safe baseline: disabled=1, mlo=0, no pending wireless changes"
    }

    Connect-Profile $FallbackProfile 45 | Out-Null
    Set-TestMloState $true
    $beforeAp = Get-ApLinkState
    if ($beforeAp.Count -ne 2) { throw "AP MLD did not start with two links: $($beforeAp.Output)" }

    Connect-Profile $MloProfile 90 | Out-Null
    $beforeWindows = Wait-WindowsLinkCount 2 45
    $beforeWindowsLinks = $beforeWindows.Count
    Write-Output "BEFORE ap_links=$($beforeAp.Count) windows_links=$beforeWindowsLinks boot_id=$oldBootId critical_count=$oldCriticalCount"
    if ($beforeWindowsLinks -ne 2) { throw "Windows client did not associate with two links" }

    $scheduleCommand = "rm -f $removeLog; (sleep 2; $cli remove_link $BeaconCount > $removeLog 2>&1) > /dev/null 2>&1 & echo SCHEDULED"
    $schedule = Invoke-ApCommand $scheduleCommand
    Write-Output "REMOVE_SCHEDULE link=$LinkId beacons=$BeaconCount exit=$($schedule.ExitCode) output=$($schedule.Output)"
    if ($schedule.ExitCode -ne 0 -or $schedule.Output -notmatch "SCHEDULED") {
        throw "Link removal scheduling failed"
    }

    $samples = @(Measure-Continuity $MonitorSeconds)
    New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
    $continuityPath = Join-Path $EvidenceDirectory ("g3-mlo-remove-link-{0}-{1}.csv" -f $LinkId,(Get-Date -Format "yyyyMMdd-HHmmss"))
    $samples | Export-Csv -LiteralPath $continuityPath -NoTypeInformation -Encoding utf8
    Write-Output "CONTINUITY_EVIDENCE $continuityPath"

    $apContinuity = Get-ContinuitySummary $samples $ApAddress
    $routerContinuity = Get-ContinuitySummary $samples $RouterAddress
    $duringWindows = Get-WlanText
    $duringWindowsLinks = @([regex]::Matches($duringWindows, "LinkID:")).Count
    $duringAp = Get-ApLinkState
    $removeResult = Invoke-ApCommand "cat $removeLog"

    Write-Output "DURING ap_links=$($duringAp.Count) windows_links=$duringWindowsLinks remove_rc=$($removeResult.ExitCode) remove_output=$($removeResult.Output)"
    Write-Output "AP_LINK_STATE $($duringAp.Output)"
    Write-Output "CONTINUITY target=$($apContinuity.Target) samples=$($apContinuity.Samples) lost=$($apContinuity.Lost) max_consecutive=$($apContinuity.MaxConsecutiveLosses) max_gap_ms=$($apContinuity.MaxGapMilliseconds)"
    Write-Output "CONTINUITY target=$($routerContinuity.Target) samples=$($routerContinuity.Samples) lost=$($routerContinuity.Lost) max_consecutive=$($routerContinuity.MaxConsecutiveLosses) max_gap_ms=$($routerContinuity.MaxGapMilliseconds)"

    & netsh.exe wlan disconnect "interface=$WifiInterface" 2>&1 | Out-Null
    Start-Sleep -Seconds 2
    Connect-Profile $FallbackProfile 45 | Out-Null
    $midBootId = Get-ApBootId
    $midCriticalCount = Get-CriticalLogCount

    if ($removeResult.ExitCode -ne 0 -or $removeResult.Output -notmatch "OK") { throw "remove_link did not complete" }
    if ($duringAp.Count -ne 1) { throw "AP did not settle on exactly one MLO link" }
    $remainingLinkId = if ($LinkId -eq 1) { 2 } else { 1 }
    if ($duringAp.Output -match "link ID\s+$LinkId(?:\D|$)") { throw "Requested Link $LinkId is still present on AP" }
    if ($duringAp.Output -notmatch "link ID\s+$remainingLinkId(?:\D|$)") { throw "Expected remaining Link $remainingLinkId is absent on AP" }
    if ($apContinuity.MaxGapMilliseconds -gt $MaxOutageMilliseconds -or $routerContinuity.MaxGapMilliseconds -gt $MaxOutageMilliseconds) {
        throw "Traffic interruption exceeded $MaxOutageMilliseconds ms"
    }
    if ($midBootId -ne $oldBootId) { throw "AP rebooted during link removal" }
    if ($midCriticalCount -gt $oldCriticalCount) { throw "New critical kernel messages appeared during link removal" }

    Set-TestMloState $false
    if ((Get-ApLinkState).Count -ne 0) { throw "MLD teardown did not remove the test interface" }
    Set-TestMloState $true
    $rebuiltAp = Get-ApLinkState
    if ($rebuiltAp.Count -ne 2) { throw "Full MLD rebuild did not restore two AP links: $($rebuiltAp.Output)" }

    Connect-Profile $MloProfile 90 | Out-Null
    $afterWindows = Wait-WindowsLinkCount 2 45
    $afterWindowsLinks = $afterWindows.Count
    $afterBootId = Get-ApBootId
    $afterCriticalCount = Get-CriticalLogCount
    Write-Output "AFTER_REBUILD ap_links=$($rebuiltAp.Count) windows_links=$afterWindowsLinks boot_id=$afterBootId critical_count=$afterCriticalCount"
    if ($afterWindowsLinks -ne 2) { throw "Windows client did not return with two links after full MLD rebuild" }
    if ($afterBootId -ne $oldBootId) { throw "AP rebooted during test or MLD rebuild" }
    if ($afterCriticalCount -gt $oldCriticalCount) { throw "New critical kernel messages appeared" }
    $passed = $true
}
finally {
    $restored = Restore-SafeState
    Write-Output "FINAL safe_state_restored=$restored fallback_requested=true"
}

if (-not $restored) { throw "Could not restore committed MLO-off safe state" }
if (-not $passed) { throw "Standard remove_link probe failed for link $LinkId" }
Write-Output "Standard remove_link probe passed for link $LinkId"



