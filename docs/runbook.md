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

`make help` is the full list. The ones you will use most:

| Task | Command |
|---|---|
| New lab VM | add a line to `terraform/envs/lab/vms.auto.tfvars`, then `make up` and `make configure` |
| Remove lab VM | delete its line and `make up`, or `make down NAME=<vm>` |
| Log in | `make ssh NAME=<vm>` |
| Health check | `make audit` (reports in `audit/`) |
| Preview prod changes | `make plan ENV=prod` |
| Apply prod changes | `make up ENV=prod` |
| Re-apply VM config | `make configure ENV=prod` / `ENV=lab` |
| Host hardening | `make hosts-check`, then `make hosts` |
| Backup a VM now | `make backup-vm HOST=10.69.20.130 VMID=101` |
| Patch a VM | `make patch ENV=prod NAME=prdsrv2` |

## When something goes wrong

- `REMOTE HOST IDENTIFICATION HAS CHANGED` for a lab VM: `make forget-host NAME=<vm>`.
- `Missing sudo password` on a new hand-built VM: run `make configure ... ARGS="-K"` once.
- Terraform `403 Permission check failed (/, Sys.Modify)`: that setting is host-level; it
  belongs in `ansible/roles/pve_host` (see decision 11 and the start-order change).
- A prod VM restart is always manual:
  `ssh -i ~/.ssh/id_ed25519_homelab root@<host> 'qm shutdown <vmid> && qm start <vmid>'`.
