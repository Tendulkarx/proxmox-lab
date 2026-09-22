# Proxmox review (2026-09-22)

Source: `audit/pve-audit-prx-server-{1,2}.txt` from `scripts/audit-host.sh`.
Both hosts: PVE 9.2.20, kernel 7.0.14-19, no pending updates, SMART passed on every disk,
fstrim and smartmontools active, time in sync. The basics are in good shape. The gaps are below.

## Hardware at a glance

| | prx-server-1 (prx1) | prx-server-2 (prx2) |
|---|---|---|
| Box | Lenovo, i7-7700 (4c/8t) | Apple (Mac mini era), i5-4308U (2c/4t) |
| RAM | 62 GiB, ~28 GiB available | **7.6 GiB, ~0.3 GiB free, swapping** |
| Boot disk | Samsung 850 EVO mSATA 500 GB, **73,305 power-on hours (8.4 years)** | Apple SSD 128 GB |
| `data` disk | Samsung NVMe 512 GB, 50% used, 15% worn | Lexar 1 TB SATA, 9% used |
| `local-lvm` | 338 GB thin pool, **empty** | 50 GB thin pool, **empty** |
| VMs | prdsrv1 (Windows, 6c/16 GB, iGPU passthrough), prdsrv2 (2c/16 GB) | prdsrv3 (4c/8 GB), test1 (2c/2 GB) |

## Must fix

| # | Finding | Why it matters | Fix |
|---|---|---|---|
| M1 | **No backups at all.** No backup jobs on either host and no backup files anywhere | prdsrv2 holds every service and database in the lab. One bad disk or bad upgrade and it is all gone | Tonight: a nightly vzdump job on each host. Next: Proxmox Backup Server (dedup, verify, restore single files), then an offsite copy (see Backups below) |
| M2 | **prx2 is out of memory.** 7.6 GiB physical; prdsrv3 alone is given 8 GB, plus test1 2 GB. 305 MiB free, swap in use | Guests slow down or get OOM-killed; every lab VM on prx2 makes it worse | Make **prx1 the default for lab VMs** (28 GiB free). Drop prdsrv3 to 6 GB unless it needs 8. Move test1 to prx1 |
| M3 | **Stale Debian 12 (bookworm) Proxmox repo on both hosts** alongside the correct trixie ones (`pve-install-repo.list` on prx1, `pve-install-repo.sources` on prx2) | Mixing releases can pull wrong packages on the next upgrade and break the host | Remove the bookworm entries; keep the trixie `proxmox.sources` |
| M4 | **prx2: `libknet1: not correctly installed`** | Half-configured package; a future upgrade can fail midway | `dpkg --audit`, then `apt install --reinstall libknet1` (or `dpkg --configure -a`) |
| M5 | **prdsrv2 has no guest agent** (`agent` not set, agent not responding) | Proxmox can't shut it down cleanly, can't freeze the filesystem for consistent backups, can't show its IP. Worst VM to lack it: it runs the databases | Set `agent: 1` in Proxmox; install `qemu-guest-agent` in the guest (Ansible baseline does this in Phase 4); restart the VM once |

## Should do

| # | Finding | Fix |
|---|---|---|
| S1 | Root SSH login by password allowed on both hosts; no two-factor on `root@pam` web login | Now your key is on both hosts: `PermitRootLogin prohibit-password`. Add TOTP to root@pam (Datacenter, Permissions, Two Factor). Keep root's password in 1Password as break-glass |
| S2 | No notification target configured | Add an email (SMTP) or ntfy/Gotify target so backup failures and SMART warnings actually reach you |
| S3 | Hostnames and search domain still `ob.local`; DNS points at the gateway | Rename to `*.home.arpa` to match the rest of the lab (DNS via the gateway is right for hypervisors, keep that). Needs `pvecm updatecerts --force` after; do it in a quiet window |
| S4 | prdsrv2 disk has no `discard=on` / `ssd=1` | Deleted data inside the VM never gets returned to the host, so the 100 GB qcow2 only ever grows. Add both flags, reboot once |
| S5 | prdsrv2 and prdsrv3 use CPU type `x86-64-v2-AES` | Standalone hosts with no migration: `host` gives the guests the full CPU feature set (AVX2 etc.), which helps SQL Server, Oracle and Postgres |
| S6 | prdsrv2 has only 2 cores but runs Postgres, SQL Server, Oracle, Metabase, Paperless, n8n and more | Raise to 4 cores (prx1 has 8 threads; prdsrv1 has 6) |
| S7 | No start order; all prod VMs start at once on boot | prdsrv2 carries Pi-hole DNS and Caddy, so start it first: prdsrv2 `order=1,up=60`, prdsrv1 `order=2` |
| S8 | prx1 boot SSD has run for 8.4 years | Healthy for now (0 reallocated, 99% wear left), but it is the oldest part. Backups (M1) cover it; plan a replacement |

## Nice to have

| # | Finding | Fix |
|---|---|---|
| N1 | Old kernels piling up: 13 on prx1 (including 6.8 from PVE 8), 8 on prx2 | Keep the running one plus one fallback; purge the rest |
| N2 | `local-lvm` thin pools unused (338 GB on prx1) | On prx1, use it for lab VMs so the NVMe `data` disk stays for prod; or remove it and grow root |
| N3 | Tags only on Terraform VMs; no colours defined | Tag prod VMs (`prod`, `docker`, `windows`/`linux`) and set a colour map (below). Terraform manages the tags once prod is imported in Phase 4 |
| N4 | prdsrv1 still has the `virtio-win` ISO attached (`ide0`) | Detach it |
| N5 | Proxmox firewall disabled at datacenter level although VM NICs have `firewall=1` | Fine while UniFi does the firewalling; leave as is or enable deliberately later |

## Suggested tag colours

Set once per host (standalone, so twice):

```bash
pvesh set /cluster/options --tag-style 'color-map=prod:c62828:ffffff;lab:2e7d32:ffffff;terraform:5c6bc0:ffffff;docker:1e88e5:ffffff;windows:0078d4:ffffff;linux:f57c00:000000;template:757575:ffffff,shape=circle,ordering=config'
```

## Backups: proposed design

1. **Now:** nightly vzdump, snapshot mode, zstd, to `data` on the same host, keep 7 daily and 4 weekly.
   Protects against a bad upgrade or a broken VM; not against a dead disk.
2. **Next:** Proxmox Backup Server as a VM on prx1 (RAM to spare), datastore on prx2's 1 TB disk
   (820 GB free) via NFS, or the reverse. Both hosts back up to it, so each host's backups live on
   the other host's disk. Deduplication makes this cheap; nightly verify jobs prove restores work.
3. **Offsite:** sync the PBS datastore (or the Paperless and Postgres dumps) to Google Drive with
   rclone, matching the approach already agreed for Paperless-ngx.
