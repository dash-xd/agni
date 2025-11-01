{
  description = "Fedora CoreOS builder + QEMU runtime environment with Butane ignition generation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        BASE_ISO = "./iso/fedora-coreos-42.20250914.3.0-live-iso.x86_64.iso";

        defaultEnv = {
          CONTAINER_NAME = "coreos-default";
          RAM_SIZE = "4G";
          CPU_CORES = "2";
          DISK_SIZE = "0G";
          PORT_SSH = "2222";
          PORT_UI = "8006";
          ISO_PATH = "./iso/lit.iso";
          SHARE_DIR = "./shared/";
          ARGUMENTS = "-enable-kvm -boot d -nic user,model=virtio-net-pci,hostfwd=tcp::22-:22";
          RESTART_POLICY = "always";
          STOP_GRACE_PERIOD = "2m";
        };

        envFile = pkgs.writeText "default.env"
          (builtins.concatStringsSep "\n"
            (map (k: "${k}=${defaultEnv.${k}}") (builtins.attrNames defaultEnv)));
      in {
        # -------------------------------------------------------------------
        # Step 1. Butane → Ignition renderer
        # -------------------------------------------------------------------
        packages.ignitions = pkgs.runCommand "butane-ignitions" {
          src = ./butane;
          nativeBuildInputs = [ pkgs.butane ];
        } ''
          mkdir -p $out
          for f in $src/*.{bu,yaml}; do
            [ -f "$f" ] || continue
            name="$(basename "$f")"
            name="${name%.*}"
            echo "Rendering $f → $out/$name.ign"
            butane --strict "$f" > "$out/$name.ign"
          done
        '';

        # -------------------------------------------------------------------
        # Step 2. CoreOS ISO Customizer
        # -------------------------------------------------------------------
        packages.fcos-custom-iso = pkgs.writeShellApplication {
          name = "fcos-custom-iso";
          runtimeInputs = [ pkgs.podman ];
          text = ''
            set -e
            mkdir -p iso
            echo "Building custom Fedora CoreOS ISO..."
            podman run --security-opt label=disable --pull=always --rm \
              -v .:/data -w /data \
              quay.io/coreos/coreos-installer:release iso customize \
              --live-karg-append=coreos.liveiso.fromram \
              --live-ignition=./config.ign \
              -o ${defaultEnv.ISO_PATH} ${BASE_ISO}
            echo "✅ Custom ISO created: ${defaultEnv.ISO_PATH}"
          '';
        };

        # -------------------------------------------------------------------
        # Step 3. Podman Compose launcher
        # -------------------------------------------------------------------
        packages.qemu-compose = pkgs.writeShellApplication {
          name = "qemu-compose";
          runtimeInputs = [ pkgs.podman ];
          text = ''
            set -e
            ENV_FILE="${1:-${envFile}}"
            echo "📦 Using environment file: $ENV_FILE"
            podman compose --env-file "$ENV_FILE" up
          '';
        };

        # Optional: convenience stop command
        packages.qemu-compose-down = pkgs.writeShellApplication {
          name = "qemu-compose-down";
          runtimeInputs = [ pkgs.podman ];
          text = ''
            set -e
            ENV_FILE="${1:-${envFile}}"
            echo "🧹 Stopping QEMU CoreOS containers..."
            podman compose --env-file "$ENV_FILE" down
          '';
        };

        # -------------------------------------------------------------------
        # Step 4. Unified builder app (Butane → ISO → Compose)
        # -------------------------------------------------------------------
        apps.${system}.default = {
          type = "app";
          program = "${pkgs.writeShellScript "build-coreos-env" ''
            set -e
            echo "🚀 Building Ignition files..."
            nix build .#ignitions
            echo "🔥 Creating CoreOS ISO..."
            nix run .#fcos-custom-iso
            echo "🧩 Launching Podman Compose..."
            nix run .#qemu-compose
          ''}";
        };
      });
}
