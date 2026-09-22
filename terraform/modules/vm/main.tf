resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  node_name   = var.node_name
  vm_id       = var.vm_id
  description = var.description
  tags        = sort(distinct(concat(["terraform"], var.tags)))

  on_boot = var.on_boot
  started = true

  clone {
    vm_id        = var.template_id
    full         = true
    datastore_id = var.datastore_id
  }

  # Guest agent is baked into template 9000 by scripts/prep-host.sh
  agent {
    enabled = true
    timeout = "5m"
  }

  operating_system {
    type = "l26"
  }

  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_gb
    file_format  = "qcow2"
    discard      = "on"
    ssd          = true
    iothread     = true
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  serial_device {}

  vga {
    type = "serial0"
  }

  initialization {
    datastore_id = var.datastore_id
    interface    = "ide2"

    ip_config {
      ipv4 {
        address = var.ipv4_address
        gateway = var.ipv4_gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.dns_domain
    }

    user_account {
      username = var.username
      keys     = var.ssh_public_keys
    }
  }
}
