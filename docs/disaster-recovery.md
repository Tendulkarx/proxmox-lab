# Disaster recovery and full rebuild

How to get the lab back after anything from a broken VM to losing everything, and how to
rebuild from bare metal by choice. Written 2026-09-22. **Read "Gaps" first: it lists what
cannot be recovered today and the order to close it.**

## What you need to recover anything

| Item | Where it lives today | Survives losing the Mac? |
|---|---|---|
| This repo (all code and docs) | Mac only, local git | **No** (gap G1) |
| Proxmox API tokens, root and turbx passwords | 1Password | Yes |
| SSH key `id_ed25519_homelab` | Mac only | No, but replaceable (see scenario 5) |
| Terraform state | Mac only, git-ignored | No, but rebuildable by re-import |
| Dotfiles | `agentic-os/.../dotfiles` | Yes, if pushed: agentic-os has a GitHub remote (`Tendulkarx/agentic-os`) |
| App stacks (`/opt/docker/*` on prdsrv2) | prdsrv2 only, not in git | **No** (gap G2) |
| VM backups (nightly 02:30, keep 2) | `data` disk of the **same** host | **No** if that disk dies (gap G3) |
| Network (UniFi), DNS (Cloudflare) | their cloud consoles | Yes |
| Build notes | `agentic-os/07-home-tech` | Yes, if pushed (same repo) |

Break-glass access when SSH keys are gone: each host's web UI or physical console as
`root@pam` (password in 1Password), then the VM console in the Proxmox UI as `turbx`
(password login works on the console; only SSH is key-only).

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
2. Repo: clone it from the private remote (**needs gap G1 closed**).
3. New SSH key: `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_homelab`. Log in to each host's web
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
4. **prx1 only: iGPU passthrough for prdsrv1.** Kernel command line must include
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

Two routes; today only route 1 is possible for prdsrv2 and prdsrv1.

1. **Restore from backup** (needs a surviving backup: gap G3): copy the backup files to the
   host's `/mnt/pve/data/dump/`, `qmrestore` each one with its original VMID, start them.
   Then `make plan ENV=prod`: `imports.tf` adopts them, expect 0 changes.
2. **Rebuild from code** (once gaps G2 and G4 are closed): Terraform creates prdsrv2 fresh
   from the template, `make configure ENV=prod` installs baseline, shell and Docker, the
   `stacks` role deploys every app, and the latest database dumps are loaded back in.

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
| G1 | Repo exists only on the Mac | Lose the Mac, lose all the code and docs | Push to a private GitHub (or Gitea) repo; commit after every change | 5 min |
| G3 | Backups live on the same disk as the VMs; nothing offsite | One disk failure loses VMs and backups together | Proxmox Backup Server on prx2 (1 TB); prx1 backs up to it. Then sync to Google Drive or a cloud bucket | an evening |
| G2 | prdsrv2's app stacks are hand-managed and not in git | Rebuilding prdsrv2 without a backup means recreating every stack by hand | `stacks/` folder plus an Ansible `stacks` role; secrets via 1Password; pin image versions | a weekend |
| G4 | No database dumps | Can only restore a whole VM, not one database; crash-consistent at best | Nightly `pg_dump`, SQL Server `BACKUP DATABASE`, Oracle `expdp` into a backup folder picked up by the VM backup | an evening |
| G5 | Some host config is manual (data storage, fstab, iGPU kernel flags, network) | Rebuild relies on this document being right | Move storage and kernel cmdline into the `pve_host` role | an evening |
| G6 | `agentic-os` has a GitHub remote, but its last commit was 8 days ago | Recent dotfile and note changes exist only on the Mac | Commit and push it regularly | 5 min |
| G7 | prdsrv1 (Windows) exists only as a VM and its backup | No rebuild path | Accept (backup only), or document its setup | optional |
| G8 | Restores have never been tested | You find out at the worst moment | Quarterly drill: restore prdsrv2's backup to VMID 919 with the NIC disconnected, boot it, check the apps' data, delete it | 30 min each quarter |

Until G1 and G3 are closed, the realistic worst case is: **a failed NVMe on prx1 loses
prdsrv2 and every service on it, with no way back.** Those two are the priority.

## Drills

| When | Drill |
|---|---|
| After every major change | `make audit`, `make plan` in both envs shows `No changes` |
| Monthly | Check the nightly backups exist and are recent: `pvesm list data --content backup` on each host |
| Quarterly | Restore test (G8); rebuild a lab VM from scratch; confirm 1Password items still work |
| Yearly | Walk through scenario 5 on paper: could you do it with only 1Password and the remote repo? |
