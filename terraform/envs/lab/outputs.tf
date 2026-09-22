output "vms" {
  description = "Lab VMs managed by this env"
  value = {
    for name, vm in local.all_vms : name => "${vm.node_name}  vmid=${vm.vm_id}  ip=${vm.ipv4}  ssh turbx@${vm.ipv4}"
  }
}
