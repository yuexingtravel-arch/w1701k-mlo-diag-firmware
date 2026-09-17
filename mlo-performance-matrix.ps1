param(
    [string]$ApAddress = "192.0.2.2",
    [string]$RouterAddress = "192.0.2.1",
    [string]$WifiInterface = "WLAN 3",
    [string]$FallbackProfile = "Gemtek_W1701K",
    [string]$KeyPath = (Join-Path $env:USERPROFILE ".ssh\codex_lan_ed25519"),
    [string]$IperfPath = (Join-Path $env:USERPROFILE "Documents\codex\.redmi_capture\iperf3\iperf3.exe"),
    [int]$IperfPort = 5202,
    [int]$IperfSeconds = 15,
    [int]$ParallelStreams = 8,
    [string]$OnlyCase = "",
    [string]$EvidenceDirectory = (Join-Path $PSScriptRoot "evidence")
)

$ErrorActionPreference = "Stop"
$ssh = "$env:WINDIR\System32\OpenSSH\ssh.exe"
$sshCommon = @("-i", $KeyPath, "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=5")
$criticalPattern = "panic|oops|rcu.*stall|mt7996_mcu_rx_event|ps.sync|firmware.*(assert|reset)|watchdog.*(reset|bite)|netdev watchdog|tx timeout"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDirectory = Join-Path $EvidenceDirectory "performance-matrix-$stamp"
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
$summaryPath = Join-Path $runDirectory "summary.csv"
$runLog = Join-Path $runDirectory "run.log"

$cases = @(
    [pscustomobject]@{ Name="5g-160"; Profile="Gemtek_W1701K_5G"; Ssid="Gemtek_W1701K_5G"; Mlo=$false; Htmode="EHT320"; Interface="phy0.1-ap0"; ExpectedLinks=0 },
    [pscustomobject]@{ Name="6g-320"; Profile="Gemtek_W1701K_6G"; Ssid="Gemtek_W1701K_6G"; Mlo=$false; Htmode="EHT320"; Interface="phy0.2-ap0"; ExpectedLinks=0 },
    [pscustomobject]@{ Name="mlo-160-320"; Profile="Gemtek_W1701K_MLO"; Ssid="Gemtek_W1701K_MLO"; Mlo=$true; Htmode="EHT320"; Interface="ap-mld0"; ExpectedLinks=2 },
    [pscustomobject]@{ Name="mlo-160-160"; Profile="Gemtek_W1701K_MLO"; Ssid="Gemtek_W1701K_MLO"; Mlo=$true; Htmode="EHT160"; Interface="ap-mld0"; ExpectedLinks=2 }
)
if (-not [string]::IsNullOrWhiteSpace($OnlyCase)) {
    $cases = @($cases | Where-Object Name -eq $OnlyCase)
    if ($cases.Count -ne 1) { throw "Unknown performance case: $OnlyCase" }
}

function Write-Run([string]$Text) {
    $line = "{0:o} {1}" -f (Get-Date), $Text
    $line | Tee-Object -FilePath $runLog -Append
}

function Invoke-Ssh([string]$HostName, [string]$Command) {
    $output = @(& $ssh @sshCommon "root@$HostName" $Command 2>&1)
    [pscustomobject]@{ ExitCode=$LASTEXITCODE; Output=($output -join "`n") }
}

function Invoke-Ap([string]$Command) { Invoke-Ssh $ApAddress $Command }
function Invoke-Router([string]$Command) { Invoke-Ssh $RouterAddress $Command }

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

function Connect-Fresh([string]$Profile, [string]$Ssid, [int]$Seconds = 90) {
    & netsh.exe wlan disconnect "interface=$WifiInterface" 2>&1 | Out-Null
    Start-Sleep -Seconds 6
    & netsh.exe wlan show networks mode=bssid "interface=$WifiInterface" 2>&1 | Out-Null
    $request = @(& netsh.exe wlan connect "name=$Profile" "interface=$WifiInterface" 2>&1) -join " | "
    Write-Run "CONNECT_REQUEST profile=$Profile response=$request"
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        Start-Sleep -Seconds 1
        $text = Get-WlanText
        if ($text -match "(?m)^\s*SSID\s*:\s*$([regex]::Escape($Ssid))\s*$") { return $text }
        if (((Get-Date) -gt $deadline.AddSeconds(-$Seconds + 10)) -and (((Get-Date).Second % 5) -eq 0)) {
            & netsh.exe wlan connect "name=$Profile" "interface=$WifiInterface" 2>&1 | Out-Null
        }
    } while ((Get-Date) -lt $deadline)
    throw "Timed out connecting to $Profile"
}

