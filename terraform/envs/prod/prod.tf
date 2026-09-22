# Production VMs, adopted from Proxmox with `import` blocks (imports.tf).
#
# Rules for this file:
#   * Values mirror what Proxmox reported on 2026-09-22 (generated.tf.orig), so the first plan
#     is 3 to import, 0 to change. Change a value here only on purpose.
#   * prevent_destroy: Terraform refuses any plan that would delete or replace these VMs.
#   * reboot_after_update = false: changes that need a restart are applied to the config and
#     wait for YOU to stop/start the VM at a time that suits you.
#   * ignore_changes covers hardware set up by hand that isn't modelled here (CD drives,
#     EFI/TPM disks, passthrough), so Terraform never tries to "correct" it.

# ---------------------------------------------------------------------------------------
# prdsrv1: Windows Server, iGPU passthrough (prx-server-1, VMID 100)
# ---------------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "prdsrv1" {
  provider  = proxmox.prx1
  name      = "prdsrv1"
  node_name = "prx-server-1"
  vm_id     = 100
  tags      = ["prod", "terraform", "windows"]

  bios          = "ovmf"
  machine       = "pc-q35-9.0"
  boot_order    = ["scsi0", "ide0", "ide2", "net0"]
  scsi_hardware = "virtio-scsi-single"
  on_boot       = true
  started       = true

  # Starts after prdsrv2 (DNS + reverse proxy)
  startup {
    order      = 2
    up_delay   = 0
    down_delay = 120
  }

  reboot_after_update = false
  stop_on_destroy     = false

  agent {
    enabled = true
    timeout = "15m"
  }

  cpu {
    cores   = 6
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 16384
  }

  disk {
    datastore_id = "data"
    interface    = "scsi0"
    file_format  = "qcow2"
    size         = 128
    iothread     = true
    discard      = "ignore"
    ssd          = false
  }

  efi_disk {
    datastore_id      = "data"
    file_format       = "qcow2"
    type              = "4m"
    pre_enrolled_keys = true
  }

  tpm_state {
    datastore_id = "data"
    version      = "v2.0"
  }

  hostpci {
    device = "hostpci0"
    id     = "0000:00:02"
    pcie   = true
    rombar = true
    xvga   = false
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:A7:26:2E"
    firewall    = true
  }

  operating_system {
    type = "win11"
  }

  vga {
    type   = "virtio"
    memory = 16
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [cdrom, efi_disk, tpm_state, hostpci, description]
  }
}

# ---------------------------------------------------------------------------------------
# prdsrv2: main Docker host: Caddy, Pi-hole, databases, apps (prx-server-1, VMID 101)
# ---------------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "prdsrv2" {
  provider  = proxmox.prx1
  name      = "prdsrv2"
  node_name = "prx-server-1"
  vm_id     = 101
  tags      = ["docker", "linux", "prod", "terraform"]

  bios          = "seabios"
  boot_order    = ["scsi0", "ide2", "net0"]
  scsi_hardware = "virtio-scsi-single"
  on_boot       = true
  started       = true

  # First to start on prx-server-1: everything else relies on its DNS and Caddy
  startup {
    order      = 1
    up_delay   = 60
    down_delay = 120
  }

  reboot_after_update = false
  stop_on_destroy     = false

  # Enabled 2026-09-22. Short timeout: until prdsrv2 is stopped and started once, the agent
  # port doesn't exist and Terraform would otherwise wait the full timeout for it.
  agent {
    enabled = true
    timeout = "2m"
  }

  # Was 2 cores, x86-64-v2-AES. Standalone host, no migration: expose the full CPU.
  cpu {
    cores   = 4
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 16384
  }

  disk {
    datastore_id = "data"
    interface    = "scsi0"
    file_format  = "qcow2"
    size         = 100
    iothread     = true
    discard      = "on" # hand freed space back to the host
    ssd          = true
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:DD:BA:F9"
    firewall    = true
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [cdrom, description]
  }
}

# ---------------------------------------------------------------------------------------
# prdsrv3: Linux Docker host (prx-server-2, VMID 100)
# ---------------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "prdsrv3" {
  provider  = proxmox.prx2
  name      = "prdsrv3"
  node_name = "prx-server-2"
  vm_id     = 100
  tags      = ["docker", "linux", "prod", "terraform"]

  bios          = "seabios"
  boot_order    = ["scsi0", "ide2", "net0"]
  scsi_hardware = "virtio-scsi-single"
  on_boot       = true
  started       = true

  reboot_after_update = false
  stop_on_destroy     = false

  agent {
    enabled = true
    timeout = "15m"
  }

  startup {
    order      = 1
    up_delay   = 30
    down_delay = 120
  }

  cpu {
    cores   = 4
    sockets = 1
    type    = "host"
  }

  # Was 8 GB on a host with 7.6 GB physical RAM (prx2 was swapping)
  memory {
    dedicated = 6144
  }

  disk {
    datastore_id = "data"
    interface    = "scsi0"
    file_format  = "qcow2"
    size         = 150
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:74:A9:D8"
    firewall    = true
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [cdrom, description]
  }
}
