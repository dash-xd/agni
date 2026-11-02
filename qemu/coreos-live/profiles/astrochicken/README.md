# Astrochicken CoreOS profile

Agni owns this base-case profile: its Butane document, guest services,
rootless toolbox Quadlets, qualification checks, and plan metadata all live
here. `prepare-inputs.sh` embeds the pinned Nix-Alpine source and any explicitly
selected workspace files into the profile's Ignition resources.

Nix-Alpine's generic `qualify-coreos-profile` Make target reads
`qualification.json`, runs the profile preparation app inside the toolbox,
and supervises the generic host QEMU/systemd adapter. The profile does not
install host units or require the optional SSH transient tester.

The guest smoke checks that the generated application account starts the
rootless Nix-Alpine toolbox as a systemd user service, can evaluate a flake,
and shares the persistent Nix store with a second rootless container. The
optional local console account is read-only outside its own workspace.

Workspace files may be added explicitly with
`COREOS_PROFILE_WORKSPACE_FILES="path/under/workspaces"`.
