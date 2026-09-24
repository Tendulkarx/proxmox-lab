# proxmox-lab: common commands. Secrets come from 1Password via `op run`.
#   make up                 create/update lab VMs to match terraform/envs/lab/vms.auto.tfvars
#   make plan               preview changes
#   make list               show managed VMs
#   make down NAME=tstsrv1    destroy ONE lab VM (it comes back on next `make up` unless removed from tfvars)
#   make destroy-lab        destroy ALL lab VMs
#   make ssh NAME=tstsrv1     SSH into a lab VM
#   make configure          run Ansible (baseline, shell, Docker) against ENV's VMs (ENV=lab|prod)
#   make hosts-check        dry run of Proxmox host hardening;  make hosts  applies it
#   make backup-vm HOST=<ip> VMID=<id>   one-off backup of a VM to that host's `data` storage
#   make patch ENV=prod NAME=prdsrv2      OS updates + reboot if needed, one VM at a time
#   make audit              read-only audit of hosts AND all VMs; reports land in audit/
#   make prod-generate      Phase 4: describe existing prod VMs as Terraform (no changes made)

ENV ?= lab
TF  := op run --env-file=.env.op -- terraform -chdir=terraform/envs/$(ENV)
# Lab VMs are rebuilt at the same IPs with new host keys, so they get their own known_hosts
# file (never your main ~/.ssh/known_hosts), cleared whenever lab VMs are destroyed.
LAB_KNOWN_HOSTS := $(HOME)/.ssh/known_hosts.proxmox-lab

.PHONY: help check init plan up list down destroy-lab ssh fmt validate ansible-deps configure forget-host hosts hosts-check prod-generate

help:
	@sed -n '2,14p' Makefile

check:
	@command -v terraform >/dev/null || { echo "Install terraform: brew install hashicorp/tap/terraform"; exit 1; }
	@command -v op >/dev/null        || { echo "Install 1Password CLI: brew install 1password-cli"; exit 1; }
	@test -f ~/.ssh/id_ed25519_homelab.pub || { echo "Missing ~/.ssh/id_ed25519_homelab.pub"; exit 1; }
	@# No secret reads here: each one costs a Touch ID prompt. `op run` reads the tokens and
	@# names any missing item (vault Development: proxmox-prx1-terraform, proxmox-prx2-terraform).
	@op account list 2>/dev/null | grep -q . || { echo "1Password CLI has no account: turn on Settings > Developer > Integrate with 1Password CLI"; exit 1; }
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
	@if [ "$(ENV)" = "lab" ]; then rm -f $(LAB_KNOWN_HOSTS); echo "cleared lab host keys ($(LAB_KNOWN_HOSTS)); they are re-learned on first connect"; fi

list:
	@$(TF) output vms

down: check
	@test -n "$(NAME)" || { echo "Usage: make down NAME=<vm>"; exit 1; }
	@test "$(ENV)" = "lab" || { echo "make down only works on ENV=lab"; exit 1; }
	$(TF) destroy -target='module.vm_prx1["$(NAME)"]' -target='module.vm_prx2["$(NAME)"]'
	@$(MAKE) --no-print-directory forget-host NAME=$(NAME)

destroy-lab: check
	@test "$(ENV)" = "lab" || { echo "destroy-lab only works on ENV=lab"; exit 1; }
	$(TF) destroy
	@rm -f $(LAB_KNOWN_HOSTS) && echo "cleared $(LAB_KNOWN_HOSTS)"

ssh:
	@test -n "$(NAME)" || { echo "Usage: make ssh NAME=<vm>"; exit 1; }
	@ip=$$(awk -v n='"$(NAME)":' '$$1==n{f=1} f&&/ansible_host/{gsub(/"/,"",$$2); print $$2; exit}' ansible/inventory/lab.generated.yml); \
	  test -n "$$ip" || { echo "$(NAME) not in lab inventory; run make up first"; exit 1; }; \
	  ssh -i ~/.ssh/id_ed25519_homelab -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$(LAB_KNOWN_HOSTS) turbx@$$ip

