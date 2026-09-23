---
description: Create a lab VM and configure it (Ubuntu 24.04, your shell, Docker)
argument-hint: <name> [cores] [memory_mb] [disk_gb]
---
Create lab VM `$ARGUMENTS`.

1. In `terraform/envs/lab/vms.auto.tfvars`, add the VM with the lowest free VMID in 900-919
   (check both the file and `make list`). Default node prx1; use prx2 only for VMs of 2 GB or less.
2. `make plan`: expect exactly 1 VM to add plus the inventory file. Show the plan summary.
3. `make up`, then `make configure NAME=<name>`.
4. Done when `make configure` ends `failed=0` and `ssh` works; reply with the VM's IP and
   `make ssh NAME=<name>`. Commit the tfvars change.
