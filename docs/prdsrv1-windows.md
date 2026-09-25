# prdsrv1 (Windows 11 VM)

Windows 11 Pro on prx1, VMID 100: O'Neil's Windows PC over Remote Desktop, so picture
quality and responsiveness matter most. Terraform owns its hardware (`envs/prod/prod.tf`);
Windows isn't managed by Ansible, so its settings are PowerShell scripts run over SSH.

| What | Where |
|---|---|
| Apps, terminal, look, wallpaper | dotfiles `install.ps1` (machine file `machines/prdsrv1`) |
| Server settings: NTP, Remote Desktop and SSH allow-list, Fast Startup off, OneDrive and Edge start-up removed, Remote Desktop quality | `scripts/windows/prdsrv1-settings.ps1` |
| Fixed IP 10.69.20.113 (paused) | `scripts/windows/prdsrv1-network.ps1` |
| SSH (key only, home networks only) | dotfiles `windows/enable-ssh.ps1` |

Run a script: `scp scripts/windows/<script> prdsrv1: && ssh prdsrv1 '.\<script>'`.
Both are safe to re-run and print only what they change.

## Remote Desktop

- H.264/AVC 4:4:4 (full colour), 60 fps, hardware encoding when a GPU is available.
- Client (Windows App on the Mac): Display, **Optimize for Retina displays** on and colour
  quality highest.
- Allowed from 10.69.20.0/24, 10.69.10.0/24 and 10.69.2.0/24 only.

## Restarting

A restart from inside Windows keeps the old virtual hardware. Hardware changes (disk options,
serial port, GPU) need a full stop and start: `lab restart prdsrv1` (asks first), or the
Proxmox web UI, **Shutdown** then **Start** (not Reboot).

## Console

Proxmox web UI, Console > **xterm.js** (serial port; paste works) or noVNC. Log in as `turbx`
with 1Password `proxmox-vm-console` (five words, easy to type in noVNC).

## Open items

- **Fixed IP**: the first try failed safely (reverted to DHCP). The Mac's VPN can't reach
  `.113`; allow it there first, then run `prdsrv1-network.ps1`.
- **GPU**: Intel HD 630 passthrough shows Code 43. Plan: GVT-g in one prx1 maintenance window
  (see `docs/proxmox-review.md`).
- **1Password SSH agent**: sign in on prdsrv1 and turn it on, for commit signing and GitHub.
