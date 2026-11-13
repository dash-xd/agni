SHELL := /bin/bash
.DEFAULT_GOAL := help

# Agni owns deployment names and lifecycle operations; nix.xd owns transport.
NIX_XD_DIR ?= $(abspath $(CURDIR)/../../../nix.xd20261112)
DEPLOYMENT ?= vm1
PROVIDER ?= podman
OWNER_SCOPE ?= nix-xd-arm
MACHINE ?= coreos-arm64

export NIX_XD_DIR DEPLOYMENT PROVIDER OWNER_SCOPE MACHINE
export GUEST_VM_INSTANCE GUEST_STATE_ROOT GUEST_SSH_USER GUEST_SSH_PORT GUEST_SSH_KEY GUEST_SSH_HOST

.PHONY: help deployment-assess deployment-verify deployment-review deployment-migrate-stage check-deployment

help:
	@printf '%s\n' \
	  'make deployment-assess DEPLOYMENT=vm1         Capture read-only legacy VM1 evidence' \
	  'make deployment-verify DEPLOYMENT=vm1         Verify exact VM1 application bundle' \
	  'make deployment-review DEPLOYMENT=vm1         Review pinned migration compatibility' \
	  'make deployment-migrate-stage DEPLOYMENT=vm1  Render private five-role migration generation; no activation' \
	  'make check-deployment                       Check host workflow syntax and interface'

deployment-assess:
	@bash operations/guest-migration.sh assess

deployment-verify:
	@bash operations/guest-migration.sh verify

deployment-review:
	@bash operations/guest-migration.sh review

deployment-migrate-stage:
	@bash operations/guest-migration.sh migrate-stage

check-deployment:
	@bash -n operations/guest-migration.sh
	@bash operations/test-guest-migration.sh
