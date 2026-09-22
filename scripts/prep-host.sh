#!/usr/bin/env bash
# prep-host.sh: one-off preparation of a standalone Proxmox VE 9 host for proxmox-lab.
#
# Run as root ON EACH HOST (prx-server-1 and prx-server-2):
#   scp scripts/prep-host.sh root@10.69.20.130:/root/ && ssh root@10.69.20.130 bash /root/prep-host.sh
#
# What it does (safe to re-run; every step skips if already done):
#   1. Adds the 'snippets' and 'import' content types to the 'data' storage (keeps existing types)
#   2. Creates role 'Terraform', user 'terraform@pve' and API token 'terraform@pve!provider'
#   3. Builds template VMID 9000 from the Ubuntu 24.04 cloud image, with qemu-guest-agent baked in
#
# The token secret is printed ONCE, on creation. Put it in terraform/envs/*/secrets.auto.tfvars on
# your Mac. Do not paste it into chat or commit it.

set -euo pipefail

STORAGE="data"
BRIDGE="vmbr0"
TEMPLATE_ID="9000"
TEMPLATE_NAME="ubuntu-2404-cloud-tpl"
IMG_BASE="https://cloud-images.ubuntu.com/noble/current"
IMG_FILE="noble-server-cloudimg-amd64.img"
WORKDIR="/root/proxmox-lab-prep"
PVE_USER="terraform@pve"
TOKEN_ID="provider"
ROLE="Terraform"
# VM lifecycle privileges only. Deliberately excludes user/realm/permission management.
PRIVS="Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit \
Mapping.Audit Mapping.Use Pool.Audit SDN.Audit SDN.Use Sys.Audit Sys.Console Sys.Syslog \
VM.Allocate VM.Audit VM.Backup VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit \
VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options \
VM.Console VM.GuestAgent.Audit VM.GuestAgent.FileRead VM.GuestAgent.FileSystemMgmt \
VM.GuestAgent.FileWrite VM.GuestAgent.Unrestricted VM.Migrate VM.PowerMgmt VM.Snapshot \
VM.Snapshot.Rollback"

log()  { printf '\n==> %s\n' "$*"; }
skip() { printf '    already done: %s\n' "$*"; }

[[ $EUID -eq 0 ]] || { echo "Run as root on the Proxmox host." >&2; exit 1; }
command -v pveversion >/dev/null || { echo "This is not a Proxmox VE host." >&2; exit 1; }
echo "Host: $(hostname)  |  $(pveversion)"

# 1. Storage content types ---------------------------------------------------------------
log "Storage '$STORAGE': ensure content types include snippets and import"
current=$(awk -v s="$STORAGE" '
  $1 ~ /^[a-z]+:$/ { inblk = ($2 == s) }
  inblk && $1 == "content" { print $2 }' /etc/pve/storage.cfg)
[[ -n "$current" ]] || { echo "Storage '$STORAGE' not found in /etc/pve/storage.cfg" >&2; exit 1; }
merged="$current"
for c in snippets import; do
  [[ ",$merged," == *",$c,"* ]] || merged="$merged,$c"
done
if [[ "$merged" != "$current" ]]; then
  pvesm set "$STORAGE" --content "$merged"
  echo "    content: $current  ->  $merged"
else
  skip "content is $current"
fi

# 2. Role, user, token ---------------------------------------------------------------------
log "Role '$ROLE'"
if pveum role list --output-format json | grep -q "\"roleid\":\"$ROLE\""; then
  pveum role modify "$ROLE" --privs "${PRIVS// /,}"
  echo "    privileges refreshed"
else
  pveum role add "$ROLE" --privs "${PRIVS// /,}"
  echo "    created"
fi

log "User '$PVE_USER'"
if pveum user list --output-format json | grep -q "\"userid\":\"$PVE_USER\""; then
  skip "user exists"
else
  pveum user add "$PVE_USER" --comment "proxmox-lab Terraform (API token only)"
  echo "    created (no password; token login only)"
fi
pveum acl modify / --users "$PVE_USER" --roles "$ROLE"

log "API token '$PVE_USER!$TOKEN_ID'"
if pveum user token list "$PVE_USER" --output-format json | grep -q "\"tokenid\":\"$TOKEN_ID\""; then
  skip "token exists (secret was shown when it was created; to rotate: pveum user token remove $PVE_USER $TOKEN_ID, then re-run)"
else
  secret=$(pveum user token add "$PVE_USER" "$TOKEN_ID" --privsep 1 \
             --comment "proxmox-lab" --output-format json | sed -n 's/.*"value":"\([^"]*\)".*/\1/p')
  echo
  echo "    ***********************************************************************"
  echo "    TOKEN SECRET (shown once; store it now):"
  echo "      proxmox_api_token = \"$PVE_USER!$TOKEN_ID=$secret\""
  echo "    ***********************************************************************"
fi
# privilege-separated token: grant it the role explicitly
pveum acl modify / --tokens "$PVE_USER!$TOKEN_ID" --roles "$ROLE"

# 3. Template 9000 ---------------------------------------------------------------------------
log "Template VMID $TEMPLATE_ID"
if qm status "$TEMPLATE_ID" >/dev/null 2>&1; then
  skip "VMID $TEMPLATE_ID exists ($(qm config "$TEMPLATE_ID" | awk -F': ' '/^name:/{print $2}')); delete it first to rebuild"
else
  command -v virt-customize >/dev/null || { echo "    installing libguestfs-tools"; apt-get update -qq && apt-get install -y -qq libguestfs-tools; }
  mkdir -p "$WORKDIR" && cd "$WORKDIR"
  echo "    downloading $IMG_FILE"
  curl -fsSLO "$IMG_BASE/$IMG_FILE"
  curl -fsSLO "$IMG_BASE/SHA256SUMS"
  grep " \*\?$IMG_FILE\$" SHA256SUMS | sha256sum -c -
  echo "    baking in qemu-guest-agent"
  virt-customize -a "$IMG_FILE" --install qemu-guest-agent --truncate /etc/machine-id
  qm create "$TEMPLATE_ID" --name "$TEMPLATE_NAME" --ostype l26 \
    --cpu host --cores 2 --memory 2048 \
    --net0 "virtio,bridge=$BRIDGE" \
    --scsihw virtio-scsi-single \
    --agent enabled=1 \
    --serial0 socket --vga serial0 \
    --tags "template"
  qm set "$TEMPLATE_ID" --scsi0 "$STORAGE:0,import-from=$WORKDIR/$IMG_FILE,format=qcow2,discard=on,ssd=1,iothread=1"
  qm set "$TEMPLATE_ID" --ide2 "$STORAGE:cloudinit" --boot order=scsi0
  qm template "$TEMPLATE_ID"
  rm -f "$WORKDIR/$IMG_FILE" "$WORKDIR/SHA256SUMS"
  echo "    template $TEMPLATE_NAME ($TEMPLATE_ID) ready"
fi

log "Done on $(hostname). Verify:"
echo "    pvesm status --content snippets"
echo "    qm config $TEMPLATE_ID | head"
echo "    pveum user token permissions $PVE_USER $TOKEN_ID --path / | head"
