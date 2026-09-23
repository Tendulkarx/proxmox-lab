---
description: Read-only health check of both Proxmox hosts and all Linux VMs
---
1. Run `make audit`.
2. Read every report in `audit/` in full: both `pve-audit-*.txt` and every `vm-*.txt`.
3. Compare against the open items in `docs/proxmox-review.md`. Done when every finding is
   classed as fixed, still open, or new.
4. Reply with a short prioritised list (urgent / important / worth deciding), each item with
   its evidence line from the report and the fix. Then append a dated section to
   `docs/proxmox-review.md` and commit.
