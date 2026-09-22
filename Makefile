# proxmox-lab: common commands. Secrets come from 1Password via `op run`.
#   make up                 create/update lab VMs to match terraform/envs/lab/vms.auto.tfvars
#   make plan               preview changes
#   make list               show managed VMs
#   make down NAME=test1    destroy ONE lab VM (it comes back on next `make up` unless removed from tfvars)
#   make destroy-lab        destroy ALL lab VMs
#   make ssh NAME=test1     SSH into a lab VM
#   make configure          run Ansible (baseline + your shell) against ENV's VMs

ENV ?= lab
TF  := op run --env-file=.env.op -- terraform -chdir=terraform/envs/$(ENV)

.PHONY: help check init plan up list down destroy-lab ssh fmt validate ansible-deps configure

help:
	@sed -n '2,9p' Makefile

check:
	@command -v terraform >/dev/null || { echo "Install terraform: brew install hashicorp/tap/terraform"; exit 1; }
	@command -v op >/dev/null        || { echo "Install 1Password CLI: brew install 1password-cli"; exit 1; }
	@test -f ~/.ssh/id_ed25519_homelab.pub || { echo "Missing ~/.ssh/id_ed25519_homelab.pub"; exit 1; }
	@op read "op://Development/proxmox-prx1-terraform/credential" >/dev/null || { echo "Cannot read prx1 token from 1Password (vault Development, item proxmox-prx1-terraform, field credential)"; exit 1; }
	@op read "op://Development/proxmox-prx2-terraform/credential" >/dev/null || { echo "Cannot read prx2 token from 1Password (vault Development, item proxmox-prx2-terraform, field credential)"; exit 1; }
	@echo "check: OK"

init: check
	terraform -chdir=terraform/envs/$(ENV) init -upgrade

fmt:
	terraform fmt -recursive terraform

validate:
	terraform -chdir=terraform/envs/$(ENV) validate

plan: check
	$(TF) plan

up: check
	$(TF) apply

list:
	@$(TF) output vms

down: check
	@test -n "$(NAME)" || { echo "Usage: make down NAME=<vm>"; exit 1; }
	@test "$(ENV)" = "lab" || { echo "make down only works on ENV=lab"; exit 1; }
	$(TF) destroy -target='module.vm_prx1["$(NAME)"]' -target='module.vm_prx2["$(NAME)"]'

destroy-lab: check
	@test "$(ENV)" = "lab" || { echo "destroy-lab only works on ENV=lab"; exit 1; }
	$(TF) destroy

ssh:
	@test -n "$(NAME)" || { echo "Usage: make ssh NAME=<vm>"; exit 1; }
	@ip=$$(awk -v n='"$(NAME)":' '$$1==n{f=1} f&&/ansible_host/{gsub(/"/,"",$$2); print $$2; exit}' ansible/inventory/lab.generated.yml); \
	  test -n "$$ip" || { echo "$(NAME) not in lab inventory; run make up first"; exit 1; }; \
	  ssh -i ~/.ssh/id_ed25519_homelab -o StrictHostKeyChecking=accept-new turbx@$$ip

ansible-deps:
	@command -v ansible-playbook >/dev/null || { echo "Install Ansible: brew install ansible"; exit 1; }
	cd ansible && ansible-galaxy collection install -r requirements.yml

configure:
	@command -v ansible-playbook >/dev/null || { echo "Install Ansible: brew install ansible"; exit 1; }
	@test -f ansible/inventory/$(ENV).generated.yml || { echo "No inventory for $(ENV); run make up first"; exit 1; }
	cd ansible && ansible-playbook -i inventory/$(ENV).generated.yml playbooks/site.yml $(if $(NAME),--limit $(NAME),)
