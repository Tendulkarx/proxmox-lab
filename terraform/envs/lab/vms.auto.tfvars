# Lab VMs. Add an entry + `make up` to create; delete it + `make up` to destroy.
# VMID 900-919 -> IP 10.69.20.200-219 (e.g. 900 -> .200). Keep VMIDs unique across both hosts.
# node: "prx2" is the default choice (more free disk); use "prx1" when you want it there.

lab_vms = {
  test1 = { node = "prx2", vmid = 900 }

  # Example with overrides:
  # docker-test = { node = "prx1", vmid = 901, cores = 4, memory_mb = 4096, disk_gb = 40, tags = ["docker"] }
}
