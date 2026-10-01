# Prod VMs built from template 9000. Add an entry + `make plan ENV=prod` + `make up ENV=prod`.
# prdsrv2 (VMID 101, .114) is hand-built and lives in prod.tf; prdsrv3 (102) is a container.
#
# Name:  prdsrv<N>, lowest free N; VMID = 99 + N (prdsrv3 = 102, prdsrv4 = 103, ...).
# IP:    the highest IP any prod VM uses, plus one (today .115, so prdsrv4 = .116), after
#        checking from prx1 that nothing answers on it: `ping -c1 <ip>; ip neigh show <ip>`
#        should show INCOMPLETE or FAILED.
# Node:  prx1 by default; prx2 has 7.6 GB RAM in total.
# Tags:  runtime, then what it runs (apps, database, dns, monitoring); prod, linux and
#        terraform are added around them.
# Deleting an entry does NOT delete the VM: prevent_destroy stops the plan.

prod_vms = {
  # Main app host (lab-rebuild-plan phase 5), replacing Windows prdsrv1 (VMID 100, .69).
  prdsrv1 = { vmid = 100, ip = "10.69.20.113", cores = 6, memory_mb = 24576, disk_gb = 200, tags = ["docker", "apps"] }
  # Example:
  # prdsrv4 = { vmid = 103, ip = "10.69.20.116", cores = 4, memory_mb = 8192, disk_gb = 60, tags = ["docker"] }
}
