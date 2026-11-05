# Cloudflare placeholder sites — staged composition

This is a **non-deployed candidate**, not a Terraform apply plan. No DNS, Custom Domain, or Worker is provisioned by these files.

## Inputs and behavior

- `hosts.json` declares eight exact hostnames, parent zones, and display titles.
- `worker.mjs` exports a dependency-free request handler. A future Cloudflare entrypoint can bind it to the manifest at build time.
- `test.mjs` qualifies exact hostname responses and unknown-host failure locally with Node's built-in test runner.

Run `node --test compositions/cloudflare-placeholder-sites/test.mjs` from the repository root.

## Required integration before promotion

1. Huram: inventory all eight zones with short-lived scoped read-only children, including DNS records, Worker routes, Custom Domains, and certificate conflicts. Capture immutable evidence and fail closed on absent zones.
2. Agni: add an explicit plan-only Terraform composition for Worker script and exact Custom Domain resources. Import or exclude existing managed resources; never replace unrelated records implicitly.
3. Huram: verify the source SHA, manifest digest, Terraform plan digest, local runtime, and approval before a separate apply operation. Use existing delegated child-token lifecycle and revocation.
4. dashxd.com: stage the outbound navigation change separately and release only after the destination HTTPS checks pass.

The manifest is **intent**, not evidence of zone ownership or live DNS. `execute=false` must be the default for any future pseudo-dispatch. No deployment workflow is wired here.
