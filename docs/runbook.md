# Runbook

How O'Neil works with this repo day to day, with or without Claude.

## One-off setup on the Mac

| What | How |
|---|---|
| Tools | `brew install hashicorp/tap/terraform 1password-cli ansible` |
| 1Password CLI | 1Password app: Settings, Developer, "Integrate with 1Password CLI" |
| SSH key in keychain | `ssh-add --apple-use-keychain ~/.ssh/id_ed25519_homelab` |
| Ansible collections | `make ansible-deps` |
| Terraform providers | `make init` and `make init ENV=prod` |
| Sanity check | `make check` |
| Claude Code | `npm install -g @anthropic-ai/claude-code` (or the installer), then `cd ~/development/proxmox-lab && claude` |

## Asking Claude to do things

Run Claude Code **from this folder** (in Warp, Orca or any terminal). It reads `CLAUDE.md`
automatically and runs commands on your Mac, which is the machine that can reach the lab.

- Read-only commands (`make plan`, `make audit`, `git diff`) run without asking.
- Anything that changes the lab (`make up`, `make configure`, `make patch`) asks you first.
- Touch ID prompts from 1Password are expected whenever Terraform runs.

Shortcuts (type in Claude Code):

| Command | Does |
|---|---|
| `/audit` | full read-only health check, prioritised findings, updates the review doc |
| `/new-vm web1 4 4096 40` | creates and configures a lab VM |
| `/patch prdsrv2` | backup, OS updates, supervised reboot, containers checked |

Or just ask in plain English: "resize prdsrv2 to 6 cores", "why is Pi-hole slow?",
"destroy all lab VMs".

## Commands (without Claude)

From any folder, `lab <command>` runs the make target here (`lab` alone goes to the repo);
`cheat` lists every custom command. `make help` is the full list. The ones you will use most:

| Task | Command |
|---|---|
| How is everything? | `lab status`: hosts, VMs, pending hardware changes, backup disk, last nightly backup |
| Backup a VM now | `lab backup prdsrv1` |
| Apply pending hardware changes | `lab restart prdsrv1` (full stop and start; asks first) |
| New lab VM | add a line to `terraform/envs/lab/vms.auto.tfvars`, then `make up` and `make configure` |
| Remove lab VM | delete its line and `make up`, or `make down NAME=<vm>` |
| Log in | `make ssh NAME=<vm>` |
| Health check | `make audit` (reports in `audit/`) |
| Preview prod changes | `make plan ENV=prod` |
| Apply prod changes | `make up ENV=prod` |
| Re-apply VM config | `make configure ENV=prod` / `ENV=lab` |
| Host hardening | `make hosts-check`, then `make hosts` |
| Patch a VM | `make patch ENV=prod NAME=prdsrv2` |

## When something goes wrong

- `REMOTE HOST IDENTIFICATION HAS CHANGED` for a lab VM: `make forget-host NAME=<vm>`.
- `Missing sudo password` on a new hand-built VM: run `make configure ... ARGS="-K"` once.
- Terraform `403 Permission check failed (/, Sys.Modify)`: that setting is host-level; it
  belongs in `ansible/roles/pve_host` (see decision 11 and the start-order change).
- A prod VM restart is always your call: `lab restart <vm>` (it asks first). A restart from
  inside the guest does **not** apply hardware changes; `lab status` shows any still pending.
- The backup disk filling up, or backups growing: `docs/reclaim-disk-space.md`.
- A backup alert email (Proxmox, Backup Server) or a down "Database dumps" / "App backups" /
  "Off-site copy" monitor: `journalctl -u db-dumps -u db-offsite` on that host; re-run with
  `sudo systemctl start db-dumps db-offsite`. Restores: `docs/disaster-recovery.md`.
- An app needs `docker compose up` on a host: only its own folders are there (homelab-apps
  `hosts/<host>`). A new app: add its folder to the right list first.
- Ports published by Docker bypass UFW; UFW (role `firewall`) only guards SSH on the VMs.
- Setting up any Windows or Mac machine: the dotfiles README and its troubleshooting section.
  The old Windows prdsrv1 is only a backup now (`archive` on prx2, lab-rebuild-plan phase 5).
