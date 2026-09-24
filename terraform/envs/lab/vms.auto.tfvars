# Lab VMs. Add an entry + `make up` to create; delete it + `make up` to destroy.
# Names are tstsrv<N>, lowest free N first; VMID = 899 + N, IP = 10.69.20.(199 + N):
# tstsrv1 = 900 = .200, tstsrv2 = 901 = .201, up to tstsrv20. Keep VMIDs unique across both hosts.
# node defaults to "prx1" (62 GB RAM). Only use "prx2" for small VMs: it has 7.6 GB RAM in total.

lab_vms = {
  tstsrv1 = { vmid = 900 }

  # Example with overrides:
  # tstsrv2 = { vmid = 901, cores = 4, memory_mb = 4096, disk_gb = 40, tags = ["docker"] }
}