function Wait-WlanLinkCount([int]$Expected, [int]$Seconds = 60) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    do {
        $text = Get-WlanText
        $count = @([regex]::Matches($text,"LinkID:")).Count
        if ($count -eq $Expected) { return $text }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    return $text
}

function Set-CaseConfiguration([object]$Case) {
    $disabled = if ($Case.Mlo) { 0 } else { 1 }
    $mlo = if ($Case.Mlo) { 1 } else { 0 }
    $cmd = "uci revert wireless; uci set wireless.radio2.htmode=$($Case.Htmode); uci set wireless.mlo1.disabled=$disabled; uci set wireless.mlo1.mlo=$mlo; wifi reload"
    $r = Invoke-Ap $cmd
    if ($r.ExitCode -ne 0) { throw "Cannot configure $($Case.Name): $($r.Output)" }
    Start-Sleep -Seconds 15
    if (-not (Wait-Ap 60)) { throw "AP management did not return for $($Case.Name)" }
}

function Measure-Ping([string]$CaseName, [int]$Count = 50) {
    $samples = [System.Collections.Generic.List[object]]::new()
    $pinger = [System.Net.NetworkInformation.Ping]::new()
    try {
        for ($i=1; $i -le $Count; $i++) {
            $ok = $false; $latency = $null; $status = "Exception"
            try {
                $reply = $pinger.Send($RouterAddress, 1000)
                $status = [string]$reply.Status
                $ok = ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
                if ($ok) { $latency = [double]$reply.RoundtripTime }
            } catch { $status = $_.Exception.GetType().Name }
            $samples.Add([pscustomobject]@{ Sequence=$i; Time=(Get-Date); Success=$ok; LatencyMs=$latency; Status=$status })
            Start-Sleep -Milliseconds 100
        }
    } finally { $pinger.Dispose() }
    $samples | Export-Csv -LiteralPath (Join-Path $runDirectory "$CaseName-ping.csv") -NoTypeInformation -Encoding utf8
    $good = @($samples | Where-Object Success | Select-Object -ExpandProperty LatencyMs | Sort-Object)
    if ($good.Count -eq 0) { return [pscustomobject]@{ Loss=$Count; Average=$null; P95=$null; Maximum=$null } }
    $p95Index = [math]::Min($good.Count - 1, [math]::Ceiling($good.Count * 0.95) - 1)
    [pscustomobject]@{
        Loss = $Count - $good.Count
        Average = [math]::Round((($good | Measure-Object -Average).Average),2)
        P95 = [math]::Round($good[$p95Index],2)
        Maximum = [math]::Round($good[-1],2)
    }
}

function Run-Iperf([object]$Case, [string]$Direction) {
    $reverseArgs = @()
    if ($Direction -eq "reverse") { $reverseArgs = @("-R") }
    $args = @("-c",$RouterAddress,"-p",[string]$IperfPort,"-P",[string]$ParallelStreams,"-t",[string]$IperfSeconds,"-O","2","-J") + $reverseArgs
    $jsonText = @(& $IperfPath @args 2>&1) -join [Environment]::NewLine
    $exitCode = $LASTEXITCODE
    $jsonPath = Join-Path $runDirectory "$($Case.Name)-iperf-$Direction.json"
    $jsonText | Set-Content -LiteralPath $jsonPath -Encoding utf8
    if ($exitCode -ne 0) { throw "iperf3 $Direction failed for $($Case.Name), exit=$exitCode" }
    $data = $jsonText | ConvertFrom-Json
    if ($data.error) { throw "iperf3 $Direction error for $($Case.Name): $($data.error)" }
    $bps = [double]$data.end.sum_received.bits_per_second
    $retransmits = $null
    if ($null -ne $data.end.sum_sent.retransmits) { $retransmits = [int64]$data.end.sum_sent.retransmits }
    [pscustomobject]@{ Gbps=[math]::Round($bps/1e9,3); Retransmits=$retransmits }
}

function Restore-SafeState {
    try {
        & netsh.exe wlan disconnect "interface=$WifiInterface" 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        try { Connect-Fresh $FallbackProfile $FallbackProfile 60 | Out-Null } catch { Write-Run "FALLBACK_WARNING $($_.Exception.Message)" }
        $r = Invoke-Ap "uci revert wireless; uci set wireless.mlo1.disabled=1; uci set wireless.mlo1.mlo=0; uci commit wireless; wifi reload"
        if ($r.ExitCode -ne 0) { return $false }
        Start-Sleep -Seconds 10
        if (-not (Wait-Ap 60)) { return $false }
        $v = Invoke-Ap "uci -q get wireless.mlo1.disabled; uci -q get wireless.mlo1.mlo; uci -q get wireless.radio2.htmode; uci changes wireless | wc -l; if iw dev ap-mld0 info >/dev/null 2>&1; then echo MLD_PRESENT; else echo MLD_ABSENT; fi"
        $v.Output | Set-Content -LiteralPath (Join-Path $runDirectory "final-safe-state.txt") -Encoding utf8
        return ($v.ExitCode -eq 0 -and $v.Output -match "^1\n0\nEHT320\n0\nMLD_ABSENT$")
    } catch {
        Write-Run "RESTORE_ERROR $($_.Exception.Message)"
        return $false
    }
}

