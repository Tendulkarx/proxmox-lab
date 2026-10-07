# Home setup map

Where everything lives and how each machine is set up. Updated 2026-10-07.

## The repos and notes

| Where | What it holds | Changed by |
|---|---|---|
| `~/development/proxmox-lab` (this repo; github.com/Tendulkarx/proxmox-lab, private) | Proxmox hosts, VMs (Terraform), what runs inside the Linux VMs (Ansible), prdsrv1's Windows scripts, and these docs | `make ...` / `lab ...`, then commit |
| `~/development/dotfiles` (github.com/Tendulkarx/dotfiles, private) | Your settings and apps on every machine: shell, git, SSH, terminal looks, wallpaper, app lists, macOS and Windows preferences | Edit the linked file, commit; `dot sync` elsewhere |
| `~/development/agentic-os` (github.com/Tendulkarx/agentic-os) | Claude's memory and area notes; `07-home-tech` routes lab work and records decisions (no guides since 2026-10-01) | Claude sessions |
| `~/development/obsidian/ob` (github.com/Tendulkarx/obsidian-vault, private) | Your knowledge vault: every home-lab guide and reference (`30-resources/homelab`, start at `Index - Home Lab`; `30-resources/guides`), decisions, to-dos (`20-areas/ideas-backlog.md`, Home Tech) | You and Claude |
| 1Password, vault `Development` | Every secret: Proxmox API tokens, root passwords, `proxmox-vm-console`, SSH key `id_ed25519_homelab` | 1Password app |

Planned changes: `docs/lab-rebuild-plan.md` (agreed 2026-09-29: Linux prdsrv1 as the main app
host, prdsrv2 as the database server, Proxmox Backup Server and an infra container on prx2).

The repos are the detailed record; the vault holds summaries and "how do I" guides that link
here. Retired and not to be used: chezmoi, github.com/Tendulkarx/machine-setup (archived), and
agentic-os `Software-Development-Resources/_archive/`.

## Networks

| Network | Range | What is on it |
|---|---|---|
| Server VLAN 20 | 10.69.20.0/24, gateway .1 | Proxmox hosts and every VM |
| Home network | 10.69.10.0/24 | Laptops and Macs at home |
| VPN | 10.69.2.0/24 | The Mac appears as 10.69.2.2 when away (interface `utun10`); only the addresses it knows are routed: .113 and .115 must be allowed there (UniFi) |
| DNS | Pi-hole on prdsrv2 (10.69.20.114), second on prdsrv3 (.115, kept in step by nebula-sync) | Search domain `home.arpa` |

Windows machines only accept SSH and Remote Desktop from these three ranges.

## Machines

| Name | What | Address | Set up by |
|---|---|---|---|
| prx1 (`prx-server-1`) | Proxmox VE 9, 62 GB RAM, main host | 10.69.20.130 | `ansible/roles/pve_host` (`make hosts`) |
| prx2 (`prx-server-2`) | Proxmox VE 9, 7.6 GB RAM: Proxmox Backup Server (datastore `main`, UI on port 8007), storage `archive`, prdsrv3 | 10.69.20.131 | same, plus role `pbs` |
| prdsrv1 | Ubuntu VM on prx1 (VMID 100): the apps and Caddy (Homarr dashboard at `home.`/`dash.`, Paperless, n8n, Metabase, Dozzle, Arcane); Windows until 2026-09-30 | 10.69.20.113 | Terraform prod + Ansible + dotfiles |
| prdsrv3 | Ubuntu container on prx2 (VMID 102): Uptime Kuma, Beszel hub (`beszel.`; agents on every host and VM), second Pi-hole, nebula-sync | 10.69.20.115 | Terraform prod + Ansible |
| prdsrv2 | Ubuntu VM on prx1 (VMID 101): the database server (Postgres, SQL Server, Oracle), primary Pi-hole, property-search | 10.69.20.114 | Terraform prod + Ansible + dotfiles |
| tstsrv<N> | Ubuntu lab VMs on prx1 (VMID 899 + N) | 10.69.20.(199 + N) | Terraform lab + Ansible + dotfiles |
| osbmac1 | Main Mac (personal) | 10.69.10.221 at home (DHCP) | dotfiles `install.sh` |
| osbmac2 | Second Mac | 10.69.10.214 (DHCP) | dotfiles `install.sh` |
| osbwin1 | Windows laptop | 10.69.10.24 (DHCP) | dotfiles `install.ps1` |

Physical hardware (rack, power, cabling, host models, disks): vault
`30-resources/homelab/Reference - Rack and Hardware`.

Naming: personal machines `osb<os><N>` (mac, win, lnx; highest number + 1, never reused);
lab VMs `tstsrv<N>` (lowest free N); prod VMs `prdsrv<N>` (VMID 99 + N, IP highest prod IP + 1).
Rules and checks: `terraform/envs/*/variables.tf`, dotfiles `machines/README.md`.

## Backups and alerts

| What | When | Where |
|---|---|---|
| Database and app dumps | 01:30 | `/opt/backups` on prdsrv2 (databases) and prdsrv1 (n8n, Paperless, Homarr), 14 days |
| VM backups, prx1 (the only job since 2026-09-30) | 03:30 (`pbs-nightly`) | Proxmox Backup Server on prx2: 7 daily, 4 weekly, 3 monthly, verified Sundays |
| VM backups, prx2 (prdsrv3) | 02:30 | `data` on prx2 |
| Off-site | 03:00 | Google Drive `homelab-offsite`, encrypted (keys: 1Password `homelab-rclone-offsite`), 30 days |
| Alerts | on warnings and errors | Gmail, to `user+homelab@example.com` (Gmail filter on that address → label `Homelab`), from both hosts, the Backup Server and Uptime Kuma (every monitor, and a push monitor per backup job) |

## Logging in

| To | How |
|---|---|
| Any host or VM from a Mac | `ssh <name>` (`prx1`, `prdsrv2`, `tstsrv1` ...); the SSH config knows them all |
| A Windows machine | Remote Desktop (Windows App), or `ssh turbx@<ip>` (key only) |
| A VM when SSH is down | Proxmox web UI, console. Linux and prdsrv1: Console > **xterm.js** accepts paste; the password is 1Password `proxmox-vm-console` |
| A host when keys are lost | Proxmox web UI as `root@pam` (password in 1Password, Development: `prx1 - Proxmox root@pam`), then the node Shell |

## Day to day

`cheat` in any terminal lists every custom command. The main ones: `lab status`,
`lab backup <vm>`, `lab restart <vm>`, `dot status`, `dot sync`. Details in `docs/runbook.md`.
