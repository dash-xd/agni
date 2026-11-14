SHELL := /bin/bash
.DEFAULT_GOAL := help

# Agni owns deployment names and lifecycle operations; nix.xd owns transport.
# Explicitly select the sibling nix.xd checkout. Never default to an old dated workspace.
NIX_XD_DIR ?=
DEPLOYMENT ?= vm1
PROVIDER ?= podman
OWNER_SCOPE ?= nix-xd-arm
MACHINE ?= coreos-arm64

export NIX_XD_DIR DEPLOYMENT PROVIDER OWNER_SCOPE MACHINE
export GUEST_VM_INSTANCE GUEST_STATE_ROOT GUEST_SSH_USER GUEST_SSH_PORT GUEST_SSH_KEY GUEST_SSH_HOST

.PHONY: help deployment-assess deployment-verify deployment-review deployment-migrate-stage deployment-migrate-verify deployment-migrate-activation-plan deployment-migrate-activation-check deployment-migrate-recovery-qualify deployment-migrate-activate deployment-migrate-activate-sandbox deployment-recover-sandbox-http deployment-qualify-runtime deployment-qualify-integration deployment-qualify-worker-candidate deployment-qualify-worker-live deployment-qualify-worker-bootstrap deployment-qualify-worker-delivery deployment-qualify-worker-recovery deployment-qualify-worker-memory deployment-diagnose-runtime-network check-deployment

help:
	@printf '%s\n' \
	  'make deployment-assess DEPLOYMENT=vm1         Capture read-only legacy VM1 evidence' \
	  'make deployment-verify DEPLOYMENT=vm1         Verify exact VM1 application bundle' \
	  'make deployment-review DEPLOYMENT=vm1         Review pinned migration compatibility' \
	  'make deployment-migrate-stage DEPLOYMENT=vm1  Render private five-role migration generation; no activation' \
	  'make deployment-migrate-verify DEPLOYMENT=vm1 Verify existing staged Quadlets; no rebuild or activation' \
	  'make deployment-migrate-activation-plan DEPLOYMENT=vm1 Snapshot rollback baseline; no service restart' \
	  'make deployment-migrate-activation-check DEPLOYMENT=vm1  Revalidate rollback snapshot and live baseline; no restart' \
	  'make deployment-migrate-recovery-qualify DEPLOYMENT=vm1 Isolated legacy rollback restore; no restart' \
	  'make deployment-migrate-activate DEPLOYMENT=vm1         Production activation remains blocked' \
	  'make deployment-migrate-activate-sandbox DEPLOYMENT=vm1 REDIS_DATA_LOSS_ACK=DISCARD-VM1-REDIS-MEMORY  Local disposable five-role cutover' \
	  'make deployment-recover-sandbox-http DEPLOYMENT=vm1  Repair installed Skymill token after interrupted cutover' \
	  'make deployment-qualify-runtime DEPLOYMENT=vm1  Live five-role ACL, HTTP, Skymill synthetic delivery checks' \
	  'make deployment-qualify-integration DEPLOYMENT=vm1  Probot Redis ACL and Skymill bounded redelivery gate' \
	  'make deployment-qualify-worker-candidate DEPLOYMENT=vm1  Isolated signed webhook and worker fixture; no activation' \
	  'make deployment-qualify-worker-bootstrap DEPLOYMENT=vm1  Isolated Redis + Skymill + worker-enabled HTTP only' \
	  'make deployment-qualify-worker-delivery DEPLOYMENT=vm1   Bootstrap + signed delivery + durable ACK' \
	  'make deployment-qualify-worker-recovery DEPLOYMENT=vm1   Delivery + fault/restart/replay recovery' \
	  'make deployment-qualify-worker-memory DEPLOYMENT=vm1     Ephemeral Redis loss/recovery with fresh delivery' \
	  'make deployment-qualify-worker-live DEPLOYMENT=vm1       Complete gated live candidate; no activation' \
	  'make deployment-diagnose-runtime-network DEPLOYMENT=vm1  Read-only Logma/Skymill/Probot network diagnosis' \
	  'make check-deployment                       Check host workflow syntax, interface, and operator shell safety'

deployment-assess:
	@bash operations/guest-migration.sh assess

deployment-verify:
	@bash operations/guest-migration.sh verify

deployment-review:
	@bash operations/guest-migration.sh review

deployment-migrate-stage:
	@bash operations/guest-migration.sh migrate-stage

deployment-migrate-verify:
	@bash operations/guest-migration.sh migrate-verify

deployment-migrate-activation-plan:
	@bash operations/guest-migration.sh migrate-activation-plan
deployment-migrate-activation-check:
	@bash operations/guest-migration.sh migrate-activation-check

deployment-migrate-recovery-qualify:
	@bash operations/guest-migration.sh migrate-recovery-qualify

deployment-diagnose-runtime-network:
	@bash operations/guest-migration.sh diagnose-runtime-network

deployment-qualify-worker-bootstrap:
	@bash operations/guest-migration.sh qualify-worker-bootstrap

deployment-qualify-worker-delivery:
	@bash operations/guest-migration.sh qualify-worker-delivery

deployment-qualify-worker-recovery:
	@bash operations/guest-migration.sh qualify-worker-recovery

deployment-qualify-worker-memory:
	@bash operations/guest-migration.sh qualify-worker-memory

deployment-qualify-worker-live:
	@bash operations/guest-migration.sh qualify-worker-live

deployment-qualify-worker-candidate:
	@bash operations/guest-migration.sh qualify-worker-candidate

deployment-qualify-integration:
	@bash operations/guest-migration.sh qualify-integration

deployment-qualify-runtime:
	@bash operations/guest-migration.sh qualify-runtime

deployment-recover-sandbox-http:
	@bash operations/guest-migration.sh recover-sandbox-http

deployment-migrate-activate-sandbox:
	@bash operations/guest-migration.sh migrate-activate-sandbox

deployment-migrate-activate:
	@echo 'AGNI_ACTIVATION=blocked reason=readiness-rollback-and-data-loss-authorization-not-yet-qualified' >&2
	@exit 1

check-deployment:
	@bash -n operations/guest-migration.sh
	@bash operations/test-guest-migration.sh
