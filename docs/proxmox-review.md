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
| prdsrv2 serial port | Done 2026-09-24: prdsrv2 restarted, `serial0` live, serial-getty active, 14 containers up, Pi-hole answering | None: Console > xterm.js now works on prdsrv2 |
| prdsrv2 locale | Done 2026-09-24: set to `en_GB.UTF-8` like the other VMs. The baseline task was also fixed: it replaced the `/etc/default/locale` link, so tstsrv1's system locale had stayed `C.UTF-8` | Running services switch to it at their next restart |
| Backup of prdsrv1 failed 2026-09-24 | `data` was 92% full; prdsrv1's 130 GB archive didn't fit | **Fixed 2026-09-24**: prdsrv2 trimmed (97 to 40 GB); prdsrv1 disk given discard + ssd and restarted, free space zeroed with SDelete (Windows' manual "Retrim" reports skipped, but deletes are passed on, which is what shrank it): image 121 to 36 GB. `data` 60% used, 182 GB free. Fresh prdsrv1 backup 34.9 GB (was 130). Still to do: alerts (S2) |
| prdsrv1 iGPU | Used for picture quality and speed over Remote Desktop. Full passthrough gives Code 43 (no ROM). Plan: GVT-g, which shares the HD 630 with the VM and is the supported route for this generation (prx1's kernel has `kvmgt` and `i915.enable_gvt`) | One maintenance window, prx1 reboot (prdsrv2 and prdsrv1 down about 5 minutes; also applies prdsrv1's pending disk change): prx1 GRUB `i915.enable_gvt=1` instead of `i915.enable_guc=3 i915.max_vfs=7`, module `kvmgt`; prdsrv1 `hostpci0: 0000:00:02.0,mdev=i915-GVTg_V5_4`. Rollback: restore both and reboot. The Intel Windows driver may need an older version if Code 43 stays |
| prdsrv1 IP | Moving from 10.69.20.69 (DHCP) to a fixed 10.69.20.113, next to prdsrv2. First try 2026-09-24 failed safely (Windows "Generic failure"; the script reverted to DHCP in 5 s). The Mac's VPN (utun10) only routes known addresses: .113 was unreachable from it | Add 10.69.20.113 (or all of 10.69.20.0/24) to the VPN's allowed resources, then run `scripts/windows/prdsrv1-network.ps1` (now uses netsh). Then update the SSH config, README and the prod IP validation |

## Re-audit (2026-09-26, 23:32): both hosts, prdsrv2, tstsrv1

Source: `make audit`. prdsrv3 is retired and test1 is now tstsrv1, so `audit/vm-prdsrv3.txt` and
`audit/vm-test1.txt` are old reports. prdsrv1 (Windows) is not covered by the VM audit.

### Fixed since the last review

| Item | Evidence now |
|---|---|
| M1 Backups exist | Nightly job on both hosts; prdsrv1, prdsrv2 and the template backed up 25 and 26 Sep |
| M2 prx2 memory | prdsrv3 retired: `Mem: 7.6Gi ... 6.2Gi available` |
| V1, V7 prdsrv3 | Retired (decision 35) |
| V4 prdsrv2 updates | Auto-updates on (`unattended-upgrades active`); 39 pending, 1 security (was 152 / 117) |
| Audit tooling | `make audit` refused tstsrv1 after its rebuild: lab VMs were checked against `~/.ssh/known_hosts`. New key verified through the guest agent (`SHA256:uW9C...dtA`), stale entry removed, `audit-vms` now reads `known_hosts.proxmox-lab` first |

### Still open

| # | Evidence | Fix |
|---|---|---|
| V2 | prdsrv2 `paperless-broker: 14413 error lines in 24h`: `Failed opening the temp RDB file ... Permission denied` | Redis can't write `/data`, so it may refuse writes and stall Paperless. Fix the ownership of the broker's data folder (Redis runs as UID 999), restart the broker |
| V3 | prdsrv2 `fail2ban: failed`, `section 'sshd' already exists` (jail.local line 278) | Remove the duplicate `[sshd]` block; manage `jail.local` from Ansible |
| S2 | `notifications.cfg: none` on both hosts | ntfy target from `pve_host` (needs a topic URL). Nothing tells you a backup or disk failed |
| Old root login | prx1 journal: `authentication failure; rhost=::ffff:10.69.20.114 user=root@pam` 07:53 and 08:08 | Homepage on prdsrv2 has `config/proxmox.yaml`, the likely source. Give it a `PVEAuditor` API token on each host |
| S1 | `root@pam enabled=1 tfa=False` on both | TOTP on root@pam; password stays in 1Password as break-glass |
| V5 | prdsrv2 `no daemon.json (container logs never rotate)` | Same `daemon.json` as tstsrv1 (10 MB x 3); needs a Docker restart |
| V6 | prdsrv2 `/opt/docker`: `not a git repository`; no database dumps | `git init` the stack folder; nightly dumps for Postgres, SQL Server, Oracle |
| V8 | prdsrv2 `tcp 0.0.0.0:5432` (Postgres); 1433 and 1521 already bound to 10.69.20.114 | Bind Postgres to 10.69.20.114 like the others |
| V9 | prdsrv2 11 of 14 images on `:latest` | Pin versions |
| S8 | prx1 boot SSD `Power_On_Hours 73403` (8.4 years), wear 99% left | Plan a replacement |
| prdsrv1 iGPU (GVT-g) | prx1 cmdline still `i915.enable_guc=3 i915.max_vfs=7` | As planned above |
| N5 | `pve-firewall: disabled/running` | Deliberate while UniFi firewalls |

### New

| # | Evidence | Why it matters | Fix |
|---|---|---|---|
| B1 | prx1 backups go to `data` on prx1 (`nvme0n1p1 /mnt/pve/data`), the same disk as prdsrv1 and prdsrv2 | One NVMe failure loses the VMs and every backup of them. Step 2 of the backup design (other host's disk) was never done | Copy prx1's backups to prx2's `data` (`867G` free, prx2 is idle) nightly; later PBS as designed. Then retention can go beyond `keep-last=2` |
| B2 | prdsrv1 `guest agent: NOT responding`; journal `VM 100 qga command failed ... got timeout` | No clean shutdown from Proxmox and no VSS freeze, so its nightly backups are crash-consistent only | Check the `QEMU-GA` service and virtio-win guest tools inside prdsrv1 |
| B3 | prdsrv2 `REBOOT REQUIRED linux-image-6.8.0-142-generic`; both hosts `pending upgrades: 4` | Kernel fixes aren't live until a restart | `make patch ENV=prod NAME=prdsrv2` in a window of O'Neil's choosing (DNS, Caddy and all apps down about 2 minutes); host upgrades via `pve_host` |
| B4 | Template 9000 backed up nightly on both hosts (`vzdump-qemu-9000-...` 0.7 GB each) | Rebuilt by `make`, so the copies only use space | Decide: add 9000 to the job's exclude list |
| B5 | prx2 holds `vzdump-qemu-100-2026_09_22-23_11_48` (18 GB): prdsrv3's final backup | Nothing prunes it | Decide: keep until a set date, then delete |

### Done 2026-09-27

- **B1:** prx1's backups are mirrored to prx2 at 06:00 (`pve-backup-copy`), only when the last
  nightly run logged no errors. First copy 00:11: 19 files, checksums match; prx2 shows them as
  storage `prx1-copy`. `make audit` reports the copy's last run.
- **B4:** template 9000 excluded from the nightly job. Its two old backups per host stay until deleted.
- **B5:** prdsrv3's final backup deleted from prx2.
- tstsrv1 destroyed; no lab VMs.
- **V2 cause found:** Redis runs as UID 999, its folder `/opt/docker/paperless/data/redis` is
  owned by 1000. `stop-writes-on-bgsave-error` is `no`, so Paperless isn't stalled, but nothing
  has been saved since 3 Sep. Fix: `sudo chown -R 999:999` on that folder, then `redis-cli BGSAVE`.
