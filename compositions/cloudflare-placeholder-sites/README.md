# Generic Cloudflare placeholder composition

This is a **staged, non-deploying** implementation. No Cloudflare resources are modified by CI.

- `hosts.json` is a synthetic example using `example.com`.
- `validate.mjs` validates the manifest schema, hostname-to-zone relationships and duplicate hostnames.
- `worker.mjs` is an independent, minimal HTTP response handler with exact-host routing.
- `build.mjs` embeds a caller-provided manifest into a self-contained Worker ES module.
- `terraform/main.tf` declares one Worker script and exact Custom Domain bindings; consumers provide account ID, service name, worker file, and zone IDs through Terraform variables.
- `.github/workflows/placeholder-sites-qualification.yml` uses GitHub-hosted `ubuntu-latest` with no Cloudflare credentials and never calls Terraform plan/apply against a live account.

Local checks:

```sh
node compositions/cloudflare-placeholder-sites/validate.mjs compositions/cloudflare-placeholder-sites/hosts.json
node --test compositions/cloudflare-placeholder-sites/test.mjs
node compositions/cloudflare-placeholder-sites/build.mjs compositions/cloudflare-placeholder-sites/hosts.json /tmp/placeholder-worker.mjs
node --check /tmp/placeholder-worker.mjs
```

Production destinations and ownership proofs belong in the caller (Huram), not in Agni. A later separate workflow must collect delegated DNS and Worker Custom Domain inventory, bind exact Agni SHA and manifest digest to plan evidence, review conflicts, and require explicit authorization before any apply. Existing services must never be overwritten implicitly.

**Not yet qualified:** provider-authenticated Terraform plan, actual zone ownership for eight hosts, custom-domain conflict handling, production Worker artifact digest, runtime Cloudflare test, and promotion. The passing CI currently proves only local source/build/format/terraform validate, not deployment readiness.
