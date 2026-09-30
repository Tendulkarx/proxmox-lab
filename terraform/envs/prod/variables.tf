variable "prx1_api_token" {
  type      = string
  sensitive = true
}

variable "prx2_api_token" {
  type      = string
  sensitive = true
}

variable "ssh_public_key_file" {
  type    = string
  default = "~/.ssh/id_ed25519_homelab.pub"
}

variable "prod_vms" {
  description = "Prod VMs built from template 9000. Key = VM name prdsrv<N>, VMID = 99 + N."
  type = map(object({
    node      = optional(string, "prx1") # "prx1" (default, 62 GB RAM) or "prx2" (7.6 GB RAM)
    vmid      = number
    ip        = string # full address, no prefix: highest prod IP + 1 (see vms.auto.tfvars)
    cores     = optional(number, 2)
    memory_mb = optional(number, 4096)
    disk_gb   = optional(number, 40)
    tags      = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for v in values(var.prod_vms) : contains(["prx1", "prx2"], v.node)])
    error_message = "node must be \"prx1\" or \"prx2\"."
  }

  validation {
    condition     = alltrue([for name, v in var.prod_vms : name == "prdsrv${v.vmid - 99}"])
    error_message = "Prod VMs are named prdsrv<N> with VMID 99 + N: prdsrv3 = 102, prdsrv4 = 103, and so on. Use the lowest free number."
  }

  # prdsrv2 (101) is the hand-built VM imported in prod.tf; 102 is prdsrv3 in containers.tf.
  validation {
    condition     = alltrue([for v in values(var.prod_vms) : contains([100], v.vmid) || (v.vmid >= 103 && v.vmid <= 199)])
    error_message = "Prod VMIDs are 100 (prdsrv1) or 103-199 (101 is prdsrv2 in prod.tf, 102 is prdsrv3 in containers.tf)."
  }

  validation {
    condition = alltrue([for v in values(var.prod_vms) :
      can(regex("^10\\.69\\.20\\.([0-9]{1,3})$", v.ip)) &&
      !contains(["1", "114", "115", "130", "131"], split(".", v.ip)[3]) &&
      !(tonumber(split(".", v.ip)[3]) >= 200 && tonumber(split(".", v.ip)[3]) <= 219)
    ])
    error_message = "ip must be 10.69.20.x, not the gateway (.1), prdsrv2 (.114), prdsrv3 (.115), the hosts (.130/.131) or the lab range (.200-.219)."
  }

  validation {
    condition     = length(distinct([for v in values(var.prod_vms) : v.ip])) == length(var.prod_vms)
    error_message = "Each prod VM needs its own IP."
  }
}
