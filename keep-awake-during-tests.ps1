Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class AwakeState {
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern uint SetThreadExecutionState(uint esFlags);
}
"@
$continuous = [uint32]2147483648
$systemRequired = [uint32]1
$displayRequired = [uint32]2
try {
    while ($true) {
        $flags = [uint32]($continuous -bor $systemRequired -bor $displayRequired)
        [void][AwakeState]::SetThreadExecutionState($flags)
        Start-Sleep -Seconds 30
    }
} finally {
    [void][AwakeState]::SetThreadExecutionState($continuous)
}


