# Prod twin of ../vm: the same VM, plus the prod guardrails. Terraform can't make
# prevent_destroy a variable, so this resource is a copy; keep the two in step.
# variables.tf, outputs.tf and versions.tf are symlinks to ../vm.
resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  node_name   = var.node_name
  vm_id       = var.vm_id
  description = var.description
  tags        = sort(distinct(concat(["terraform"], var.tags)))

  on_boot = var.on_boot
  started = true

  # Restarts are O'Neil's call: changes that need one wait for a manual stop and start.
  reboot_after_update = false

  # Proxmox's "purge" also deletes the VMID from backup jobs, including their EXCLUDE
  # list. With purge on, destroying a lab VM silently removed it from the nightly job's
  # exclusions, so the next VM reusing that VMID would be backed up. Keep it off.
  purge_on_destroy = false

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
    file_format  = startswith(var.datastore_id, "local-lvm") ? "raw" : "qcow2" # LVM-thin only supports raw
    discard      = "on"
    ssd          = true
    iothread     = true
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  # Serial port kept for the text console (Console > xterm.js, copy/paste works);
  # standard VGA makes the default console noVNC, like the prod VMs.
  serial_device {}

  vga {
    type = "std"
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

  lifecycle {
    prevent_destroy = true
  }
}
