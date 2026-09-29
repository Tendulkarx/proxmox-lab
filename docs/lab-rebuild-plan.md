# Lab rebuild plan

Agreed 2026-09-29. Windows prdsrv1 is retired and replaced by a Linux server that becomes the
main app host; prdsrv2 becomes the database server; prx2 gets Proxmox Backup Server and a small
infra container; backups gain history and an off-site copy. Every step follows the house rule
in `CLAUDE.md`: look, preview, apply, verify, then commit. Nothing touching prod or a host is
applied without O'Neil's go-ahead, and restarts or shutdowns are always his call.

## Where things stand (measured 2026-09-29)

| Host | Hardware | Load |
|---|---|---|
| prx1 | i7-7700, 4 cores / 8 threads, 62 GB RAM; NVMe 512 GB (`data`, VMs and backups, 183 GB used); SATA SSD 500 GB (`local-lvm`, 338 GB, unused; boot disk has run 8.4 years) | load 0.4; 28 GB RAM free |
| prx2 | i5-4308U, 2 cores / 4 threads, 7.6 GB RAM; SSD 1 TB (`data`, 106 GB used, the prx1 copy); Apple SSD 128 GB (boot) | idle; 6.4 GB RAM free; both SSDs healthy |

| VM | Size | Actual use |
|---|---|---|
| prdsrv1 (VMID 100, Windows 11) | 6 vCPU, 16 GB, 128 GB, Intel iGPU passthrough | Remote Desktop PC; backup 39.4 GB |
| prdsrv2 (VMID 101, Ubuntu 24.04) | 4 vCPU, 16 GB, 100 GB | 6 GB RAM, load 0.25, 42 GB disk; backup 14.4 GB |

prdsrv2 app memory: Oracle 2.2 GB, Metabase 1.2 GB, SQL Server 0.9 GB, Paperless 0.8 GB,
Pi-hole 0.4 GB, n8n 0.4 GB, Tika 0.3 GB, Postgres 0.3 GB, Uptime Kuma 0.2 GB, the rest small.
Irreplaceable data is small: databases about 190 MB, Paperless 21 MB, n8n 6 MB, Uptime Kuma 13 MB.

The lab has spare capacity; its weak points are resilience and backups: every service shares
one VM, Uptime Kuma runs on the machine it watches, there are two nights of backups with nothing
off-site and no database dumps, and no restore has been tested (gaps G3, G4, G8).

## Target layout

| Where | What | Role | Size |
|---|---|---|---|
| prx1 | **prdsrv1** (VMID 100, Ubuntu 24.04, fixed IP 10.69.20.113) | **Main app host**: Caddy, n8n, Paperless, Metabase, Homepage, Arcane, Dozzle, property-search and anything added later | 6 vCPU, 24 GB, 200 GB on `data` (NVMe); bulk disk on `local-lvm` (SATA) if needed |
| prx1 | **prdsrv2** (VMID 101, 10.69.20.114) | **Database server**: Postgres, SQL Server, Oracle, nightly dumps; primary Pi-hole (keeps .114, so no DNS change for clients) | 4 vCPU, 16 GB, 100 GB |
| prx1 | **tstsrv1** (VMID 900, .200) | Try changes before prod | 2 vCPU, 4 GB, 40 GB on `local-lvm` |
| prx2 | **Proxmox Backup Server**, installed on the host | Deduplicated, verified backups: 7 daily, 4 weekly, 3 monthly | datastore on the 1 TB SSD |
| prx2 | **prdsrv3** (LXC, VMID 102, 10.69.20.115) | Infra: Uptime Kuma (moved off prdsrv2, so it can report prdsrv2 down) and a second Pi-hole | 1 vCPU, 1 GB, 8 GB |

Memory after the change: prx1 about 44 of 62 GB allocated (18 GB left for new apps); prx2 about
4 to 5 of 7.6 GB (Proxmox about 1.5, Backup Server about 2 to 3, prdsrv3 about 1).

Why this way round: the databases (the heavy, stateful part, Oracle alone is 6 GB of data) stay
where they are; only the apps move, and their data is tiny. prdsrv1 is built fresh from code
with the most room, as the main server. Pi-hole stays on .114, so DHCP and every client keep
their DNS setting; only the Cloudflare wildcard record moves (.114 to .113) when Caddy moves.

