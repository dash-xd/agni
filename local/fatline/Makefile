SHELL := /bin/bash
.DEFAULT_GOAL := help
NIX ?= nix
WORKSPACE ?= $(CURDIR)/.fatline-workspace
export FATLINE_WORKSPACE := $(WORKSPACE)

.PHONY: help bootstrap preflight build qualify qualify-integration advance-pin test-acl render-acl
help:
	@echo "make bootstrap  # clone Logma, Prajapati, Smoke and pin SHAs"
	@echo "make preflight  # verify pinned checkouts"
	@echo "make build      # build three Go repositories"
	@echo "make qualify    # minimal local checks\n\t@echo "nix build .#fatline  # declarative composition (requires qualified image digests)""
	@echo "make test-acl   # verify Agni ACL policy rendering and secret handling"
	@echo "make render-acl CREDENTIAL_DIR=... OUTPUT=...  # render users.acl from host-only password files"

bootstrap preflight build qualify qualify-integration advance-pin:
	$(NIX) run .#$@

test-acl:
	python3 scripts/test-render-users-acl.py

render-acl:
	@test -n "$(CREDENTIAL_DIR)" -a -n "$(OUTPUT)" || { echo "CREDENTIAL_DIR and OUTPUT are required" >&2; exit 2; }
	python3 scripts/render-users-acl.py acl-policy.json "$(CREDENTIAL_DIR)" "$(OUTPUT)"

