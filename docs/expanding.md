# Expanding proxmox-lab

Recipes for growing the lab, from the everyday to the ambitious. Each one keeps the same
rule: the change lives in the repo first, then `make` applies it. With Claude Code you can
simply ask for any of these; the recipe is what it will follow.

## Everyday

### A lab VM

Add one line to `terraform/envs/lab/vms.auto.tfvars`, then `make up` and `make configure`:

```hcl
web1 = { vmid = 902, cores = 4, memory_mb = 4096, disk_gb = 40, tags = ["docker"] }
```

Or in Claude Code: `/new-vm web1 4 4096 40`. Remove it by deleting the line and `make up`.

### Change a prod VM's hardware

Edit its block in `terraform/envs/prod/prod.tf` (cores, memory, disk size, tags), then
`make plan ENV=prod` and `make up ENV=prod`. CPU type, cores beyond hot-plug and most disk
flags wait for you to stop and start the VM. Disk size can only grow.

### Change something inside every VM

Edit the relevant role (`vm_baseline` for system settings, `shell` for the prompt and tools,
`docker` for Docker), then `make configure ENV=lab` first, check it, then `ENV=prod`.
Preview prod with `ARGS="--check --diff"`.

### Change something on the hosts

Edit `ansible/roles/pve_host` (defaults for values, tasks for new behaviour), then
`make hosts-check` and `make hosts`. Use `--tags <tag>` to run one part only.

## New permanent (prod) VM

Built from the template, so it is fully reproducible from code:

1. Add a resource to `terraform/envs/prod/prod.tf` using the same module as the lab, but with
   `prevent_destroy` and `reboot_after_update = false`. Pick a VMID and IP outside the lab
   ranges and record both in `docs/decisions.md`.
2. Add it to `ansible/inventory/prod.yml`.
3. `make plan ENV=prod`, `make up ENV=prod`, `make configure ENV=prod NAME=<vm>`.
4. Add a UniFi DNS record if it needs a name.

## Deploying applications from the repo (the next big step)

Today prdsrv2's Docker stacks are edited by hand in `/opt/docker`. Bringing them into the repo
makes them rebuildable (see `docs/disaster-recovery.md`, gap G2):

1. Copy each `/opt/docker/<stack>/docker-compose.yml` (and non-secret config such as the
   Caddyfile) into `stacks/<stack>/` in this repo. Secrets stay out: each stack's `.env`
   becomes an `.env.op` of `op://` references, or an Ansible-vault file.
2. Add an Ansible role `stacks` that, per host, copies the stack files, renders `.env` from
   1Password, runs `docker compose up -d`, and keeps a list of which stacks belong to which VM
   in `inventory/host_vars/<vm>.yml`.
3. Pin every image to a version (no `:latest`), so a redeploy gives the same result.
4. From then on: edit in the repo, `make configure ENV=prod`, and the VM follows.

## New Proxmox host

1. Install PVE 9, set its static IP on `vmbr0`, create and mount its `data` disk (see
   `docs/disaster-recovery.md`, "Rebuild a host").
2. Run `scripts/prep-host.sh` on it; save the token in 1Password as `proxmox-prx3-terraform`.
3. Add it to `.env.op`, a provider alias in each `terraform/envs/*/providers.tf`, a module
   block in `envs/lab/main.tf`, and `ansible/inventory/proxmox.yml`.
4. `make hosts`.

Clustering (one UI, live migration, shared config) is possible later, but needs unique
VMIDs across hosts (prdsrv1 and the old prdsrv3 both used 100) and ideally 3 nodes or a
QDevice for quorum. Keep standalone until there is a reason.

## Other directions

| Idea | How it fits |
|---|---|
| Proxmox Backup Server | A VM on prx2 (1 TB disk); both hosts' backup jobs point at it. Top priority, see DR |
| LXC containers | bpg's `proxmox_virtual_environment_container` resource; lighter than VMs for single services. Christian Lempa's `proxmox-lxc` template is the model |
| Packer golden image | Christian's `proxmox-iso-ubuntu`: builds template 9000 from the ISO with everything pre-baked, replacing `prep-host.sh`'s template step |
| Other OSes | Another template (e.g. Debian 13 as 9001) and a `template_id` per VM |
| Windows in Ansible | WinRM or OpenSSH on prdsrv1, a `windows` inventory group, `ansible.windows` modules |
| Semaphore UI | A management VM running Ansible/Terraform on a schedule, so the lab no longer depends on the Mac being awake |
| Monitoring | Uptime Kuma already runs; add node-exporter via Ansible and Grafana/Prometheus as a stack |
| Remote repo + CI | Push to a private GitHub repo; a CI job can run `terraform validate` and `ansible-lint` on every change |

## House rules when expanding

- One source of truth: if a setting exists in code, change it in code, never in the UI.
- Preview before apply, backup before risky changes, verify after.
- Record every non-obvious choice in `docs/decisions.md`.
- Keep secrets in 1Password; the repo stores references only.
