{
  description = "Unified Fedora CoreOS + QEMU environment flake, modular & reproducible";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # -------------------------------
        # Version metadata
        # -------------------------------
        versions = {
          v42 = {
            url = "https://builds.coreos.fedoraproject.org/streams/stable.json";
            sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          };
        };
        currentMeta = versions.v42;

        # -------------------------------
        # CoreOS ISO derivation
        # -------------------------------
        coreosIso = let
          stableJson = pkgs.builtins.fetchurl {
            url = currentMeta.url;
            sha256 = currentMeta.sha256;
          };
          parsed = builtins.fromJSON stableJson;
          isoMeta = parsed.architectures.x86_64.images.iso;
        in pkgs.stdenv.mkDerivation {
          pname = "coreos-${isoMeta.version}";
          version = isoMeta.version;

          src = pkgs.fetchurl {
            url = isoMeta.location;
            sha256 = isoMeta.sha256;
          };

          buildCommand = ''
            mkdir -p $out
            cp $src $out/${pname}.iso
          '';
        };

        # -------------------------------
        # SHA update helper
        # -------------------------------
        updateCoreOS = pkgs.stdenv.mkDerivation {
          pname = "update-coreos-version";
          version = "0.1";

          buildCommand = let
            url = "https://builds.coreos.fedoraproject.org/streams/stable.json";
            fetched = pkgs.fetchurl { url = url; sha256 = "0000000000000000000000000000000000000000000000000000"; };
            sha = builtins.hashString "sha256" (builtins.readFile fetched);
          in ''
            mkdir -p $out
            echo "{ url = \"${url}\"; sha256 = \"${sha}\"; }" > $out/new-version.nix
            echo "✅ New version metadata written to $out/new-version.nix"
          '';
        
        # -------------------------------
        # Default QEMU environment configuration
        # -------------------------------
        defaultEnv = {
          CONTAINER_NAME = "coreos-default";
          RAM_SIZE = "4G";
          CPU_CORES = "2";
          DISK_SIZE = "0G";
          PORT_SSH = "2222";
          PORT_UI = "8006";
          ISO_PATH = "./iso/coreos-live.iso";
          SHARE_DIR = "./shared/";
          ARGUMENTS = "-enable-kvm -boot d -nic user,model=virtio-net-pci,hostfwd=tcp::22-:22";
          RESTART_POLICY = "always";
          STOP_GRACE_PERIOD = "2m";
        };

        envFile = pkgs.writeText "default.env"
          (builtins.concatStringsSep "\n"
            (map (k: "${k}=${defaultEnv.${k}}") (builtins.attrNames defaultEnv)));

        # -------------------------------
        # Butane → Ignition renderer derivation
        # -------------------------------
        ignitions = pkgs.stdenv.mkDerivation {
          pname = "butane-ignitions";
          buildInputs = [ pkgs.butane ];
          src = ./butane;
          buildCommand = ''
            mkdir -p $out
            for f in $src/*.{bu,yaml}; do
              [ -f "$f" ] || continue
              name="$(basename "$f")"
              name="${name%.*}"
              echo "Rendering $f → $out/$name.ign"
              butane --strict "$f" > "$out/$name.ign"
            done
          '';
        };

        # -------------------------------
        # CoreOS custom ISO derivation
        # -------------------------------
        fcosCustomIso = pkgs.stdenv.mkDerivation {
          pname = "fcos-custom-iso";
          buildInputs = [ pkgs.podman ];
          # depend on the built coreos ISO and ignitions
          nativeBuildInputs = [];
          buildCommand = ''
            mkdir -p $out
            echo "Building custom Fedora CoreOS ISO..."
            podman run --security-opt label=disable --pull=always --rm \
              -v $PWD:/data -w /data \
              quay.io/coreos/coreos-installer:release iso customize \
              --live-karg-append=coreos.liveiso.fromram \
              --live-ignition=${ignitions}/*.ign \
              -o ${defaultEnv.ISO_PATH} ${coreosIso}/$(basename ${coreosIso})
            echo "✅ Custom ISO created: ${defaultEnv.ISO_PATH}"
          '';
        };
      in
      {
        packages.${system}.coreosIso = coreosIso;
        packages.${system}.updateCoreOS = updateCoreOS;
        packages.${system}.ignitions = ignitions;
        packages.${system}.fcosCustomIso = fcosCustomIso;

        defaultPackage.${system} = coreosIso;

        # -------------------------------
        # Expose QEMU Compose apps
        # -------------------------------
        apps.${system} = {
          qemuCompose = {
            type = "app";
            program = pkgs.writeShellScript "qemu-compose" ''
              set -e
              ENV_FILE="${1:-${envFile}}"
              echo "📦 Using environment file: $ENV_FILE"
              podman compose --env-file "$ENV_FILE" up
            '';
          };

          qemuComposeDown = {
            type = "app";
            program = pkgs.writeShellScript "qemu-compose-down" ''
              set -e
              ENV_FILE="${1:-${envFile}}"
              echo "🧹 Stopping QEMU CoreOS containers..."
              podman compose --env-file "$ENV_FILE" down
            '';
          };

          default = {
            type = "app";
            program = pkgs.writeShellScript "build-coreos-env" ''
              set -e
              echo "🚀 Building Ignition files..."
              nix build .#ignitions
              echo "🔥 Creating CoreOS ISO..."
              nix build .#fcosCustomIso
              echo "🧩 Launching Podman Compose..."
              nix run .#apps.${system}.qemuCompose
            '';
          };
        };

        devShell.${system} = pkgs.mkShell {
          buildInputs = [ coreosIso ];
        };
      });
}