Why Proxmox Backup Server on the prx2 host rather than a VM: Proxmox recommends 4 GiB plus
1 GiB per TiB of datastore; as a VM that is about 5 GB plus a second OS, which prx2 cannot fit
beside anything else. Proxmox advises against installing it on a hypervisor because backups
could die with the VMs they protect; here the VMs live on prx1, so prx2 is the separate
machine that advice asks for.

## Phases

Each phase lists what changes, who does it, how it is checked, and how to undo it.

### Phase 1: archive the Windows backup (no service affected)

1. Storage `archive` on prx2: `/mnt/pve/data/archive`, content backup, `keep-all`, in
   `ansible/roles/pve_host` so it is rebuilt with the host. No job writes to or prunes it.
2. Protect the newest Windows backup on prx1 (Proxmox never prunes protected backups) and
   hard-link its copy on prx2 into `archive`. A hard link costs no extra space and survives the
   nightly mirror deleting the original name.
3. At decommission (phase 5) the same is done with a final backup taken with the VM shut down,
   which is the one to keep long term.

Check: `pvesm list archive` on prx2 shows the backup, and `zstd -t` confirms the file is intact.
Undo: remove the link and the storage.

### Phase 2: Proxmox Backup Server on prx2 (no service affected)

1. Ansible role `pbs` for prx2: Proxmox's `pbs-no-subscription` trixie repository, package
   `proxmox-backup-server`, datastore `main` at `/mnt/pve/data/pbs`, retention keep-daily 7,
   keep-weekly 4, keep-monthly 3, nightly prune and garbage collection, weekly verify.
2. A PBS user and API token for prx1 with backup rights on `main` only (in 1Password as
   `prx2-pbs`); storage `pbs` added on prx1 with the server's fingerprint.
3. Run one manual backup of prdsrv2 to it and restore it to VMID 919 with the NIC unplugged
   (the first restore test, gap G8).
4. Switch the nightly job's storage from `data` to `pbs`. Keep the old vzdump copy job running
   in parallel for two weeks; then remove it and its 107 GB mirror, and free about 100 GB on
   prx1's NVMe.
5. Alerts (review item S2): an email target on both hosts and on the Backup Server, so a failed
   backup, verify or disk problem reaches O'Neil.

Check: the nightly job logs to `pbs`; a restore boots; alerts arrive for a test message.
Undo: point the job back at `data`; `apt remove proxmox-backup-server`.

### Phase 3: prdsrv3 infra container on prx2

1. Terraform: an LXC resource (bpg `proxmox_virtual_environment_container`) in
   `envs/prod`, Ubuntu 24.04, nesting on for Docker; start order after prdsrv2.
2. Ansible: `vm_baseline`, `shell`, `docker` roles; homelab-apps stacks `uptime-kuma` (data
   copied from prdsrv2, 13 MB, so every monitor is kept) and `pihole` (second instance, kept in
   step with the first by nebula-sync).
