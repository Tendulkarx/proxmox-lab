# Two standalone hosts, so one provider alias each.
# Tokens come from 1Password at run time via `op run --env-file=.env.op` (see Makefile):
#   TF_VAR_prx1_api_token / TF_VAR_prx2_api_token

provider "proxmox" {
  alias     = "prx1"
  endpoint  = "https://10.69.20.130:8006/"
  api_token = var.prx1_api_token
  insecure  = true # self-signed cert on the host itself
}

provider "proxmox" {
  alias     = "prx2"
  endpoint  = "https://10.69.20.131:8006/"
  api_token = var.prx2_api_token
  insecure  = true
}
