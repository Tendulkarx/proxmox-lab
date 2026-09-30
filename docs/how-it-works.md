# How proxmox-lab works

The whole lab, explained layer by layer: what each tool owns, where the truth lives, and what
happens when you run a command. Read this first; `docs/expanding.md` and
`docs/disaster-recovery.md` build on it.

## The big picture

```
 Mac (osbmac1)                                     Server VLAN 20 (10.69.20.0/24)
 ~/development/proxmox-lab (this repo)             ┌──────────────────────────────────────┐
 ├─ make ─┬─ Terraform ── Proxmox API (HTTPS) ───▶ │ prx1 prx-server-1 .130   prx2 .131   │
 │        │     tokens from 1Password (op run)     │   VM hardware: CPU, RAM, disk, NIC   │
 │        └─ Ansible ──── SSH (id_ed25519_homelab) │   host config: repos, SSH, backups   │
 │                                                  │   guest config: packages, shell,     │
 └─ Claude Code (reads CLAUDE.md, runs make)       │   Docker, users, updates             │
                                                    └──────────────────────────────────────┘
```

Everything you do goes through `make`. The Makefile decides which tool runs, with which
inventory and which credentials, so a command behaves the same whether you or Claude types it.

## The layers, and who owns each

| Layer | What it is | Owned by | Lives in |
|---|---|---|---|
| 0. Hardware + network | 2 mini PCs, UniFi UDM SE, VLANs, Cloudflare DNS | You (manual) | `agentic-os/07-home-tech` notes |
| 1. Proxmox install | PVE 9 on each host, `vmbr0`, the `data` disk | You, once per host | This doc; `docs/disaster-recovery.md` |
| 2. Host preparation | API user and token, storage content types, template 9000 | `scripts/prep-host.sh` | run once per host as root |
| 3. Host configuration | repos, kernels, root SSH, hostname, backup job, tags, start order, alerts | Ansible role `pve_host` | `ansible/roles/pve_host` |
| 4. VM hardware | which VMs exist; CPU, RAM, disk, NIC, tags, guest agent | Terraform | `terraform/envs/lab`, `terraform/envs/prod` |
| 5. Guest OS | packages, timezone, locale, SSH, sudo, auto-updates, your shell, Docker | Ansible roles `vm_baseline`, `shell`, `docker` | `ansible/roles/` |
| 6. Applications | Docker Compose stacks (Caddy, Pi-hole, Postgres...) | **Hand-managed today** | `/opt/docker/*` on prdsrv2 (not yet in git) |
| 7. Data | databases, Paperless documents, n8n workflows | Nightly Proxmox backup (whole VM) | `data` storage on the same host |

Layers 2 to 5 are code: delete them and the repo rebuilds them. Layers 6 and 7 are the gaps
(see `docs/disaster-recovery.md`, "Gaps").

## The tools

### Terraform (layer 4)

Describes **which VMs exist and what hardware they have**. You edit a file; `make plan` shows
the difference between the file and Proxmox; `make up` makes Proxmox match.

- **Provider**: `bpg/proxmox`, talking to each host's API (two standalone hosts, so two
  provider aliases, `prx1` and `prx2`).
- **Two environments, two separate state files**, so nothing done in one can touch the other:
  - `envs/lab`: disposable test VMs, one line each in `vms.auto.tfvars`. VMID 900-919 maps to
    IP 10.69.20.200-219. Cloned from template 9000, configured by cloud-init (user `turbx`,
    your SSH key, static IP, DNS).
  - `envs/prod`: prdsrv2 **imported** (adopted as it was); prdsrv1 (VM) and prdsrv3
    (container) built by Terraform.
    `prevent_destroy` blocks any plan that would delete them; `reboot_after_update = false`
    means hardware changes wait for you to stop and start the VM.
- **State** (`terraform.tfstate` in each env folder) is Terraform's memory of what it manages.
  It is git-ignored and lives only on the Mac. Losing it is recoverable (re-import), see DR.
- **Module** `terraform/modules/vm`: the one reusable lab-VM definition.

### Ansible (layers 3 and 5)

Describes **what should be configured on a machine**, and makes it so over SSH. Idempotent:
running it twice changes nothing the second time.

| Inventory | Machines | User |
|---|---|---|
| `inventory/proxmox.yml` | prx1, prx2 | root |
| `inventory/prod.yml` | prdsrv2 | turbx (passwordless sudo) |
| `inventory/lab.generated.yml` | lab VMs, **written by Terraform** on every `make up` | turbx |

| Playbook | Roles | Run with |
|---|---|---|
| `proxmox-hosts.yml` | `pve_host` | `make hosts-check`, `make hosts` |
| `site.yml` | `vm_baseline`, `shell`, `docker` | `make configure ENV=lab\|prod` |
| `patch.yml` | (tasks) | `make patch ENV=... NAME=...` |
| `audit.yml` | runs `scripts/audit-guest.sh` | `make audit-vms` |

The `shell` role deploys your dotfiles repo (`~/development/dotfiles` on the Mac,
github.com/Tendulkarx/dotfiles) to `~/development/dotfiles` on each VM: the committed HEAD
only, then its `install.sh` links the files into place, as on the Mac. Commit a change there,
then `make configure`.

### Secrets

| Secret | Where | How it is used |
|---|---|---|
| Proxmox API tokens | 1Password `Development`: `proxmox-prx1-terraform`, `proxmox-prx2-terraform` | `op run --env-file=.env.op` injects them for each Terraform run (Touch ID) |
| SSH key | `~/.ssh/id_ed25519_homelab` (no passphrase); backed up in 1Password as SSH Key item `id_ed25519_homelab` | Ansible, `make ssh`, root on the hosts |
| turbx sudo password | 1Password (yours) | only needed for a brand-new hand-built VM (`ARGS="-K"`) |
| App passwords | per-stack `.env` files on prdsrv2 | not touched by this repo |

`.env.op` holds only `op://` references, so it is safe in git.

### Claude Code

Runs on the Mac in this folder, so it can reach the lab. `CLAUDE.md` gives it the map and the
rules (look, preview, apply, verify); `.claude/settings.json` lets read-only commands run
freely and makes everything else ask you; `.claude/commands/` holds `/audit`, `/new-vm`,
`/patch`.

## What a command actually does

**`make up` (lab)**: `make check` (tools, key, 1Password) → `op run` fetches tokens →
`terraform apply` shows the plan, waits for `yes`, clones/changes/destroys VMs → rewrites
`ansible/inventory/lab.generated.yml` → clears the lab SSH host keys.

**`make configure ENV=prod`**: picks `inventory/prod.yml` → SSH as turbx → `site.yml` applies
baseline, shell and Docker roles → only changes what differs, then prints a recap.

**`make audit`**: copies read-only scripts to each host and VM, runs them, pulls the reports
into `audit/`. Changes nothing anywhere.

## Conventions

| Thing | Convention |
|---|---|
| Lab VMIDs / IPs | 900-919 / 10.69.20.200-219 (VMID - 700) |
| Template | VMID 9000 `ubuntu-2404-cloud-tpl` on each host |
| Tags | `prod`, `lab`, `terraform`, `docker`, `linux`, `windows`, `template` (colours set by `pve_host`) |
| Storage | `data` for prod disks and backups; lab VMs on prx1 use `local-lvm` |
| Default lab host | prx1 (62 GB RAM); prx2 (7.6 GB) only for small VMs |
| Every decision | a row in `docs/decisions.md` with the reason |