if (-not (Test-Path -LiteralPath $IperfPath)) { throw "iperf3 client missing: $IperfPath" }
$restored = $false
$serverStarted = $false
$results = [System.Collections.Generic.List[object]]::new()
$boot0 = (Invoke-Ap "cat /proc/sys/kernel/random/boot_id").Output.Trim()
$critical0 = [int](Invoke-Ap "dmesg | grep -Eic '$criticalPattern' || true").Output.Trim()

try {
    $baseline = Invoke-Ap "uci -q get wireless.mlo1.disabled; uci -q get wireless.mlo1.mlo; uci -q get wireless.radio2.htmode; uci changes wireless | wc -l"
    if ($baseline.Output -notmatch "^1\n0\nEHT320\n0$") { throw "Safe baseline absent: $($baseline.Output -replace "`n",' | ')" }

    $serverCommand = ('if test -f /tmp/codex-iperf3-5202.pid; then read oldpid < /tmp/codex-iperf3-5202.pid; kill "$oldpid" 2>/dev/null || true; rm -f /tmp/codex-iperf3-5202.pid; fi; iperf3 -s -D -I /tmp/codex-iperf3-5202.pid -p {0}; sleep 1; test -s /tmp/codex-iperf3-5202.pid; read newpid < /tmp/codex-iperf3-5202.pid; kill -0 "$newpid"; echo LISTENING' -f $IperfPort)
    $server = Invoke-Router $serverCommand
    if ($server.ExitCode -ne 0 -or $server.Output -notmatch "LISTENING") { throw "Cannot start router iperf3 server: $($server.Output)" }
    $serverStarted = $true
    Write-Run "ROUTER_IPERF_STARTED port=$IperfPort"

    foreach ($case in $cases) {
        Write-Run "CASE_START name=$($case.Name)"
        try { Connect-Fresh $FallbackProfile $FallbackProfile 60 | Out-Null } catch { Write-Run "FALLBACK_PREP_WARNING $($_.Exception.Message)" }
        Set-CaseConfiguration $case

        $apInfo = Invoke-Ap "iw dev $($case.Interface) info 2>&1"
        $apInfo.Output | Set-Content -LiteralPath (Join-Path $runDirectory "$($case.Name)-ap-info.txt") -Encoding utf8
        if ($apInfo.ExitCode -ne 0) { throw "Expected AP interface $($case.Interface) is absent" }

        $wlan = Connect-Fresh $case.Profile $case.Ssid 90
        if ($case.ExpectedLinks -gt 0) {
            $wlan = Wait-WlanLinkCount $case.ExpectedLinks 60
        } else {
            Start-Sleep -Seconds 8
            $wlan = Get-WlanText
        }
        $wlan | Set-Content -LiteralPath (Join-Path $runDirectory "$($case.Name)-wlan.txt") -Encoding utf8
        $linkCount = @([regex]::Matches($wlan,"LinkID:")).Count
        if ($case.ExpectedLinks -gt 0 -and $linkCount -ne $case.ExpectedLinks) { throw "$($case.Name) has $linkCount Windows links" }
        if ($case.Name -eq "mlo-160-320" -and ($wlan -notmatch "Band: 6 GHz, BW: 320" -or $wlan -notmatch "Band: 5 GHz, BW: 160")) { throw "Unexpected 160+320 link widths" }
        if ($case.Name -eq "mlo-160-160" -and @([regex]::Matches($wlan,"BW: 160")).Count -ne 2) { throw "Unexpected 160+160 link widths" }

        $ping = Measure-Ping $case.Name 50
        $before = Invoke-Ap "iw dev $($case.Interface) station dump 2>&1"
        $before.Output | Set-Content -LiteralPath (Join-Path $runDirectory "$($case.Name)-station-before.txt") -Encoding utf8
        if ($case.Mlo) {
            (Invoke-Ap "hostapd_cli -p /var/run/hostapd -i ap-mld0 -l1 all_sta 2>&1").Output | Set-Content -LiteralPath (Join-Path $runDirectory "$($case.Name)-link1-before.txt") -Encoding utf8
            (Invoke-Ap "hostapd_cli -p /var/run/hostapd -i ap-mld0 -l2 all_sta 2>&1").Output | Set-Content -LiteralPath (Join-Path $runDirectory "$($case.Name)-link2-before.txt") -Encoding utf8
            (Invoke-Ap "cat /sys/kernel/debug/ieee80211/phy0/mt76/tx_stats 2>&1").Output | Set-Content -LiteralPath (Join-Path $runDirectory "$($case.Name)-driver-tx-before.txt") -Encoding utf8
        }
        $forward = Run-Iperf $case "forward"
        if ($case.Mlo) {
            (Invoke-Ap "hostapd_cli -p /var/run/hostapd -i ap-mld0 -l1 all_sta 2>&1").Output | Set-Content -LiteralPath (Join-Path $runDirectory "$($case.Name)-link1-after-forward.txt") -Encoding utf8
            (Invoke-Ap "hostapd_cli -p /var/run/hostapd -i ap-mld0 -l2 all_sta 2>&1").Output | Set-Content -LiteralPath (Join-Path $runDirectory "$($case.Name)-link2-after-forward.txt") -Encoding utf8
            (Invoke-Ap "cat /sys/kernel/debug/ieee80211/phy0/mt76/tx_stats 2>&1").Output | Set-Content -LiteralPath (Join-Path $runDirectory "$($case.Name)-driver-tx-after-forward.txt") -Encoding utf8
        }
        $reverse = Run-Iperf $case "reverse"
        if ($case.Mlo) {
            (Invoke-Ap "hostapd_cli -p /var/run/hostapd -i ap-mld0 -l1 all_sta 2>&1").Output | Set-Content -LiteralPath (Join-Path $runDirectory "$($case.Name)-link1-after-reverse.txt") -Encoding utf8
            (Invoke-Ap "hostapd_cli -p /var/run/hostapd -i ap-mld0 -l2 all_sta 2>&1").Output | Set-Content -LiteralPath (Join-Path $runDirectory "$($case.Name)-link2-after-reverse.txt") -Encoding utf8
            (Invoke-Ap "cat /sys/kernel/debug/ieee80211/phy0/mt76/tx_stats 2>&1").Output | Set-Content -LiteralPath (Join-Path $runDirectory "$($case.Name)-driver-tx-after-reverse.txt") -Encoding utf8
        }
        $after = Invoke-Ap "iw dev $($case.Interface) station dump 2>&1"
        $after.Output | Set-Content -LiteralPath (Join-Path $runDirectory "$($case.Name)-station-after.txt") -Encoding utf8

        $boot = (Invoke-Ap "cat /proc/sys/kernel/random/boot_id").Output.Trim()
        $critical = [int](Invoke-Ap "dmesg | grep -Eic '$criticalPattern' || true").Output.Trim()
        if ($boot -ne $boot0) { throw "AP rebooted during $($case.Name)" }
        if ($critical -gt $critical0) { throw "New critical kernel messages during $($case.Name)" }

        $row = [pscustomobject]@{
            Case=$case.Name; WindowsLinks=$linkCount; PingLoss=$ping.Loss; PingAvgMs=$ping.Average; PingP95Ms=$ping.P95; PingMaxMs=$ping.Maximum
            ForwardGbps=$forward.Gbps; ForwardRetransmits=$forward.Retransmits; ReverseGbps=$reverse.Gbps; ReverseRetransmits=$reverse.Retransmits
            BootUnchanged=$true; NewCriticalLogs=0
        }
        $results.Add($row)
        $results | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding utf8
        Write-Run "CASE_PASS name=$($case.Name) links=$linkCount ping_loss=$($ping.Loss) ping_avg_ms=$($ping.Average) forward_gbps=$($forward.Gbps) reverse_gbps=$($reverse.Gbps)"
    }
}
finally {
    if ($serverStarted) {
        $stopCommand = 'if test -f /tmp/codex-iperf3-5202.pid; then read oldpid < /tmp/codex-iperf3-5202.pid; kill "$oldpid" 2>/dev/null || true; rm -f /tmp/codex-iperf3-5202.pid; fi'
        $stop = Invoke-Router $stopCommand
        Write-Run "ROUTER_IPERF_STOP exit=$($stop.ExitCode)"
    }
    $restored = Restore-SafeState
    Write-Run "FINAL safe_state_restored=$restored fallback_requested=true"
}

if (-not $restored) { throw "Could not restore committed MLO-off safe state" }
if ($results.Count -ne $cases.Count) { throw "Performance matrix incomplete: $($results.Count)/$($cases.Count) cases" }
Write-Run "RESULT PASS cases=$($results.Count)"
$results | Format-Table -AutoSize








