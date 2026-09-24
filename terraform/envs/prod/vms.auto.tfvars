# Prod VMs built from template 9000. Add an entry + `make plan ENV=prod` + `make up ENV=prod`.
# prdsrv1 (VMID 100, .69) and prdsrv2 (VMID 101, .114) are hand-built and live in prod.tf.
#
# Name:  prdsrv<N>, lowest free N; VMID = 99 + N (prdsrv3 = 102, prdsrv4 = 103, ...).
# IP:    the highest IP any prod VM uses, plus one (today .114, so prdsrv3 = .115), after
#        checking from prx1 that nothing answers on it: `ping -c1 <ip>; ip neigh show <ip>`
#        should show INCOMPLETE or FAILED.
# Node:  prx1 by default; prx2 has 7.6 GB RAM in total.
# Deleting an entry does NOT delete the VM: prevent_destroy stops the plan.

prod_vms = {
  # Example:
  # prdsrv3 = { vmid = 102, ip = "10.69.20.115", cores = 4, memory_mb = 8192, disk_gb = 60, tags = ["docker"] }
}
