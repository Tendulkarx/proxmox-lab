# Lab VMs. Add an entry + `make up` to create; delete it + `make up` to destroy.
# VMID 900-919 -> IP 10.69.20.200-219 (e.g. 900 -> .200). Keep VMIDs unique across both hosts.
# node defaults to "prx1" (62 GB RAM). Only use "prx2" for small VMs: it has 7.6 GB RAM in total.

lab_vms = {
  test1 = { vmid = 900 }

  # Example with overrides:
  # docker-test = { vmid = 901, cores = 4, memory_mb = 4096, disk_gb = 40, tags = ["docker"] }
}
