# Prod containers (LXC). Decision 62: infra that must outlive prdsrv2 lives in a container on
# prx2, which costs only what its apps use.
#
# The template is downloaded by Ansible (roles/pve_host, pve_lxc_templates): the Terraform
# token deliberately cannot. Docker needs `nesting`, the one feature flag a non-root token may
# set on an unprivileged container.

# ---------------------------------------------------------------------------------------
# prdsrv3: infra: Uptime Kuma and the second Pi-hole (prx-server-2, VMID 102)
# ---------------------------------------------------------------------------------------
resource "proxmox_virtual_environment_container" "prdsrv3" {
  provider    = proxmox.prx2
  node_name   = "prx-server-2"
  vm_id       = 102
  description = "Infra: Uptime Kuma and the second Pi-hole. Built by proxmox-lab (Terraform + make configure ENV=prod)."
  # Environment, OS, runtime, roles, terraform (Proxmox shows them A to Z)
  tags        = ["prod", "linux", "docker", "monitoring", "dns", "terraform"]

  unprivileged  = true
  start_on_boot = true
  started       = true
  # As for lab VMs (modules/vm): a purge would also drop VMID 102 from backup jobs' lists.
  purge_on_destroy = false

  features {
    nesting = true
  }

  operating_system {
    template_file_id = "data:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
    type             = "ubuntu"
  }

  cpu {
    cores = 2 # a ceiling, not a reservation: prx2 has 4 threads
  }

  memory {
    dedicated = 1024
    swap      = 512
  }

  disk {
    datastore_id = "data"
    size         = 8
  }

  network_interface {
    name     = "eth0"
    bridge   = "vmbr0"
    firewall = true
  }

  initialization {
    hostname = "prdsrv3"

    ip_config {
      ipv4 {
        address = "10.69.20.115/24"
        gateway = "10.69.20.1"
      }
    }

    # The router, not Pi-hole: this container hosts a Pi-hole and must resolve without one.
    dns {
      servers = ["10.69.20.1"]
      domain  = "home.arpa"
    }

    # root's key, only for the first login: playbooks/lxc-bootstrap.yml makes turbx, then
    # vm_baseline turns root SSH off.
    user_account {
      keys = local.prod_ssh_keys
    }
  }

  lifecycle {
    prevent_destroy = true
    # Only read when the container is made; a newer template must never replace it.
    ignore_changes = [operating_system[0].template_file_id, initialization[0].user_account]
  }
}

output "containers" {
  description = "Prod containers"
  value = {
    prdsrv3 = "prx-server-2  vmid=102  ip=10.69.20.115  ssh turbx@10.69.20.115"
  }
}
