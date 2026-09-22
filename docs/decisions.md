# Decisions

Short record of choices and the reason for each. Newest at the bottom.

| # | Decision | Reason |
|---|---|---|
| 1 | Use the **bpg/proxmox** provider (v0.114.x), not telmate/proxmox as Christian Lempa's template does | Both hosts run PVE 9.2; bpg is actively maintained, supports PVE 9, can download cloud images and upload cloud-init snippets itself, and supports `terraform import` by `node/vmid` |
| 2 | Two provider aliases, `prx1` and `prx2`; each VM entry names its host | The hosts are standalone, not clustered, so each has its own API endpoint |
| 3 | Default node for lab VMs is **prx2** | `data` on prx2 has about 860 GB free against about 237 GB on prx1, and it keeps experiments off the host running prdsrv2 |
| 4 | VM disks and cloud-init drives on `data`; set `datastore_id` explicitly everywhere | `local-lvm` is empty and small on prx2 (about 52 GB). bpg defaults several blocks (cloud-init, TPM) to `local-lvm`, so leaving it implicit would scatter disks |
| 5 | Separate Terraform state per environment (`envs/lab`, `envs/prod`) | A mistake in lab, including `terraform destroy`, cannot reach prod. Mirrors the dev/prod split already sketched in `~/infra-as-code` |
| 6 | Prod VMs are **imported**, never recreated; `lifecycle { prevent_destroy = true }` and `ignore_changes` on build-time fields | They were built by hand. The first plan after import must be empty before anything is applied |
| 7 | Lab range: IPs .200 to .219, VMIDs 900 to 919, tag `lab` | Predictable addresses for Ansible, outside the DHCP pool, and easy to tell apart from prod at a glance |
| 8 | Start with the Ubuntu 24.04 **cloud image** as template 9000; add Packer later | Gets VMs running on day one. Packer (Christian's `proxmox-iso-ubuntu`) is worth adding once the pipeline works end to end |
| 9 | Guest login `turbx` with `id_ed25519_homelab` | Same account as prdsrv2; one key for the homelab. Terraform reads the public key from disk at run time, so it is never committed |
| 10 | API token in git-ignored `secrets.auto.tfvars` for now | Simplest start. Revisit (1Password CLI or ansible-vault) before moving to a management VM |
| 11 | Dedicated `terraform@pve` user with a scoped role and a privilege-separated token | Not root; the token can be revoked on its own. bpg also needs SSH to the host for snippet uploads, done as a limited user via ssh-agent |
| 12 | Run from the Mac first; management VM later | Claude's sandbox on the Mac cannot reach the LAN, so O'Neil runs the commands; Claude writes and reviews the code |
| 13 | Windows (prdsrv1) joins Ansible in a later phase | WinRM or OpenSSH setup is extra work; get Linux right first |
| 14 | New dedicated repo `~/development/proxmox-lab` (local git) | Keeps this separate from the older `~/infra-as-code` sketch and the machine-setup `~/infrastructure` repo |

| 15 | Template 9000 is built **on the host** by `scripts/prep-host.sh`, with `virt-customize` baking in qemu-guest-agent | The stock cloud image has no guest agent. Baking it in means Terraform never needs custom cloud-init snippets, so it needs **no SSH access to the hosts** in phase 1: API token only. This also replaces the SSH part of decision 11 |
| 16 | Prod VMIDs confirmed: prx1 has prdsrv1 = 100, prdsrv2 = 101; prx2 has prdsrv3 = 100. Import IDs are `prx-server-1/100`, `prx-server-1/101`, `prx-server-2/100` | From `qm list`, 2026-09-22. VMIDs 900 to 919 and 9000 are free on both hosts |
| 17 | Lab VMIDs stay unique across **both** hosts, even though standalone hosts would allow duplicates | VMID 100 already exists on both hosts, which would have to be renumbered before the two could ever be clustered or share a Proxmox Backup Server datastore. No new clashes |

## Open items

- None blocking phase 1.
