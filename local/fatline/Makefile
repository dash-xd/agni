SHELL := /bin/bash
.DEFAULT_GOAL := help

# Agni owns deployment names and lifecycle operations; nix.xd owns transport.
# Explicitly select the sibling nix.xd checkout. Never default to an old dated workspace.
NIX_XD_DIR ?=
DEPLOYMENT ?= vm1
PROVIDER ?= podman
OWNER_SCOPE ?= nix-xd-arm
MACHINE ?= coreos-arm64
QUALIFICATION ?=

# Keep all nix.xd operation logs in one user-owned location.
# The generic nix.xd log wrapper supplies action, machine and timestamp fields.
NIX_XD_LOG_DIR ?= $(HOME)/.local/nix.xd/logs
NIX_XD_LOG_COMPOSITION ?= fatline

export NIX_XD_DIR DEPLOYMENT PROVIDER OWNER_SCOPE MACHINE
export NIX_XD_LOG_DIR NIX_XD_LOG_COMPOSITION
export GUEST_VM_INSTANCE GUEST_STATE_ROOT GUEST_SSH_USER GUEST_SSH_PORT GUEST_SSH_KEY GUEST_SSH_HOST

.PHONY: check-architecture qualification qualification-check
check-architecture:
	@python3 qualification/check-architecture.py

# One operator-facing selection entry. Legacy deployment-* targets remain
# transitional wrappers until their host-action callers have been migrated.
qualification:
	@case "$(QUALIFICATION)" in \
	  factory-live) $(MAKE) --no-print-directory deployment-qualify-factory-live ;; \
	  factory-contract) $(MAKE) --no-print-directory deployment-qualify-factory-contract ;; \
	  declarative-generator) $(MAKE) --no-print-directory deployment-qualify-declarative-generator ;; \
	  *) echo 'QUALIFICATION=factory-live|factory-contract|declarative-generator required' >&2; exit 2 ;; \
	esac

qualification-check: check-architecture check-deployment

help:
	@printf '%s\n' \
	  'make qualification-check                            Architecture and static gate checks' \
	  'make qualification QUALIFICATION=factory-live DEPLOYMENT=vm1  Execute selected live gate' \
	  'make check-architecture                             Audit Agni owner and source-pinning contracts'
	@$(MAKE) --no-print-directory legacy-help

# Compatibility targets remain here only as a migration boundary.
include operations/deployment-compat.mk
