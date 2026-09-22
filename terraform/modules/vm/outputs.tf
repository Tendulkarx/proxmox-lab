output "name" {
  value = proxmox_virtual_environment_vm.this.name
}

output "vm_id" {
  value = proxmox_virtual_environment_vm.this.vm_id
}

output "node_name" {
  value = proxmox_virtual_environment_vm.this.node_name
}

output "ipv4" {
  description = "Configured static address without the prefix length"
  value       = split("/", var.ipv4_address)[0]
}
