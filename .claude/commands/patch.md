---
description: Back up, then OS-patch one VM with a supervised reboot
argument-hint: <vm name, e.g. prdsrv2>
---
Patch `$ARGUMENTS`.

1. Look up its host and VMID (`docs/decisions.md`, `terraform/envs/*/`).
2. Tell O'Neil the expected outage and wait for his go-ahead.
3. `make backup-vm HOST=<host ip> VMID=<vmid>`; confirm the backup file is listed.
4. `make patch ENV=<prod|lab> NAME=$ARGUMENTS`.
5. Done when the summary shows every container back. Report packages changed, whether it
   rebooted, and containers back N of N.
