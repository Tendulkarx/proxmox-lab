# proxmox-lab

Infrastructure as code for O'Neil's homelab: two standalone Proxmox VE 9 hosts, their VMs,
and the software inside them. Terraform (bpg/proxmox) owns VM hardware; Ansible owns the
hosts and everything inside the guests. `make help` lists every command; the Makefile is the
source of truth for how things run.

## Environment

- Hosts: prx1 = `prx-server-1` 10.69.20.130 (62 GB RAM, main host); prx2 = `prx-server-2`
  10.69.20.131 (7.6 GB RAM). Server VLAN 10.69.20.0/24, gateway .1, DNS Pi-hole on prdsrv2.
- Prod: prdsrv1 (prx1/100, .113, Ubuntu, main app host, template-built; Windows until
  2026-09-30, final backup in `archive` on prx2), prdsrv3 (prx2/102, .115, LXC: Uptime Kuma,
  second Pi-hole), prdsrv2 (prx1/101, every Docker
  service: Caddy, Pi-hole, Postgres, SQL Server, Oracle, Paperless, n8n, Metabase...).
- prdsrv2's apps: `/opt/docker` is the git repo github.com/Tendulkarx/homelab-apps (private),
  cloned on the Mac at `~/development/homelab-apps`. Pinned image versions; `.env` files are
  not in git, their values are in 1Password as `prdsrv2-<app>` (section `env`).
- Lab VMs: `terraform/envs/lab/vms.auto.tfvars`, VMID 900-919 = IP 10.69.20.200-219, prx1 default.
- Secrets: 1Password vault `Development`, read at run time by `op run` (Touch ID prompt).
  SSH key `~/.ssh/id_ed25519_homelab`; VM user `turbx` (passwordless sudo); hosts as `root`.
- Why things are the way they are: `docs/decisions.md`. Open work: `docs/proxmox-review.md`.
- Anything touching recovery, backups or rebuilding: follow `docs/disaster-recovery.md`.
- Adding a VM, host, app or capability: follow the recipe in `docs/expanding.md`.

## How to work here

Every change follows **look, preview, apply, verify**:

1. **Look** before acting: `make audit` (read-only, reports land in `audit/`), or read the
   relevant file. Base conclusions on what the reports and commands show.
2. **Preview** every change: `make plan ENV=...` for Terraform, `ARGS="--check --diff"` for
   Ansible. Show O'Neil the preview and wait for his go-ahead before applying anything to prod
   or the hosts.
3. **Apply** with the matching `make` target, never by hand-editing a server, so the repo stays
   the record.
4. **Verify**: re-run the plan (expect `No changes`) or the audit, and report the result.

Then commit with a message saying what changed and why, and add a row to
`docs/decisions.md` for any choice a future reader would question.

## Guardrails

- Prod VMs keep `prevent_destroy` and `reboot_after_update = false`. Restarts are O'Neil's
  call: tell him the command and the expected outage (prdsrv2 = DNS, Caddy and all apps).
- Take a backup before patching or risky changes: `make backup-vm HOST=<ip> VMID=<id>`.
- Terraform only ever runs through `make` (it wraps `op run` for the API tokens).
- Secrets stay in 1Password: read `op://` references, never values; keep tokens, passwords
  and `.env` contents out of files, commits and chat.
- The Terraform token deliberately lacks `Sys.Modify`; host-level settings (VM start order,
  backup jobs, tag colours) belong in `ansible/roles/pve_host`, run as root.
- Writing style for docs and commit messages: UK English; colons and semicolons, no dashes
  as punctuation.
