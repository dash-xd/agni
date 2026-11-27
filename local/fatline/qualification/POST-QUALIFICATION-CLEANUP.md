# Qualification and post-qualification cleanup contract

This is a normative companion to `CANONICAL-ARCHITECTURE.md`. A green static
architecture run is not authorization to delete the fallback credential writer
or to activate Fatline. Run gates on exact source SHAs and record the run URL,
runner architecture, exit status, failed negative cases, and scoped teardown.

## Execution stages

1. **Static on aarch64:** Pin three repository SHAs, validate the source lock,
   run each architecture guard and their negative tests. A Blacksmith 2-vCPU
   ARM runner is suitable. No Podman Machine, Mac mounts or live credentials
   are implied by this pass.
2. **GHXD live on the selected owner:** Bootstrap a disposable Nix-Alpine owner
   with explicit grants. Verify the mounts, one-writer exclusivity, SOPS+age
   authorization/refresh, positive source generation, wrong-SHA refusal,
   absence of secret leakage, then scoped owner/volume teardown. Capture
   evidence before removing the historical host writer.
3. **Fatline VM:** Verify exact artifact and VM identity, factory-live with
   observable idempotent effects and unchanged original service InvocationIDs,
   then a separate supervised systemd/Quadlet crash/restart/reclaim gate.
   Neither static ARM nor userspace simulation counts as CoreOS VM acceptance.
4. **Cutover:** Migrate all callers to the canonical selectors; update locks
   and run all affected gates. Remove host-action scripts, dispatcher and
   deployment aliases *only after* no remaining callers and live evidence.
   Do not keep a second working compatibility path for convenience.
5. **Cleanup:** Stop only the test workloads owned by this run; detach mounts,
   remove temporary containers/volumes and expired stage roots by exact recorded
   identity, and preserve evidence before deleting runtime objects. Confirm
   baseline VM invocation identities still match. Never use broad volume or
   worktree pruning on a shared qualification machine.
6. **Merge hygiene:** Merge passing candidates only after pinning downstream
   revisions and checking all required gates. Delete only a specific merged,
   unprotected, unreferenced feature branch after checking it is not a source
   lock, active PR head, deployment reference or worktree. Keep CalVer
   qualification refs that are still referenced. No wildcard branch deletion.

## Evidence record per gate

| Field | Required |
| --- | --- |
| Identity | Repository, 40-hex revision, lock digest and workflow run URL |
| Runner | Provider, OS, `uname -m`, CPU class and execution scope |
| Acceptance | Gate name, observed positive and negative cases, raw exit code |
| Resources | Exact volumes, containers, stage roots, VM boot and invocation identities |
| Cleanup | Before/after resource inventory, retained evidence locations |
| Outcome | `static`, `live-passed`, `failed` or `blocked` (never inferred) |

## Agent stop conditions

- No credentials or Mac/CoreOS VM: run static ARM checks only and report the live
  gates as blocked; do not simulate a pass marker or weaken an assertion.
- A shared resource cannot be attributed to this run: preserve it.
- A branch is not proven merged and unreferenced: preserve it.
- A legacy adapter still has callers: prohibit new callers, keep the adapter,
  and report its removal as a subsequent gate.

The architecture guards must accept **shrinking** the recorded legacy
inventory and reject **expanding** it. Never write a check whose assertion
requires a retired adapter to be recreated.
