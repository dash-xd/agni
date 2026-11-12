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

## Probot webhook integration: native ARM64 artifact gate

The `#qualify-integration` app accepts `--scenario probot-webhook --phase preflight|artifacts|live`.
The previously qualified `preflight` checks exact source markers and runs the Probot
Skymill/Logma Node client contract tests.

`--phase artifacts` reuses the same pinned source manifest and produces
`skymill-http` (`cmd/skymill-http`) and `logma-lifecycle`
(`cmd/api-lifecycle`) with Go 1.26, `CGO_ENABLED=0`, and the Linux ARM64
target. It checks build metadata and registers each result as a Nix GC root
under the Nix-Alpine writer's state directory. Probot's exact staged
package manifest/lockfile and Node source syntax are checked, but **npm
dependency installation, immutable OCI packaging, CoreOS deployment, and
GitHub webhook delivery are not included in this phase**. These are
explicit follow-on gates rather than implicit success claims.

The older `coreos-services-vm1` package already orchestrates Logma and
Skymill guest-side user-systemd services with isolated Redis credentials.
It references older pinned upstream source revisions and must not be
silently promoted as proof that the new Probot source manifest is running.
A subsequent live composition must bind the new native artifacts to
that existing Agni guest contract and add the Probot service, then verify
GitHub App installation credentials independently of GHXD user OAuth.

`--phase live` deliberately runs source checks and the artifact gate
but fails closed with
`AGNI_PROBOT_WEBHOOK_INTEGRATION=blocked` until guest service and
GitHub authority wiring are qualified. A successful build is not a
webhook-settlement or Logmash/SSE observation qualification.