3. UniFi (O'Neil, web UI): DHCP DNS server 2 = 10.69.20.115 on every VLAN; DNS record prdsrv3.
4. Caddy points `uptime.` at prdsrv3; the old Uptime Kuma on prdsrv2 stops after a day of both.

Check: stop Pi-hole on prdsrv2 briefly and confirm names still resolve; Uptime Kuma still shows
every monitor and alerts. Undo: start the prdsrv2 containers again, DNS server 2 back to empty.

### Phase 4: database dumps and off-site tier 1 (free)

1. On prdsrv2, nightly: `pg_dump` of every Postgres database, SQL Server `BACKUP DATABASE`,
   Oracle Data Pump export, into `/opt/backups`, 14 days kept (gap G4).
2. Nightly encrypted copy (rclone crypt) to Google Drive of what cannot be rebuilt: the dumps,
   Paperless's exporter output, n8n workflows, Uptime Kuma data, and the `.env` files are not
   needed (1Password holds them). Under 1 GB; 30 days kept; fits the free 15 GB.
3. rclone's Drive token and crypt keys in 1Password (`prdsrv2-rclone`).

Check: restore one dump into a scratch database; list the remote. Undo: remove the timers.

### Phase 5: replace Windows prdsrv1 with Linux (Windows goes away)

1. O'Neil copies anything he wants off Windows first.
2. Shut down prdsrv1; final backup (stopped, so fully consistent); protect it; link it into
   `archive` on prx2 (phase 1 method). Optional: keep a second copy off-site (phase 9).
3. Terraform: remove the Windows VM (a deliberate change past `prevent_destroy`), then create
   the new prdsrv1 from template 9000 with the `prod-vm` module: 6 vCPU, 24 GB, 200 GB on
   `data`, guest agent, `discard` and `ssd`, CPU `host`, start order 2. The iGPU is released.
4. Ansible: `vm_baseline`, `shell` (dotfiles), `docker`; UFW baseline; SSH key only.
5. UniFi: DNS record prdsrv1 to .113 and allow .113 on the VPN (the open item from
   `prdsrv1-windows.md`). 1Password items `prdsrv1-<app>`. Uptime Kuma monitor, Homepage tile.
6. Retire the Windows-only pieces: `scripts/windows/prdsrv1-*.ps1`, dotfiles machine
   `prdsrv1` (kept in git history).

Check: `make plan ENV=prod` empty after apply; `ssh prdsrv1` works; audit clean.
Undo: restore the archived Windows backup to VMID 100 (the Terraform change is reverted too).

### Phase 6: move the apps from prdsrv2 to prdsrv1

homelab-apps gains one folder per host (or a host list per stack) so each host checks out only
its stacks; Arcane on prdsrv1 manages both hosts through its agent.

Order, one app at a time, each: stop on prdsrv2, copy its data, start on prdsrv1, check, then
remove from prdsrv2:

1. Dozzle, Homepage, Arcane (no data worth moving).
2. Metabase and property-search (both only talk to Postgres: `postgres:5432` becomes
   `10.69.20.114:5432`; prdsrv2's UFW allows 5432 from .113 only, plus the Mac).
3. n8n (the forced-command SSH key and `run.sh` move with property-search).
4. Paperless (data, media and its Redis).
5. Caddy last: Cloudflare wildcard `*.example.com` from .114 to .113, then Caddy on prdsrv2
   stops. Short outage of the web UIs only (DNS and databases unaffected).

Check after each: the app's page loads, Uptime Kuma green, property-search's next run is `ok`.
Undo: start the app on prdsrv2 again (its data is left in place until phase 7).

### Phase 7: tidy prdsrv2 and add tstsrv1

1. Remove the moved stacks and their data from prdsrv2 (a backup exists from phase 2).
2. prdsrv2 memory stays 16 GB for the databases; revisit after a month of use.
3. tstsrv1 on `local-lvm` (SATA) via `make up`.

### Phase 8: prove it and write it down

1. Restore drill: restore prdsrv2 from the Backup Server to VMID 919 with the NIC unplugged,
   boot it, check the databases (gap G8); repeat quarterly.
2. Update `home-setup-map.md`, `disaster-recovery.md` (G3, G4, G8), `runbook.md`,
   `proxmox-review.md`, homelab-apps README, the agentic-os and Obsidian notes; decisions logged.

### Phase 9, last: open choices

1. Windows: keep only the archived backup (restore it to a small, normally stopped VM on
   `local-lvm` if ever needed), or build a small Windows VM.
2. Off-site tier 2 for whole VM backups: Backblaze B2 (pay as you go, about $6 per TB a month,
   so under £1 for 40 to 80 GB) or a Hetzner Storage Box (about €4 a month for 1 TB). Prices to
   be checked before choosing.
3. Optional: a small separate device (a Raspberry Pi or an old laptop) for the second Pi-hole
   and Uptime Kuma, so they survive both hosts being down.

## Risks

| Risk | Mitigation |
|---|---|
| prx2 now holds backups and infra: if it fails, both go | Services keep running on prx1; off-site tier 1 holds the irreplaceable data; phase 9 adds tier 2 |
| prx1 boot SSD is old | Its loss is recoverable from the Backup Server (phase 2) and the rebuild docs |
| Apps reaching Postgres over the network instead of the Docker network | Same host underneath (both VMs on prx1); UFW limits 5432 to prdsrv1 and the Mac |
| Moving Caddy breaks HTTPS names | Done last, one DNS record, reversible in a minute |
