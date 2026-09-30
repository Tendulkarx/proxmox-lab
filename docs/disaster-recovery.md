# Disaster recovery and full rebuild

How to get the lab back after anything from a broken VM to losing everything, and how to
rebuild from bare metal by choice. Written 2026-09-22. **Read "Gaps" first: it lists what
cannot be recovered today and the order to close it.**

## What you need to recover anything

| Item | Where it lives today | Survives losing the Mac? |
|---|---|---|
| This repo (all code and docs) | Mac, and github.com/Tendulkarx/proxmox-lab (private) since 2026-09-25 | Yes |
| Proxmox API tokens, root and turbx passwords | 1Password (`proxmox-vm-console` is turbx's console password on every VM) | Yes |
| SSH key `id_ed25519_homelab` | Mac, and 1Password (SSH Key item `id_ed25519_homelab`, vault Development, since 2026-09-24) | Yes |
| Terraform state | Mac only, git-ignored | No, but rebuildable by re-import |
| Dotfiles | `~/development/dotfiles` | Yes, if pushed: github.com/Tendulkarx/dotfiles (private) |
| App stacks (`/opt/docker/*` on prdsrv2) | github.com/Tendulkarx/homelab-apps (private; `/opt/docker` is the working copy, the Mac has a clone). `.env` values in 1Password as `prdsrv2-<app>` | Yes (app data: only in the VM backups) |
| VM backups (nightly 02:30, keep 2) | `data` disk of the same host, and prx1's copied to prx2 (`prx1-copy`) at 06:00 | Survives one host's disk; nothing off-site yet (gap G3) |
| Network (UniFi), DNS (Cloudflare) | their cloud consoles | Yes |
| Build notes | `agentic-os/07-home-tech` | Yes, if pushed (same repo) |

Break-glass access when SSH keys are gone: each host's web UI or physical console as
`root@pam` (password in 1Password), then the VM console in the Proxmox UI as `turbx` with the
`proxmox-vm-console` password from 1Password (set on every VM by `vm_baseline`; the console
accepts it, SSH never does). Use Console > **xterm.js** where the VM has a serial port (template
VMs; prdsrv2 after its next restart): it accepts paste. noVNC doesn't, so type it there.

## Scenarios

### 1. A lab VM is broken (minutes)

```bash
make down NAME=tstsrv1 && make up && make configure NAME=tstsrv1
```

### 2. A prod VM is broken but the host is fine (15 to 60 minutes)

Configuration drift (a setting changed by hand): `make configure ENV=prod NAME=prdsrv2`.

Broken OS or data: restore last night's backup over it. Proxmox UI: VM → Backup → pick the
backup → Restore. Or on the host:

```bash
ssh -i ~/.ssh/id_ed25519_homelab root@10.69.20.130
pvesm list data --content backup --vmid 101          # pick the file
qm stop 101
qmrestore /mnt/pve/data/dump/vzdump-qemu-101-<date>.vma.zst 101 --force --storage data
qm start 101
```

Then on the Mac: `make plan ENV=prod` (expect `No changes`) and `make audit-vms`.
You lose everything since the backup (up to 24 hours).

To inspect a backup without touching the live VM, restore it to a spare VMID instead
(e.g. `qmrestore <file> 919 --storage local-lvm --unique`), boot it with its network
disconnected, look, then delete it.

### 3. A host's `data` disk dies (VMs AND their backups are on it)

**Today this loses those VMs.** Their only backups sit on the same disk. The fix is gap G3
(backups on the other host and offsite); once that exists, this becomes scenario 2 after
replacing the disk and re-adding the storage (see "Rebuild a host", step 3).

### 4. A host's boot disk dies (prx1's is the 8-year-old SATA SSD)

The VM disks on the NVMe `data` disk survive; the VM definitions in `/etc/pve` do not.

1. Replace the boot disk and reinstall Proxmox (see "Rebuild a host"). **Do not format the
   data disk**: mount the existing one and re-add the storage.
2. `make hosts` restores repos, SSH, backup job, tags, start order.
3. Get the VMs back, either way:
   - **From backup** (simplest): `qmrestore` as in scenario 2; each backup carries its VM's config.
   - **From the surviving disks**: recreate each VM with its old VMID and hardware (the values
     are in `terraform/envs/prod/prod.tf`), then `qm rescan --vmid <id>` finds the disk on
     `data` as "unused"; attach it as `scsi0` and set it as the boot disk.
4. Re-run `scripts/prep-host.sh` (new token: update the 1Password item), `make plan ENV=prod`.

### 5. The Mac is lost or wiped

1. Tools: `brew install hashicorp/tap/terraform 1password-cli ansible`, sign in to 1Password.
2. Repo: `git clone git@github.com:Tendulkarx/proxmox-lab.git ~/development/proxmox-lab`.
3. SSH key: in 1Password open `id_ed25519_homelab`, export the private key to
   `~/.ssh/id_ed25519_homelab` (`chmod 600`) and save its public key as `.pub` next to it. Only
   if that item is gone too: `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_homelab`, then log in to each host's web
   UI shell as root and append the new public key to `/root/.ssh/authorized_keys`; do the same
   for turbx on each VM through the Proxmox VM console.
4. Terraform state:
   - prod: `make init ENV=prod`, then `make plan ENV=prod`. `imports.tf` re-adopts the VMs;
     expect imports and 0 changes.
   - lab: lab VMs are disposable: delete them in the UI, then `make up`.
5. `make check`, `make audit`.

### 6. Everything is gone, or you want to start fresh

Follow "Full rebuild" below.

## Full rebuild from bare metal

The order matters: each phase depends on the one before. Allow an evening for phases A to E,
then however long the data restore takes.

### A. The Mac

Scenario 5 steps 1 to 3 (tools, repo, SSH key). Check the 1Password items exist:
`proxmox-prx1-terraform`, `proxmox-prx2-terraform` in vault `Development`.

### B. Network

UniFi: VLAN 20 `10.69.20.0/24`, gateway `.1`, DHCP pool ending at `.199` (lab uses
`.200-.219`), hosts `.130` and `.131` static. Full detail: `agentic-os/07-home-tech/
Home-Tech-Resources/home-network-reference.md`.

### C. Rebuild a host (repeat per host)

1. **Install Proxmox VE 9** from USB. Target: the boot disk (prx1: Samsung 850 EVO mSATA;
   prx2: Apple 128 GB SSD). Hostname `prx-server-1.home.arpa` (or `-2`), IP `10.69.20.130/24`
   (or `.131`), gateway and DNS `10.69.20.1`.
2. **Repositories**: in the UI, Updates → Repositories: disable `pve-enterprise`, add
   `pve-no-subscription`. Then `apt update && apt full-upgrade`, reboot.
3. **The `data` disk** (prx1: NVMe `nvme0n1`; prx2: Lexar 1 TB `sda`).
   - Fresh disk only, this erases it: `mkfs.ext4 -L data /dev/nvme0n1p1` (create the partition
     first with `fdisk` if needed).
   - Mount it (existing or fresh):
     ```bash
     mkdir -p /mnt/pve/data
     echo "UUID=$(blkid -s UUID -o value /dev/nvme0n1p1) /mnt/pve/data ext4 defaults 0 2" >> /etc/fstab
     mount -a
     pvesm add dir data --path /mnt/pve/data --is_mountpoint 1 \
       --content images,rootdir,iso,vztmpl,backup,snippets,import --nodes prx-server-1
     ```
4. **prx1, only if a VM needs the iGPU again** (Windows prdsrv1 used it until 2026-09-30).
   Kernel command line must include
   `intel_iommu=on iommu=pt i915.enable_guc=3 i915.max_vfs=7`. On a GRUB install: add to
   `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`, `update-grub`; on systemd-boot: add to
   `/etc/kernel/cmdline`, `proxmox-boot-tool refresh`. Reboot and check
   `dmesg | grep -i 'IOMMU enabled'`.
5. **Your key**: `ssh-copy-id -i ~/.ssh/id_ed25519_homelab.pub root@10.69.20.130`.
6. **Prep**: `scp scripts/prep-host.sh root@<ip>:` then `ssh root@<ip> bash prep-host.sh`.
   Paste the printed token into the 1Password item (replace the old value).
7. On the Mac: `make hosts-check`, `make hosts`.

### D. Terraform

```bash
make init && make init ENV=prod
```

### E. Prod VMs

Two routes; today only route 1 is possible for prdsrv2. prdsrv1 and prdsrv3 are rebuilt
from Terraform and Ansible (route 2), their app data from backups.

1. **Restore from backup** (needs a surviving backup: gap G3): copy the backup files to the
   host's `/mnt/pve/data/dump/`, `qmrestore` each one with its original VMID, start them.
   Then `make plan ENV=prod`: `imports.tf` adopts them, expect 0 changes.
2. **Rebuild from code** (once gap G4 is closed): Terraform creates prdsrv2 fresh
   from the template, `make configure ENV=prod` installs baseline, shell and Docker, the
   `git clone` homelab-apps to `/opt/docker`, `op inject` each `.env`, `docker compose up -d`
   per app, and the latest database dumps are loaded back in.

Then `make hosts ARGS="--tags startup,backups"`, and check DNS (Pi-hole) and Caddy
before anything else, because every other service depends on them.

### F. Lab and verification

```bash
make up && make configure
make audit          # or /audit in Claude Code
```

Done when every host and VM report is clean, `make plan` and `make plan ENV=prod` both say
`No changes`, and Homepage shows every service up.

## Gaps (what stops a full recovery today), in the order to close them

| # | Gap | Risk | Fix | Effort |
|---|---|---|---|---|
| ~~G1~~ | ~~Repo exists only on the Mac~~ | **Closed 2026-09-25**: pushed to github.com/Tendulkarx/proxmox-lab (private) | Push after every commit | |
| G3 | Nothing off-site. (Same-disk part closed 2026-09-27: prx1's backups are mirrored to prx2 after each clean run) | Losing both hosts (fire, theft, surge) loses everything | Encrypted rclone upload: database dumps to Google Drive (free); VM backups to a service with room for about 52 GB | an evening |
| ~~G2~~ | ~~prdsrv2's app stacks are not in git~~ | **Closed 2026-09-27**: `/opt/docker` is the repo homelab-apps, images pinned, secrets in 1Password (`op inject -i .env.example -o .env`) | Deploying it with Ansible was dropped: Arcane edits the files in place (decision 54) | |
| G4 | No database dumps | Can only restore a whole VM, not one database; crash-consistent at best | Nightly `pg_dump`, SQL Server `BACKUP DATABASE`, Oracle `expdp` into a backup folder picked up by the VM backup | an evening |
| G5 | Some host config is manual (data storage, fstab, iGPU kernel flags, network) | Rebuild relies on this document being right | Move storage and kernel cmdline into the `pve_host` role | an evening |
| G6 | `agentic-os` has a GitHub remote, but its last commit was 8 days ago | Recent dotfile and note changes exist only on the Mac | Commit and push it regularly | 5 min |
| G7 | prdsrv1 (Windows) exists only as a VM and its backup | No rebuild path | **Closed 2026-09-30**: Windows retired (final backup in `archive` on prx2); prdsrv1 is Linux, built from code | done |
| G8 | Restores have never been tested | You find out at the worst moment | Quarterly drill: restore prdsrv2's backup to VMID 919 with the NIC disconnected, boot it, check the apps' data, delete it | 30 min each quarter |

Since 2026-09-27 a failed NVMe on prx1 is survivable (restore from `prx1-copy` on prx2, though
prx2 has only 7.6 GB RAM, so restore prdsrv2 with less memory). The worst case now is losing
both hosts at once: G3 (off-site) and G4 (dumps) are the priority.

## Drills

| When | Drill |
|---|---|
| After every major change | `make audit`, `make plan` in both envs shows `No changes` |
| Monthly | Check the nightly backups exist and are recent: `pvesm list data --content backup` on each host |
| Quarterly | Restore test (G8); rebuild a lab VM from scratch; confirm 1Password items still work |
| Yearly | Walk through scenario 5 on paper: could you do it with only 1Password and the remote repo? |
