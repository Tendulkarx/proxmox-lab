# prdsrv2, adopted from Proxmox with an `import` block (imports.tf).
#
# Rules for this file:
#   * Values mirror what Proxmox reported on 2026-09-22 (generated.tf.orig), so the first plan
#     is 3 to import, 0 to change. Change a value here only on purpose.
#   * prevent_destroy: Terraform refuses any plan that would delete or replace these VMs.
#   * reboot_after_update = false: changes that need a restart are applied to the config and
#     wait for YOU to stop/start the VM at a time that suits you.
#   * Start order is NOT set here: Proxmox requires Sys.Modify on / to change it, which the
#     Terraform token deliberately lacks. It is set by Ansible (roles/pve_host, as root).
#   * ignore_changes covers hardware set up by hand that isn't modelled here (CD drives,
#     EFI/TPM disks, passthrough), so Terraform never tries to "correct" it.

# ---------------------------------------------------------------------------------------
# prdsrv1 (VMID 100) was Windows 11 until 2026-09-30. Its final backup is kept in storage
# `archive` on prx2 (lab-rebuild-plan phase 5; restore it to go back). Terraform forgets the
# old VM rather than destroying it: it was removed on prx1 by hand after the archive was
# checked. The Linux prdsrv1 is template-built: vms.auto.tfvars.
# ---------------------------------------------------------------------------------------
removed {
  from = proxmox_virtual_environment_vm.prdsrv1

  lifecycle {
    destroy = false
  }
}

# ---------------------------------------------------------------------------------------
# prdsrv2: database server: Postgres, SQL Server, Oracle, primary Pi-hole (prx-server-1, VMID 101)
# ---------------------------------------------------------------------------------------
resource "proxmox_virtual_environment_vm" "prdsrv2" {
  provider  = proxmox.prx1
  name      = "prdsrv2"
  node_name = "prx-server-1"
  vm_id     = 101
  # Environment, OS, runtime, roles, terraform (Proxmox shows them A to Z)
  tags      = ["prod", "linux", "docker", "database", "dns", "terraform"]

  bios          = "seabios"
  boot_order    = ["scsi0", "ide2", "net0"]
  scsi_hardware = "virtio-scsi-single"
  on_boot       = true
  started       = true


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

  # Serial port for the Proxmox xterm.js console (copy and paste work there): emergency
  # access when SSH is down. Added 2026-09-24; takes effect at prdsrv2's next full stop and
  # start. Ansible enables the matching login prompt (serial-getty@ttyS0).
  serial_device {}

  operating_system {
    type = "l26"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [cdrom, description, startup]
  }
}

# prdsrv3 (prx-server-2, VMID 100) retired 2026-09-22: it was a test box duplicating
# prdsrv2's databases. Removing its block makes the next apply destroy it (after a final backup).
