locals {
  node_names = {
    prx1 = "prx-server-1"
    prx2 = "prx-server-2"
  }

  # prx1: lab VMs on the spare 338 GB local-lvm pool, keeping the NVMe `data` disk for prod.
  # prx2: its local-lvm is only 50 GB, so use `data`.
  lab_datastore = {
    prx1 = "local-lvm"
    prx2 = "data"
  }

  ssh_keys = [trimspace(file(pathexpand(var.ssh_public_key_file)))]

  vms = {
    for name, v in var.lab_vms : name => merge(v, {
      ipv4 = "10.69.20.${v.vmid - 700}"
    })
  }
}

# Providers can't be picked per for_each item, so one module block per host.
module "vm_prx1" {
  source    = "../../modules/vm"
  providers = { proxmox = proxmox.prx1 }
  for_each  = { for k, v in local.vms : k => v if v.node == "prx1" }

  name            = each.key
  node_name       = local.node_names.prx1
  datastore_id    = local.lab_datastore.prx1
  vm_id           = each.value.vmid
  cores           = each.value.cores
  memory_mb       = each.value.memory_mb
  disk_gb         = each.value.disk_gb
  tags            = concat(["lab"], each.value.tags)
  ipv4_address    = "${each.value.ipv4}/24"
  ssh_public_keys = local.ssh_keys
}

module "vm_prx2" {
  source    = "../../modules/vm"
  providers = { proxmox = proxmox.prx2 }
  for_each  = { for k, v in local.vms : k => v if v.node == "prx2" }

  name            = each.key
  node_name       = local.node_names.prx2
  datastore_id    = local.lab_datastore.prx2
  vm_id           = each.value.vmid
  cores           = each.value.cores
  memory_mb       = each.value.memory_mb
  disk_gb         = each.value.disk_gb
  tags            = concat(["lab"], each.value.tags)
  ipv4_address    = "${each.value.ipv4}/24"
  ssh_public_keys = local.ssh_keys
}

locals {
  all_vms = merge(module.vm_prx1, module.vm_prx2)
}

# Ansible inventory for the lab VMs (git-ignored; regenerated on every apply)
resource "local_file" "ansible_inventory" {
  filename        = "${path.root}/../../../ansible/inventory/lab.generated.yml"
  file_permission = "0644"
  content = yamlencode({
    all = {
      children = {
        lab = {
          hosts = {
            for name, vm in local.all_vms : name => {
              ansible_host = vm.ipv4
              proxmox_node = vm.node_name
              proxmox_vmid = vm.vm_id
            }
          }
          vars = {
            ansible_user                 = "turbx"
            ansible_ssh_private_key_file = "~/.ssh/id_ed25519_homelab"
          }
        }
      }
    }
  })
}
