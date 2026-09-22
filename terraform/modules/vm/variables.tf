variable "name" {
  description = "VM name (also the hostname set by cloud-init)"
  type        = string
}

variable "node_name" {
  description = "Proxmox node name, e.g. prx-server-2"
  type        = string
}

variable "vm_id" {
  description = "Proxmox VMID"
  type        = number
}

variable "template_id" {
  description = "VMID of the cloud-init template to clone"
  type        = number
  default     = 9000
}

variable "description" {
  type    = string
  default = "Managed by Terraform (proxmox-lab)"
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory_mb" {
  type    = number
  default = 2048
}

variable "disk_gb" {
  description = "Boot disk size in GB (grown from the template's ~3.5 GB)"
  type        = number
  default     = 20
}

variable "datastore_id" {
  description = "Storage for the boot disk AND the cloud-init drive (bpg defaults the latter to local-lvm)"
  type        = string
  default     = "data"
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "ipv4_address" {
  description = "Static address in CIDR form, e.g. 10.69.20.200/24"
  type        = string
}

variable "ipv4_gateway" {
  type    = string
  default = "10.69.20.1"
}

variable "dns_servers" {
  type    = list(string)
  default = ["10.69.20.114"]
}

variable "dns_domain" {
  type    = string
  default = "home.arpa"
}

variable "username" {
  type    = string
  default = "turbx"
}

variable "ssh_public_keys" {
  type = list(string)
}

variable "on_boot" {
  description = "Start with the host"
  type        = bool
  default     = false
}
