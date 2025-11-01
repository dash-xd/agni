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

        # Default environment for QEMU container
        defaultEnv = {
          BOOT = "nixos";
          RAM_SIZE = "4G";
          CPU_CORES = "2";
          DISK_SIZE = "64G";
          ARGUMENTS = "-enable-kvm -boot d -nic user,model=virtio-net-pci,hostfwd=tcp::22-:22";
          RESTART_POLICY = "always";
          STOP_GRACE_PERIOD = "2m";
        };

        # Compose template built dynamically from args
        dockerComposeTemplate = pkgs.writeText "docker-compose.yml" ''
          version: "3.9"
          services:
            qemu:
              image: docker.io/qemux/qemu:latest
              container_name: ${defaultEnv.BOOT}-coreos
              privileged: true
              environment:
                BOOT: "${defaultEnv.BOOT}"
                RAM_SIZE: "${defaultEnv.RAM_SIZE}"
                CPU_CORES: "${defaultEnv.CPU_CORES}"
                DISK_SIZE: "${defaultEnv.DISK_SIZE}"
                ARGUMENTS: "${defaultEnv.ARGUMENTS}"
              devices:
                - /dev/kvm
                - /dev/net/tun
              cap_add:
                - NET_ADMIN
              ports:
                - "8006:8006"
                - "2222:22"
              volumes:
                - ./iso/ignited.iso:/boot.iso:ro
                - ./shared:/storage/hostshare
              restart: ${defaultEnv.RESTART_POLICY}
              stop_grace_period: ${defaultEnv.STOP_GRACE_PERIOD}
        '';

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
              -o ./iso/ignited.iso fedora-coreos-42.20250914.3.0-live-iso.x86_64.iso
            echo "✅ Custom ISO created: ./iso/ignited.iso"
          '';
        };

        # -------------------------------------------------------------------
        # Step 3. QEMU Docker Compose generator
        # -------------------------------------------------------------------
        packages.qemu-compose = pkgs.writeShellApplication {
          name = "qemu-compose";
          runtimeInputs = [ pkgs.envsubst ];
          text = ''
            set -e
            echo "Generating docker-compose.yml with QEMU CoreOS defaults..."
            cp ${dockerComposeTemplate} ./docker-compose.yml
            echo "✅ docker-compose.yml created with defaults:"
            echo "   BOOT=${defaultEnv.BOOT}"
            echo "   RAM_SIZE=${defaultEnv.RAM_SIZE}"
            echo "   CPU_CORES=${defaultEnv.CPU_CORES}"
          '';
        };

        # -------------------------------------------------------------------
        # Step 4. Unified builder app (Butane → ISO → Compose)
        # -------------------------------------------------------------------
        apps.${system}.default = {
          type = "app";
          program = "${pkgs.writeShellScript "build-coreos-env" ''
            set -e
            echo "🚀 Building all Butane → Ignition files..."
            nix build .#ignitions
            echo "🔥 Creating final CoreOS ISO..."
            nix run .#fcos-custom-iso
            echo "🧩 Generating docker-compose.yml..."
            nix run .#qemu-compose
            echo "✅ All artifacts ready:"
            echo "   - Ignitions: ./result/*.ign"
            echo "   - ISO: ./iso/ignited.iso"
            echo "   - Compose: ./docker-compose.yml"
          ''}";
        };
      });
}
