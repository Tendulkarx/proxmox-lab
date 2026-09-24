<#
prdsrv1: fixed address 10.69.20.113 (was 10.69.20.69 from DHCP), next to prdsrv2 (.114).
Changing the address drops any SSH or Remote Desktop session, so run it as a one-off
SYSTEM task that outlives the connection:

  scp scripts/windows/prdsrv1-network.ps1 prdsrv1:C:/ProgramData/
  ssh prdsrv1 'Register-ScheduledTask -TaskName prdsrv1-network -Force -User SYSTEM -RunLevel Highest
     -Action (New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\prdsrv1-network.ps1")
     -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(15))'

Then connect to 10.69.20.113. BEFORE running: the VPN the Mac uses to reach the servers must
allow 10.69.20.113 (it only routes the addresses it knows). Safety net: if the gateway doesn't answer on the new address
within 30 seconds, it goes back to DHCP. Log: C:\ProgramData\prdsrv1-network.log.
Safe to re-run: does nothing when the address is already set.
#>
$ErrorActionPreference = 'Stop'
$ip = '10.69.20.113'; $prefix = 24; $gw = '10.69.20.1'; $dns = '10.69.20.114', '10.69.20.1'
$log = 'C:\ProgramData\prdsrv1-network.log'
function Log($m) { Add-Content -Path $log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) }

$nic = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -match 'VirtIO' } | Select-Object -First 1
if (-not $nic) { Log 'no VirtIO adapter up; nothing done'; exit 1 }
$if = $nic.ifIndex
$current = Get-NetIPAddress -InterfaceIndex $if -AddressFamily IPv4
if ($current.IPAddress -eq $ip -and $current.PrefixOrigin -eq 'Manual') { Log "already $ip; nothing to do"; exit 0 }
Log "changing $($nic.Name) from $($current.IPAddress) ($($current.PrefixOrigin)) to $ip"

try {
    # netsh sets address, mask and gateway in one step; the NetTCPIP cmdlets failed with
    # "Generic failure" part-way through on 2026-09-24 (the safety net reverted it).
    $name = $nic.Name
    netsh interface ipv4 set address name="$name" static $ip 255.255.255.0 $gw | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "netsh set address exited $LASTEXITCODE" }
    netsh interface ipv4 set dnsservers name="$name" static $dns[0] primary validate=no | Out-Null
    netsh interface ipv4 add dnsservers name="$name" $dns[1] index=2 validate=no | Out-Null
    $ok = $false
    foreach ($n in 1..15) {
        Start-Sleep -Seconds 2
        if (Test-Connection -ComputerName $gw -Count 1 -Quiet) { $ok = $true; break }
    }
    if (-not $ok) { throw "gateway $gw not answering on $ip" }
    Log "done: $ip/$prefix via $gw, DNS $($dns -join ', ')"
} catch {
    Log "FAILED at line $($_.InvocationInfo.ScriptLineNumber) ($_): reverting to DHCP"
    netsh interface ipv4 set address name="$($nic.Name)" source=dhcp | Out-Null
    netsh interface ipv4 set dnsservers name="$($nic.Name)" source=dhcp | Out-Null
    ipconfig /renew | Out-Null
    Log "reverted to DHCP: $((Get-NetIPAddress -InterfaceIndex $if -AddressFamily IPv4).IPAddress)"
}