ansible-deps:
	@command -v ansible-playbook >/dev/null || { echo "Install Ansible: brew install ansible"; exit 1; }
	cd ansible && ansible-galaxy collection install -r requirements.yml

configure:
	@command -v ansible-playbook >/dev/null || { echo "Install Ansible: brew install ansible"; exit 1; }
	@inv=ansible/inventory/$(ENV).yml; test -f $$inv || inv=ansible/inventory/$(ENV).generated.yml; \
	  test -f $$inv || { echo "No inventory for $(ENV); run make up first"; exit 1; }; \
	  cd ansible && ANSIBLE_SSH_ARGS="-o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=accept-new $(if $(filter lab,$(ENV)),-o UserKnownHostsFile=$(LAB_KNOWN_HOSTS),)" \
	  ansible-playbook -i ../$$inv playbooks/site.yml $(if $(NAME),--limit $(NAME),) $(ARGS)

hosts-check:
	cd ansible && ansible-playbook -i inventory/proxmox.yml playbooks/proxmox-hosts.yml --check --diff $(ARGS)

hosts:
	cd ansible && ansible-playbook -i inventory/proxmox.yml playbooks/proxmox-hosts.yml $(ARGS)

prod-generate: check
	@test ! -f terraform/envs/prod/generated.tf || { echo "terraform/envs/prod/generated.tf already exists; move it aside first"; exit 1; }
	op run --env-file=.env.op -- terraform -chdir=terraform/envs/prod plan -generate-config-out=generated.tf

# Remove a lab VM's old host key (it is regenerated every time the VM is rebuilt)
forget-host:
	@test -n "$(NAME)" || { echo "Usage: make forget-host NAME=<vm>"; exit 1; }
	@ip=$$(awk -v n='"$(NAME)":' '$$1==n{f=1} f&&/ansible_host/{gsub(/"/,"",$$2); print $$2; exit}' ansible/inventory/lab.generated.yml 2>/dev/null); \
	  test -n "$$ip" && ssh-keygen -R "$$ip" -f $(LAB_KNOWN_HOSTS) >/dev/null 2>&1; \
	  echo "forgot host key for $(NAME) $${ip:-(ip unknown)}"

.PHONY: audit audit-hosts audit-vms
audit: audit-hosts audit-vms
	@ls -l audit/

audit-hosts:
	@for h in 10.69.20.130 10.69.20.131; do \
	  scp -q -i ~/.ssh/id_ed25519_homelab scripts/audit-host.sh root@$$h:/root/ && \
	  ssh -i ~/.ssh/id_ed25519_homelab root@$$h 'bash /root/audit-host.sh >/dev/null; echo /root/pve-audit-$$(hostname).txt' \
	  | xargs -I{} scp -q -i ~/.ssh/id_ed25519_homelab root@$$h:{} audit/ && echo "audited $$h"; \
	done
	@ls -l audit/

audit-vms:
	cd ansible && ANSIBLE_SSH_ARGS="-o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=accept-new" ansible-playbook -i inventory/prod.yml -i inventory/lab.generated.yml playbooks/audit.yml

.PHONY: backup-vm patch
backup-vm:
	@test -n "$(HOST)" -a -n "$(VMID)" || { echo "Usage: make backup-vm HOST=10.69.20.130 VMID=101"; exit 1; }
	ssh -i ~/.ssh/id_ed25519_homelab root@$(HOST) 'vzdump $(VMID) --mode snapshot --storage data --compress zstd --notes-template "manual {{guestname}}" && pvesm list data --content backup --vmid $(VMID)'

patch:
	@test -n "$(NAME)" || { echo "Usage: make patch ENV=prod NAME=<vm>"; exit 1; }
	@inv=ansible/inventory/$(ENV).yml; test -f $$inv || inv=ansible/inventory/$(ENV).generated.yml; \
	  cd ansible && ANSIBLE_SSH_ARGS="-o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=accept-new $(if $(filter lab,$(ENV)),-o UserKnownHostsFile=$(LAB_KNOWN_HOSTS),)" \
	  ansible-playbook -i ../$$inv playbooks/patch.yml --limit $(NAME) $(ARGS)
