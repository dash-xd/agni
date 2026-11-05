# Fatline qualification

Agni owns Fatline's composition, source pins, ACL policy, runtime assertions, and qualification plan. The plan is exposed as the `qualify-plan` flake app. Nix-Alpine owns the generic Make dispatcher and runtime adapter; this directory intentionally has no application Makefile.

From the Nix-Alpine checkout, invoke the plan through its generic Make interface:

```sh
make qualify-plan \
  PLAN_REPO=dash-xd/agni \
  PLAN_BRANCH=codex/coreos-fatline-qemu \
  PLAN_REV=<full-agni-commit-sha> \
  PLAN_CHECKOUT=compositions/agni \
  PLAN_FILE=local/fatline/qualification/plan.json \
  PLAN_FLAKE=local/fatline \
  PLAN_TARGET=qualify-plan \
  PLAN_SOURCES=local/fatline/qualification/sources.tsv \
  PLAN_GATE=all
```

The exact source revision is part of the qualification input. The source manifest resolves component checkouts at their recorded commit IDs. Artifact identity manifests may be passed through Nix-Alpine's generic artifact option.

The plan uses the `nix.xd qualification-plan/v1` module protocol. Each module declares a kind, phases, inputs, outputs, dependencies, and cleanup policy. Gates select module entry points; Agni resolves their dependency graph and runs shared prerequisites once. The module executor currently maps artifact builds, provider builds, ACL policy checks, and Podman/systemd composition gates to Agni-owned handlers. Runtime modules clean up by default; `RETAIN=1` preserves only the final selected runtime for inspection.

The Podman/systemd gates exercise the host topology through Nix-Alpine's rootless Podman socket and user systemd bus. This does not qualify CoreOS/QEMU or GCP. Those are separate runtime adapters and must report only the capabilities they actually provide.

Keep credential material outside the checkout. The tracked ACL policy contains no plaintext credentials; render deployment ACL files from protected credential inputs and qualify the generated policy on the selected runtime topology.
