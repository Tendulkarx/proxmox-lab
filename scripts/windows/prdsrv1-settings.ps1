<#
prdsrv1 (Windows 11 VM) settings that belong to it as a server, not to the dotfiles.
Safe to re-run; prints only what it changes. Run over SSH from the Mac:

  scp scripts/windows/prdsrv1-settings.ps1 prdsrv1: && ssh prdsrv1 '.\prdsrv1-settings.ps1'

  1. Time: sync over NTP (it was running on its own clock, "Local CMOS Clock")
  2. Remote Desktop and SSH: only from the server VLAN (10.69.20.0/24), the home network
     (10.69.10.0/24) and the VPN (10.69.2.0/24). Remote Desktop was open to any address
  3. Fast Startup off: "shut down" becomes a real shutdown, which Proxmox's clean shutdowns
     and pending hardware changes rely on
  4. OneDrive removed and kept from coming back (not used); ~\OneDrive files are left alone
  5. Edge no longer starts itself at sign-in (Startup boost off)
  6. Remote Desktop picture quality: full-colour H.264 (AVC 4:4:4), 60 frames a second, and
     the GPU for encoding when it works. Applies from the next Remote Desktop connection.
#>
$ErrorActionPreference = 'Stop'
function Say($m) { Write-Host $m }
function Set-Reg($path, $name, $value) {
    $cur = (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name
    if ("$cur" -eq "$value") { return }
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType DWord -Force | Out-Null
    Say "  $path\$name = $value"
}

Say '-- 1. time sync (NTP)'
$peers = 'time.cloudflare.com,0x8 0.uk.pool.ntp.org,0x8'
if ((Get-Service w32time).StartType -ne 'Automatic') { Set-Service w32time -StartupType Automatic; Say '  w32time starts automatically' }
$cfg = (w32tm /query /configuration) -join "`n"
if ($cfg -notmatch [regex]::Escape('NtpServer: time.cloudflare.com')) {
    w32tm /config /manualpeerlist:"$peers" /syncfromflags:manual /reliable:no /update | Out-Null
    Restart-Service w32time
    Say "  NTP servers: $peers"
}
w32tm /resync /force | Out-Null
Say ('  source now: ' + ((w32tm /query /source) -join '').Trim())

Say '-- 2. Remote Desktop and SSH only from home networks'
$allowed = '10.69.20.0/24', '10.69.10.0/24', '10.69.2.0/24'
$rules = @(Get-NetFirewallRule -DisplayGroup 'Remote Desktop' | Where-Object Direction -eq 'Inbound') +
         @(Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)
foreach ($rule in $rules) {
    $now = @(($rule | Get-NetFirewallAddressFilter).RemoteAddress)
    $want = $allowed | ForEach-Object { $_ -replace '/24$', '/255.255.255.0' }
    if ((($now | Sort-Object) -join ',') -ne (($want | Sort-Object) -join ',')) {
        $rule | Set-NetFirewallRule -RemoteAddress $allowed
        Say "  $($rule.Name): $($allowed -join ', ') (was $($now -join ', '))"
    }
}

Say '-- 3. Fast Startup off'
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' HiberbootEnabled 0

Say '-- 4. OneDrive'
if (Get-Process OneDrive -ErrorAction SilentlyContinue) { Stop-Process -Name OneDrive -Force; Say '  stopped' }
if (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") {
    winget uninstall --id Microsoft.OneDrive --exact --silent --accept-source-agreements --disable-interactivity | Out-Null
    Say "  uninstalled (exit $LASTEXITCODE)"
}
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' DisableFileSyncNGSC 1
if (Test-Path "$HOME\OneDrive") {
    $n = @(Get-ChildItem "$HOME\OneDrive" -Recurse -File -ErrorAction SilentlyContinue).Count
    Say "  ~\OneDrive kept as a plain folder ($n files)"
}

Say '-- 5. Edge start-up'
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' StartupBoostEnabled 0
Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Run | Get-Member -MemberType NoteProperty |
    Where-Object Name -like 'MicrosoftEdgeAutoLaunch_*' | ForEach-Object {
        Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Run -Name $_.Name
        Say "  removed start-up entry $($_.Name)"
    }
Say '-- 6. Remote Desktop picture quality'
$ts = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
Set-Reg $ts AVC444ModePreferred 1          # Prioritize H.264/AVC 444 graphics mode
Set-Reg $ts AVCHardwareEncodePreferred 1   # Configure H.264/AVC hardware encoding
Set-Reg $ts bEnumerateHWBeforeSW 1         # Use hardware graphics adapters for all RDS sessions
# 60 fps instead of the default 30 (frame interval in ms)
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations' DWMFRAMEINTERVAL 15

Say 'done'
