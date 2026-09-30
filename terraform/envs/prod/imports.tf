# Step 1 of Phase 4: adopt the existing prod VMs WITHOUT changing them.
#
#   make init ENV=prod
#   make prod-generate      -> writes generated.tf describing each VM exactly as it is now
#
# Claude then tidies generated.tf into prod VM definitions (prevent_destroy, no auto-reboot),
# and `make plan ENV=prod` must show 3 to import, 0 to add, 0 to change, 0 to destroy
# before anything is applied.

import {
  to       = proxmox_virtual_environment_vm.prdsrv2
  id       = "prx-server-1/101"
  provider = proxmox.prx1
}

