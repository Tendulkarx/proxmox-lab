# Reclaiming VM disk space

VM disks here are qcow2 files on each host's `data` storage. They grow as a guest writes and
only shrink when the guest tells the host which blocks it has freed (TRIM/discard). Backups
store the disk's contents, so a disk full of old deleted data also makes large backups.

## What happened (2026-09-24)

`data` on prx1 reached 92%. prdsrv1's disk had `discard` off, so its file had grown to 121 GB
of 128 while Windows used 41 GB; its backup was 130 GB, and that night's backup failed for lack
of room. prdsrv2's weekly `fstrim` had run before discard was active, leaving 97 GB for 39 GB
used. After the steps below: prdsrv1 36 GB, prdsrv2 40 GB, `data` 44% used, prdsrv1's
backup 35 GB.

## Check

```sh
lab status                                   # data disk use, pending changes
ssh prx1 'du -sh /mnt/pve/data/images/*/*'   # each disk file's real size
ssh prx1 'qm config <vmid> | grep scsi0'     # discard=on,ssd=1 wanted
```

## Fix

1. **Discard on the disk.** In Terraform: `discard = "on"`, `ssd = true` on the VM's disk
   (both are set for prdsrv1 and prdsrv2, and in `modules/vm` for every new VM).
   `lab plan prod`, `lab up prod`; the change is pending until `lab restart <vm>`.
2. **Hand back the free space once.**
   - Linux: `ssh <vm> 'sudo fstrim -av'` (runs weekly by itself afterwards).
   - Windows: `Optimize-Volume -DriveLetter C -ReTrim` should do it. On prdsrv1 it reported
     "Retrim: skipped" even with TRIM supported, so zero the free space instead; the disk runs
     with `detect-zeroes=unmap`, and when the fill file is deleted Windows sends the discards:
     `winget install Microsoft.Sysinternals.SDelete`, then `sdelete64 -accepteula -z C:`.
     C: looks full while it runs; the space returns when it finishes. From then on, normal
     file deletes are passed through without help.
3. **Take a fresh backup** so there is a good copy at the new size: `lab backup <vm>`.

## Keep it healthy

- New VMs get discard from `modules/vm` and `modules/prod-vm`.
- `lab status` shows the `data` disk after every change; above about 75%, check here first.
- Backups share the disk with the VMs (keep-last=2): see `docs/disaster-recovery.md`, gap G3.
