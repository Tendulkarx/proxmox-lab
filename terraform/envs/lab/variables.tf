variable "prx1_api_token" {
  description = "terraform@pve!provider=<secret> for prx-server-1"
  type        = string
  sensitive   = true
}

variable "prx2_api_token" {
  description = "terraform@pve!provider=<secret> for prx-server-2"
  type        = string
  sensitive   = true
}

variable "ssh_public_key_file" {
  type    = string
  default = "~/.ssh/id_ed25519_homelab.pub"
}

variable "lab_vms" {
  description = "Test VMs. Key = VM name. VMID 900-919 maps to IP 10.69.20.200-219."
  type = map(object({
    node      = optional(string, "prx1") # "prx1" (default, 62 GB RAM) or "prx2" (7.6 GB RAM)
    vmid      = number
    cores     = optional(number, 2)
    memory_mb = optional(number, 2048)
    disk_gb   = optional(number, 20)
    tags      = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for v in values(var.lab_vms) : contains(["prx1", "prx2"], v.node)])
    error_message = "node must be \"prx1\" or \"prx2\"."
  }

  validation {
    condition     = alltrue([for v in values(var.lab_vms) : v.vmid >= 900 && v.vmid <= 919])
    error_message = "Lab VMIDs must be 900-919 (IP = 10.69.20.<vmid - 700>)."
  }

  validation {
    condition     = length(distinct([for v in values(var.lab_vms) : v.vmid])) == length(var.lab_vms)
    error_message = "Each lab VM needs a unique VMID (unique across BOTH hosts)."
  }
}
