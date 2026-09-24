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

## Re-audit (2026-09-22, 22:37)

| Item | Before | Now |
|---|---|---|
| M1 Backups | none | Nightly job 02:30, snapshot, zstd, keep-last=2, lab excluded. **First run tonight; no backup exists yet** |
| M2 prx2 memory | 305 MiB free, swapping | prdsrv3 8 GB to 6 GB, test1 moved to prx1: ~1 GiB available. Still tight; keep prx2 for prdsrv3 only |
| M3 Bookworm repos | both hosts | gone |
| M4 libknet1 | "not correctly installed" | cosmetic (renamed libknet1t64 on PVE 9); only libknet1t64 installed |
| M5 prdsrv2 guest agent | off | on and responding |
| S1 Root SSH | password allowed | key only (drop-in overrides sshd_config). **TOTP on root@pam still to do** |
| S2 Alerts | none | **still none** (ntfy ready in `pve_host`, needs a topic URL) |
| S3 Hostnames | `*.ob.local` | `*.home.arpa`, node certs reissued (valid to 2028) |
| S4 prdsrv2 discard/SSD | off | on |
| S5 CPU type | x86-64-v2-AES on prdsrv2/3 | `host` on all |
| S6 prdsrv2 cores | 2 | 4 |
| S7 Start order | none | prdsrv2 1st (60 s), prdsrv1 2nd; prdsrv3 1st on prx2 |
| N1 Old kernels | 13 and 8 | 2 each (running + fallback); ~10 GB freed on prx1 root |
| N2 local-lvm | unused | lab VMs on prx1 use it |
| N3 Tags | none on prod | tags + colour map on both hosts |
| N4 prdsrv1 ISO | attached | detached |

### New findings

- **Backup exclusion bug (fixed in code):** prx2's job excludes 901 to 919 but not 900. Destroying
  test1 with Proxmox's "purge" option also removed VMID 900 from the job's exclude list.
  Lab module now sets `purge_on_destroy = false`; `make hosts ARGS="--tags backups"` restores the list.
- **Failed root login from prdsrv2 to prx2** (`authentication failure; rhost=10.69.20.114
  user=root@pam`, 19:28). Something on prdsrv2 (most likely the Homepage or Uptime Kuma Proxmox
  integration) logs in as root with a wrong or old password. Give it a read-only API token
  (role `PVEAuditor`) instead of root.
- prdsrv1 logs `vfio-pci: Cannot read device rom at 0000:00:02.0` on start. Common with Intel
  iGPU passthrough and harmless if the VM works (agent responds). If display output ever fails,
  set `rombar=0` on hostpci0.

## VM audit (2026-09-22, 23:00): prdsrv2, prdsrv3, test1

test1: clean. Both hosts: clean apart from the items above.

| # | VM | Finding | Cause | Fix |
|---|---|---|---|---|
| V1 | prdsrv3 | `mssql_db` crash-looping (40 restarts): `PalInstanceId: Unable to read instance id from file` then `PAL initialization failed. Error: 101` | Almost certainly the disk-full episode left SQL Server's instance-id file empty/corrupt | Back up the volume, move the instance-id file aside, start (see below) |
| V2 | prdsrv2 | Redis (`paperless-broker`): 14,050 x `Background saving error` in 24 h; last good save 19 days ago | Redis cannot write `dump.rdb` (permissions on the data folder, or fork failing). With default `stop-writes-on-bgsave-error yes` Redis refuses writes, which can stall Paperless document processing | Read the line before the error, fix ownership or overcommit |
| V3 | prdsrv2 | fail2ban failed at boot: `jail.local line 278: section 'sshd' already exists` | Duplicate `[sshd]` block in `/etc/fail2ban/jail.local` | Remove the duplicate, restart |
| V4 | both | 152 / 162 pending updates (117 / 108 security) | Auto-updates were off (prdsrv2) or failed on the full disk (prdsrv3) | One supervised `apt full-upgrade` per VM, then reboot |
| V5 | both | No Docker log rotation | No `/etc/docker/daemon.json` | Add it in a maintenance window (needs a Docker restart) |
| V6 | both | No database dumps; `/opt/docker` on prdsrv2 is **not** a git repo (notes say it was); prdsrv3's stack lives in `/home/turbx/db-stack` | | Nightly dumps per engine; `git init` both stack folders |
| V7 | prdsrv3 | Duplicates prdsrv2's Postgres/SQL Server/Oracle with 6-month-old images, on the 7.6 GB host; avahi running; 2 swap files | | Decide: retire prdsrv3 or give it a distinct purpose |
| V8 | both | Database ports reachable LAN-wide (prdsrv3 UFW allows 5432/1433/1521/5500 from anywhere; prdsrv2 Postgres on 0.0.0.0) | Docker published ports bypass UFW anyway | Bind to the LAN IP only; rely on UniFi rules |
| V9 | prdsrv2 | Most images on `:latest` | | Pin versions (already planned in the vault notes) |

Noise, not problems: Arcane `context canceled` (page navigation), Metabase `reset from ERROR state` (INFO lines), prdsrv3 `postgres_db` errors (all from the disk-full episode; healthy now).

## Open items (2026-09-24)

| Item | Detail | Action |
|---|---|---|
| prdsrv2 serial port pending | Added in Proxmox, applies at the next full stop and start (`qm pending 101` shows `serial0`) | Next time prdsrv2 needs a restart (e.g. after `make patch`), do a full stop and start: `ssh prx1 'qm shutdown 101 && qm start 101'`. Outage 1 to 2 minutes: DNS, Caddy, all apps |
| prdsrv2 locale | `/etc/default/locale` is `en_US.UTF-8` (a link to `/etc/locale.conf`); `vm_baseline` wants `en_GB.UTF-8`. Left alone on 2026-09-24 | Decide: accept `en_GB` (services pick it up on restart; affects date and number formats) or set `locale: en_US.UTF-8` for prdsrv2 in the inventory |
