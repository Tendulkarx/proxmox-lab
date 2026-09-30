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

**Done 2026-09-29**: storage `archive` on prx2 (`make hosts ARGS="--tags archive"`); the 29 Sep
nightly backup of Windows prdsrv1 (39.4 GB) protected on prx1, hard-linked into `archive` and
protected there; `zstd -t` passed. This is the interim copy; the final one comes in phase 5.

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

Status 2026-09-29: steps 1 to 4 done; step 5 (alerts) open.
- 1: role `pbs` (`make hosts`), idempotent. The enterprise repository is kept but
  `Enabled: false`, because it fails `apt update` with 401 without a subscription.
- 2: `scripts/pbs-connect.sh` made token `backup@pbs!prx1` and storage `pbs` on prx1. The secret
  went straight from prx2 to prx1 and is not in 1Password: if it is lost, run the script with
  `--rotate`. Token rights are what the user AND the token are both granted, so the role gives
  `backup@pbs` DatastoreBackup on `/datastore/main` and the script gives the token the same.
- 3: prdsrv2 backed up in 4 min and restored to VM 919 (NIC unplugged, 10.69.20.114 on a dummy
  interface) in 5 min. Postgres (5 databases; property_search had 7,241 listings and the
  19:00 run), SQL Server (6 databases) and the app containers came up. Oracle stopped with
  ORA-00600 [ksipc: no private ips avail for use]: it needs a real network interface, which the
  unplugged test VM does not have, so it says nothing about the backup. VM 919 destroyed.
- 4: done as a second job, `pbs-nightly` at 03:30 (all VMs, same exclusions, retention on the
  Backup Server), not a switch. `nightly` to `data` and the 06:00 copy stay until 2026-10-13;
  then remove them and the prx1 mirror on prx2.

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

