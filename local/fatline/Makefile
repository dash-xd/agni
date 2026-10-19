SHELL := /bin/bash
.DEFAULT_GOAL := help
NIX ?= nix
WORKSPACE ?= $(CURDIR)/.fatline-workspace
export FATLINE_WORKSPACE := $(WORKSPACE)

.PHONY: help bootstrap preflight build qualify
help:
	@echo "make bootstrap  # clone Logma, Prajapati, Smoke and pin SHAs"
	@echo "make preflight  # verify pinned checkouts"
	@echo "make build      # build three Go repositories"
	@echo "make qualify    # minimal local checks"

bootstrap preflight build qualify:
	$(NIX) run .#$@
