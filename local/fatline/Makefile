SHELL := /bin/bash
.DEFAULT_GOAL := help
NIX ?= nix
WORKSPACE ?= $(CURDIR)/.fatline-workspace
export FATLINE_WORKSPACE := $(WORKSPACE)

.PHONY: help bootstrap preflight build qualify qualify-integration advance-pin check-generator
help:
	@echo "make bootstrap  # clone Logma, Prajapati, Smoke and pin SHAs"
	@echo "make preflight  # verify pinned checkouts"
	@echo "make build      # build three Go repositories"
	@echo "make qualify    # minimal local checks"
	@echo "make check-generator  # host Podman Quadlet generator dry-run (no install)"

bootstrap preflight build qualify qualify-integration advance-pin:
	$(NIX) run .#$@

check-generator:
	@bash ./scripts/check-generator.sh