Run order (prepared 2026-09-29; homelab-apps PR #9 holds the stacks):
1. `make hosts ARGS="--tags templates --limit prx2"` downloads the Ubuntu 24.04 container
   template; `make plan ENV=prod` must show 1 to add (prdsrv3), 0 to change; `make up ENV=prod`.
2. `make lxc-bootstrap NAME=prdsrv3`, then `make configure ENV=prod NAME=prdsrv3`
   (vm_baseline skips the kernel, guest agent and serial console in a container).
3. On prdsrv3: a read-only deploy key for homelab-apps, clone to `/opt/docker`, `.env` files
   from `op inject` plus the prdsrv3 values in the README; start `pihole` and `nebula-sync`.
   Check: `dig @10.69.20.115 prx1.home.arpa` and a blocked domain give the same answers as .114.
4. Uptime Kuma: stop it on prdsrv2, copy `data/` (13 MB), start it on prdsrv3, point Caddy's
   `uptime.` at `10.69.20.115:3001`. Four database monitors name containers on prdsrv2's
   network (`postgres`, `sqlserver`, Oracle, `paperless-broker`): the first three change to
   10.69.20.114 and their published ports. Paperless's Redis is not published outside prdsrv2,
   so its monitor goes; the Paperless web monitor stays.
5. UniFi (O'Neil): DNS server 2 = 10.69.20.115 on every VLAN.

Status 2026-09-30: steps 1 to 3 done. prdsrv3 runs Pi-hole and nebula-sync (first sync done;
.114 and .115 give the same answers for local records, internet names and blocked domains),
156 MB of its 1 GB used. Docker works with `nesting` alone. homelab-apps is cloned with a
read-only deploy key and on `main` (PR #9 merged); the console password is set.
Status 2026-09-30, later: phase 3 done. Uptime Kuma moved (about 3 minutes without
monitoring); every active monitor is up from prdsrv3; the Redis monitor is paused, not deleted.
The old copy on prdsrv2 is stopped, not removed, with its data in
`~turbx/uptime-kuma-data-2026-09-30.tgz` there. Undo: Caddy back to `uptime-kuma:3001`, start
it on prdsrv2. O'Neil set DNS server 2 in UniFi. Lesson: Caddy mounts the one Caddyfile, and
`git pull` replaces the file, so after a pull Caddy needs `docker restart caddy` (seconds of
downtime for every site), not `caddy reload`.

### Phase 4: database dumps and off-site tier 1 (free)

1. On prdsrv2, nightly: `pg_dump` of every Postgres database, SQL Server `BACKUP DATABASE`,
   Oracle Data Pump export, into `/opt/backups`, 14 days kept (gap G4).
2. Nightly encrypted copy (rclone crypt) to Google Drive of what cannot be rebuilt: the dumps,
   Paperless's exporter output, n8n workflows, Uptime Kuma data, and the `.env` files are not
   needed (1Password holds them). Under 1 GB; 30 days kept; fits the free 15 GB.
3. rclone's Drive token and crypt keys in 1Password (`prdsrv2-rclone`).

Check: restore one dump into a scratch database; list the remote. Undo: remove the timers.

Status 2026-09-30: phase 4 done. The first off-site copy (12 files, 26 MB) passed
`rclone cryptcheck` against the local dumps; the keys are in 1Password `prdsrv2-rclone`. Open:
rclone's shared Google client is retired during 2026, so an own OAuth client is needed
(`homelab-apps/backups/offsite.md`, O'Neil in the Google Cloud console).
- `homelab-apps/backups/dump.sh`, timer `db-dumps` at 01:30 (role `db_backups`): every Postgres
  database plus roles, SQL Server master/model/msdb (it has no user databases), Oracle FREEPDB1
  full Data Pump export, n8n's SQLite database and key, Paperless's exporter. 36 MB a night,
  3 minutes. Restored property_search into a scratch database: 7,241 listings and 285,308 sold
  prices, the same as live.
- `offsite.sh`, timer `db-offsite` at 03:00: rclone crypt to Drive folder `homelab-offsite`,
  30 days, without the dev database: about 0.8 GB. Skipped until rclone is set up.
- Uptime Kuma push monitors "Database dumps" and "Off-site copy" (26 h window); their URLs are
  in `/etc/default/db-backups` on prdsrv2.
- Not covered off-site yet: Uptime Kuma's own data (on prdsrv3; in prx2's nightly backup).

Alerts (phase 2 step 5): done by `scripts/gmail-alerts.sh`: Gmail target and warnings/errors
matcher on both hosts and the Backup Server (test emails sent), and Uptime Kuma's first
notification, on all 15 monitors.

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

Status 2026-09-30: done, except the items for O'Neil below.
- Windows shut down cleanly; final backup taken stopped (37.6 GB, 2 min), protected on prx1,
  hard-linked into `archive` on prx2 and protected there; `zstd -t` passed. VM 100 then
  removed with `qm destroy` (Terraform `removed` block with `destroy = false`, so the plan
  only forgets it). The 29 Sep interim copy stays in `archive` too.
- New prdsrv1: VM 100 from template 9000, 6 cores, 24 GB, 200 GB, 10.69.20.113, DNS both
  Pi-holes; start order 2; baseline, shell (machine profile `prdsrv`, `KIND=server`) and
  Docker; a second `make configure` changes nothing.
- Retired: `scripts/windows/`, `docs/prdsrv1-windows.md`, dotfiles `machines/prdsrv1` (it
  gave the new Linux VM the Windows desktop profile) and the .69 SSH entry.
- Moved to phase 6, where the rules matter: UFW, the Uptime Kuma monitor and Homepage tile.
- Console password set; `make plan ENV=prod` shows no changes. O'Neil: a restart for the new
  kernel (nothing runs there yet), and in UniFi a DNS record prdsrv1 = .113 and .113/.115 on
  the VPN.

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

Status 2026-09-30: phase 6 done.
- Moved to prdsrv1: Homepage, Dozzle, Arcane, Metabase, n8n, Paperless (data copied with the app
  stopped; each checked through Caddy). Their data on prdsrv2 is left in place for phase 7.
- Changed from the plan: property-search stays on prdsrv2 beside Postgres. n8n (now on prdsrv1)
  still starts it over SSH to .114, so neither the forced-command key nor the n8n credential
  changed. Apps on prdsrv1 reach Postgres as `postgres` through `extra_hosts`, so no secret
  changed either.
- Dozzle on prdsrv1 reads prdsrv2 and prdsrv3 through `dozzle-agent`, with the lab's own
  certificate (the built-in one is shared by every install and would let anyone reaching port
  7007 run commands in the containers).
- Backups follow the apps: `dump.sh` does only the parts whose container runs on the host;
  prdsrv1 has its own timers, rclone config and Uptime Kuma push monitors; off-site copies go
  to `daily/<date>/<host>`.
- Caddy: config folder mounted (`caddy/etc`), so `caddy reload` works after a pull. Pi-hole's
  page is published on 10.69.20.114:8081 for it.
- Finished the same day: O'Neil moved the Cloudflare `*` record to 10.69.20.113; once caches
  expired (5 minutes; the Mac held some names a little longer) Caddy on prdsrv2 stopped, the
  Caddyfile went back to container names and the `PUBLISH_IP` ports closed. All ten sites and
  every Uptime Kuma monitor are up. Downtime: each app about a minute while it moved; Pi-hole's
  page about 70 minutes (prdsrv2's UFW blocked its own Caddy from the new 8081 port).

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
