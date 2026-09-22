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

| 18 | Tokens live in 1Password (vault `Development`, items `proxmox-prx1-terraform` / `proxmox-prx2-terraform`, field `credential`) and reach Terraform via `op run --env-file=.env.op`. Supersedes decision 10 | `.env.op` holds only `op://` references, so it is safe to commit; no secret is ever written to disk in the repo |
| 19 | Lab IP is derived from the VMID (`10.69.20.<vmid - 700>`), with validation that VMIDs are 900 to 919 and unique | One number per VM to choose; impossible to give two VMs the same IP by mistake |
| 20 | Terraform writes `ansible/inventory/lab.generated.yml` on every apply (git-ignored) | Ansible always targets exactly what exists; no hand-maintained inventory |

| 21 | Ansible copies the shell config **from the agentic-os dotfiles folder on the Mac** (`dotfiles_dir`), not from a copy in this repo | One source of truth: edit the dotfiles there, re-run `make configure`, every VM matches |
| 22 | The VM `.zshrc` is the Mac `.zshrc` verbatim plus a marked Linux block appended by Ansible | The Mac file loads plugins from `/opt/homebrew` and only runs `compinit` when Homebrew exists; the block loads the Ubuntu package paths, runs `compinit`, and removes Mac aliases that break Linux (notably `ip`, which shadows the real `ip` command) |
| 23 | fzf and starship are installed from pinned GitHub releases; zsh plugins, eza and zoxide from apt | Ubuntu 24.04's fzf (0.44) is too old for `fzf --zsh` used in the `.zshrc`; starship isn't packaged for noble |
| 24 | `.gitconfig` is not deployed to VMs | It carries Mac-specific settings (1Password SSH signing paths) that would break git on Linux |

| 25 | Lab VMs use a separate known_hosts file, `~/.ssh/known_hosts.proxmox-lab`, cleared by `make down` / `make destroy-lab` | Lab VMs are rebuilt at the same IPs with fresh host keys, which tripped SSH's "host identification has changed" check on first use. Your main `~/.ssh/known_hosts` stays strict for everything else, including prod |

| 26 | Docker Engine from Docker's official apt repo on every Linux VM, with `/opt/docker` owned by turbx and a shared `proxy` network | Same layout as prdsrv2 (setup-sequence.md Phase 3), so compose stacks move between VMs unchanged. Install is skipped if Docker already exists; for hand-built hosts set `docker_manage_daemon_json: false` so Ansible never rewrites daemon.json or restarts Docker |
| 27 | `scripts/audit-host.sh` is a read-only report; output goes to `audit/` (git-ignored) | Basis for the Proxmox review; nothing on the host is changed |

| 28 | **Lab VMs default to prx1**, on its spare `local-lvm` pool (raw disks); prx2 only for small VMs. Supersedes decision 3 | The audit showed prx2 has 7.6 GiB RAM and was already swapping; prx1 has 62 GiB. Lab on `local-lvm` keeps the NVMe `data` disk for prod |
| 29 | Host hardening lives in `ansible/roles/pve_host` (`make hosts-check`, `make hosts`) | Everything from docs/proxmox-review.md that doesn't touch VMs: stale repos, broken package, old kernels, root SSH key-only, FQDN/search domain `home.arpa`, nightly backups, tag colours, optional ntfy alerts |
| 30 | Interim backups: nightly vzdump to the host's own `data`, `keep-last=2`, lab VMIDs excluded | Something tonight beats nothing. Only 2 copies because they sit on the same disk as the VMs; Proxmox Backup Server on the other host is the next step |
| 31 | Prod VMs are adopted with `import` blocks and `terraform plan -generate-config-out` | Terraform describes each VM exactly as it is, instead of hand-writing configs and risking a replace. Changes that need reboots (prdsrv2 agent, CPU, cores, discard; prdsrv3 RAM; start order; tags) are applied afterwards as reviewed diffs, with `reboot_after_update = false` |

## Open items

- None blocking phase 1.
