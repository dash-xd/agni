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
SMOKE_CHECKOUT ?= smoke20261115
GHXD_NATIVE_GRANTS_ACK ?=
AGNI_CHECKOUT ?= $(notdir $(abspath $(CURDIR)/../..))

# Keep all nix.xd operation logs in one user-owned location.
# The generic nix.xd log wrapper supplies action, machine and timestamp fields.
NIX_XD_LOG_DIR ?= $(HOME)/.local/nix.xd/logs
NIX_XD_LOG_COMPOSITION ?= fatline

export NIX_XD_DIR DEPLOYMENT PROVIDER OWNER_SCOPE MACHINE
export NIX_XD_LOG_DIR NIX_XD_LOG_COMPOSITION
export GUEST_VM_INSTANCE GUEST_STATE_ROOT GUEST_SSH_USER GUEST_SSH_PORT GUEST_SSH_KEY GUEST_SSH_HOST

.PHONY: architecture-verify-sources
architecture-verify-sources:
	@test -n "$(NIX_XD_DIR)" || { echo 'NIX_XD_DIR required' >&2; exit 2; }
	@python3 qualification/verify-architecture-sources.py "$(NIX_XD_DIR)" "$(abspath $(NIX_XD_DIR)/../$(SMOKE_CHECKOUT))"

.PHONY: native-source-sync
.PHONY: architecture-qualify
.PHONY: check-architecture qualification qualification-check
check-architecture:
	@python3 qualification/check-architecture.py

# One operator-facing selection entry. Legacy deployment-* targets remain
# transitional wrappers until their host-action callers have been migrated.
qualification:
	@case "$(QUALIFICATION)" in \
	  source-sync-native) $(MAKE) --no-print-directory native-source-sync ;; \
	  factory-live) $(MAKE) --no-print-directory deployment-qualify-factory-live ;; \
	  factory-contract) $(MAKE) --no-print-directory deployment-qualify-factory-contract ;; \
	  declarative-generator) $(MAKE) --no-print-directory deployment-qualify-declarative-generator ;; \
	  *) echo 'QUALIFICATION=source-sync-native|factory-live|factory-contract|declarative-generator required' >&2; exit 2 ;; \
	esac

native-source-sync: architecture-verify-sources
	@GHXD_NATIVE_GRANTS_ACK="$(GHXD_NATIVE_GRANTS_ACK)" SMOKE_CHECKOUT="$(SMOKE_CHECKOUT)" \
	  bash operations/native-source-sync.sh

qualification-check: check-architecture check-deployment

# Cross-repository admission check. Host Git staging is explicitly transitional;
# the only Linux action uses the generic Nix-Alpine flake runner.
architecture-qualify: qualification-check architecture-verify-sources
	@test -n "$(NIX_XD_DIR)" -a -f "$(NIX_XD_DIR)/Makefile" || { echo 'NIX_XD_DIR required' >&2; exit 2; }
	@$(MAKE) --no-print-directory -C "$(NIX_XD_DIR)" architecture-check
	@$(MAKE) --no-print-directory -C "$(NIX_XD_DIR)" architecture-audit \
	  AGNI_DIR="$(abspath $(CURDIR)/../..)" \
	  SMOKE_DIR="$(abspath $(NIX_XD_DIR)/../$(SMOKE_CHECKOUT))"
	@$(MAKE) --no-print-directory -C "$(NIX_XD_DIR)" stage \
	  MACHINE="$(MACHINE)" PROVIDER="$(PROVIDER)" SCOPE="$(OWNER_SCOPE)" \
	  CHECKOUT="$(AGNI_CHECKOUT)"
	@$(MAKE) --no-print-directory -C "$(NIX_XD_DIR)" show \
	  MACHINE="$(MACHINE)" PROVIDER="$(PROVIDER)" SCOPE="$(OWNER_SCOPE)" \
	  FLAKE="$(AGNI_CHECKOUT)/local/fatline"
	@$(MAKE) --no-print-directory -C "$(NIX_XD_DIR)" stage \
	  MACHINE="$(MACHINE)" PROVIDER="$(PROVIDER)" SCOPE="$(OWNER_SCOPE)" \
	  CHECKOUT="$(SMOKE_CHECKOUT)"
	@$(MAKE) --no-print-directory -C "$(NIX_XD_DIR)" run \
	  MACHINE="$(MACHINE)" PROVIDER="$(PROVIDER)" SCOPE="$(OWNER_SCOPE)" \
	  FLAKE="$(SMOKE_CHECKOUT)" TARGET='#architecture-check'
	@echo 'AGNI_ARCHITECTURE_QUALIFICATION=passed contracts=static native_runner=nix-alpine ghxd_host=migration-pending'


help:
	@printf '%s\n' \
	  'make qualification-check                            Architecture and static gate checks' \
	  'make architecture-qualify NIX_XD_DIR=...             Cross-repo static audit and Smoke Nix-Alpine check' \
	  'make qualification QUALIFICATION=source-sync-native GHXD_NATIVE_GRANTS_ACK=TRUST-NIX-ALPINE-OWNER' \
	  'make qualification QUALIFICATION=factory-live DEPLOYMENT=vm1  Execute selected live gate' \
	  'make check-architecture                             Audit Agni owner and source-pinning contracts'
	@printf '%s\n' 'Historical deployment-* operations: make -C local/fatline legacy-help'

# Compatibility targets remain here only as a migration boundary.
include operations/deployment-compat.mk
