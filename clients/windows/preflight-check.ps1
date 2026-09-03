# Run this BEFORE installing any log-forwarding agent (NXLog, Fluent Bit,
# etc.) on a Windows device you want to monitor. It confirms the device
# can actually reach the collector over the network first - the single
# most common source of "it's not working" once an agent is configured,
# and one no agent-side troubleshooting can fix if the answer is no.
#
# Usage: .\preflight-check.ps1 -CollectorHost 192.168.30.38

param(
    [Parameter(Mandatory=$true)]
    [string]$CollectorHost
)

$pass = 0
$fail = 0

Write-Host "Checking connectivity to syslog collector at $CollectorHost ..."
Write-Host ""

if (Test-Connection -ComputerName $CollectorHost -Count 1 -Quiet) {
    Write-Host "[PASS] ICMP ping reachable" -ForegroundColor Green
    $pass++
} else {
    Write-Host "[WARN] ICMP ping failed (not fatal - some networks block ping while still allowing the ports below)" -ForegroundColor Yellow
}

function Test-Port {
    param([int]$Port, [string]$Label)
    $result = Test-NetConnection -ComputerName $CollectorHost -Port $Port -WarningAction SilentlyContinue
    if ($result.TcpTestSucceeded) {
        Write-Host "[PASS] TCP $Port ($Label) reachable" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "[FAIL] TCP $Port ($Label) NOT reachable" -ForegroundColor Red
        $script:fail++
    }
}

Test-Port -Port 514 -Label "syslog TCP"
Test-Port -Port 20514 -Label "syslog RELP"
Test-Port -Port 3100 -Label "Loki push API"

Write-Host ""
Write-Host "UDP 514 (syslog UDP) can't be definitively tested without a listener ack -"
Write-Host "if the TCP 514 check above passed, UDP to the same host/port is almost"
Write-Host "always fine too (same host, same firewall path)."

Write-Host ""
Write-Host "Result: $pass passed, $fail failed."
if ($fail -gt 0) {
    Write-Host "Fix network reachability (routing/firewall/VPN) before configuring any agent." -ForegroundColor Red
    exit 1
} else {
    Write-Host "Network path looks good - safe to proceed with agent setup." -ForegroundColor Green
}
