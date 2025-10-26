{
  description = "Dynamic Fedora CoreOS ISO builder for CoreOS self-replication";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Try to load the local lockfile, fallback to null
        fcosLock =
          let lockPath = ./fcos-lock.json;
          in if builtins.pathExists lockPath
             then builtins.fromJSON (builtins.readFile lockPath)
             else null;

        fcosFetcher = import ./fcos-fetch.nix { inherit pkgs; };

        # FCOS ISO derivation (auto-fetched or pinned)
        fcosIso = fcosFetcher {
          version = fcosLock.version or "latest";
          stream = "stable";
          arch = "x86_64";
          lockFile = ./fcos-lock.json;
          useLock = fcosLock != null;
        };

      in {
        packages = {
          fcos-iso = fcosIso;

          fcos-butane = pkgs.writeShellApplication {
            name = "fcos-butane";
            runtimeInputs = [ pkgs.podman ];
            text = ''
              podman run --rm -i -v "$PWD":/pwd:Z -w /pwd quay.io/coreos/butane:release \
                --pretty --strict ./butane.yaml -o config.ign
            '';
          };

          fcos-custom-iso = pkgs.writeShellApplication {
            name = "fcos-custom-iso";
            runtimeInputs = [ pkgs.podman fcosIso ];
            text = ''
              podman run --security-opt label=disable --rm \
                -v .:/data -w /data \
                quay.io/coreos/coreos-installer:release iso customize \
                --live-karg-append=coreos.liveiso.fromram \
                --live-ignition=./config.ign \
                -o customized.iso ${fcosIso}
            '';
          };
        };

        # Nix-native updater
        apps.update = flake-utils.lib.mkApp {
          drv = pkgs.writeShellApplication {
            name = "update-fcos";
            runtimeInputs = [ pkgs.curl pkgs.jq pkgs.gnupg pkgs.nix ];
            text = ''
              nix eval .#packages.${system}.fcos-iso > /dev/null
            '';
          };
        };
      });
}
