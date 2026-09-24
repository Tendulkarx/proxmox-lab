---
description: Create a lab VM and configure it (Ubuntu 24.04, your shell, Docker)
argument-hint: [cores] [memory_mb] [disk_gb]
---
Create a lab VM with `$ARGUMENTS` (cores, memory, disk; defaults if omitted).

1. In `terraform/envs/lab/vms.auto.tfvars`, add the VM with the lowest free number N
   (check both the file and `make list`): name `tstsrv<N>`, VMID 899 + N. The first is
   always tstsrv1 = 900; if tstsrv1 and tstsrv2 exist, the next is tstsrv3 = 902.
   For a prod VM, follow "New permanent (prod) VM" in `docs/expanding.md` instead. Default node prx1; use prx2 only for VMs of 2 GB or less.
2. `make plan`: expect exactly 1 VM to add plus the inventory file. Show the plan summary.
3. `make up`, then `make configure NAME=<name>`.
4. Done when `make configure` ends `failed=0` and `ssh` works; reply with the VM's IP and
   `make ssh NAME=<name>`. Commit the tfvars change.
