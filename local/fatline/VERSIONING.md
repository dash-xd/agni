# Fatline image and composition identity (canonical proposal)

## Identity layers

1. **Nix source**: pinned flake inputs, lockfile, derivation and resulting store archive.
2. **Podman image**: locally imported content identity (inspect `Id`); a tag is not proof of source.
3. **CalVer release**: immutable published `YYYY.0M.0D[.MICRO]` tag, UTC.
4. **Qualification**: signed or otherwise authoritative record binding image ID, source pins, policy revision, tests and evidence digest. A tag alone confers no authority.
5. **Composition**: separately versioned, immutable manifest of four component releases and configuration/policy digests.
6. **Deployment**: immutable image IDs and composition qualification digest resolved at activation. Channel aliases must not be used for restart/recreation.

## Tag grammar

Local image namespace: `localhost/fatline/<component>`, component one of `redis`, `nginx`, `logma`, `skymill`.

- `:<calver>` — immutable published release, e.g. `:2026.10.21.1`
- `:candidate-<calver>` — immutable candidate revision, e.g. `:candidate-2026.10.21.2`
- `:qualified-<calver>` — immutable qualification marker, backed by matching record
- `:qualified` — mutable channel alias, informational/discovery only
- `:candidate` — optional mutable local development convenience, never deployment authority

No `:latest` in deployment. No moving or reusing a versioned tag, even following rollback or revocation. Promotion may move `:qualified` only after authority checks. Failed or revoked releases remain auditable. A qualification record can be revoked without deleting an image.

## Promotion protocol (Smoke owns enforcement)

1. Build via Nix-Alpine using pinned sources; import locally and inspect image ID.
2. Allocate a unique candidate CalVer in UTC (micro starts at 1 for additional same-day revisions). Do not overwrite an occupied versioned tag.
3. Bind source pins, Nix output, image ID, architecture, policy, tests and evidence in a candidate record.
4. Run component tests and full Redis–Nginx–Logma–Skymill integration gates. A 40 MiB noeviction Redis ACL test alone is not full composition qualification.
5. Publish immutable component version tags and qualification records only on success. Atomically advance channel mapping through a compare-and-swap authority transition; do not treat `podman tag` as atomic multi-component activation.
6. Publish and qualify a separate composition manifest that names exact component versions and immutable image IDs.
7. Before activating, re-resolve and verify every tag-to-ID mapping, source derivation and authorization; render Quadlets pinned to image IDs (or use explicit immutable version tags with mandatory preflight verification), `Pull=never`.
8. Activate with systemd --user. Record deployed IDs, qualification digest and rollback predecessor. Restart must not silently follow a mutable channel.
9. Roll back by activating a previously qualified composition, not by retagging its immutable versions.

## Repository responsibilities

- **Nix-Alpine**: builds, imports, and inspects images; does not grant qualification.
- **Agni**: declares desired composition, CalVer component references, Quadlet and network topology; does not hardcode host image IDs.
- **Smoke**: qualification checks, immutable publication checks, tag/ID resolution, activation and rollback evidence.
- **huram-abi-master**: canonical workflow and authority rules; existing idioms must be reconciled before Smoke enforcement is introduced.

## Current state

Agni's checked-in `2026.10.21` references are reserved placeholders, **not published or qualified**. The Nix images currently use local `:candidate` archive tags. Smoke promotion, CAS, composition qualification, and activation checks remain to be implemented and tested. Do not activate the placeholders as though they were qualified.
