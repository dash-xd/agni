{
  description = "Pinned Fedora CoreOS QEMU artifacts for Agni profiles";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/02c087f3fe673c9e317f206a627cb6b910336dbe";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      armSystem = "aarch64-linux";
      armPkgs = import nixpkgs { system = armSystem; };
      armRelease = "44.20261023.3.1";
      armCompressedQcow = armPkgs.fetchurl {
        url = "https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${armRelease}/aarch64/fedora-coreos-${armRelease}-qemu.aarch64.qcow2.xz";
        sha256 = "b239866503802feabc9cb4ce99e7d1eec18811dd44b9fd33af4a29f8f588978b";
      };
      armQcow = armPkgs.runCommand "fedora-coreos-${armRelease}-aarch64-qemu" {
        nativeBuildInputs = [ armPkgs.xz armPkgs.coreutils ];
      } ''
        mkdir -p "$out"
        xz --decompress --stdout "${armCompressedQcow}" > "$out/base.qcow2"
        echo "9e35faa475db9dede69a81fb212cb6b6fe5bd7d753c2bb27df53666a16e445e9  $out/base.qcow2" | sha256sum --check
      '';
      armTestSSHKey = builtins.getEnv "COREOS_TEST_SSH_PUBLIC_KEY";
      armValidSSHKey = builtins.match "^ssh-ed25519 [A-Za-z0-9+/=]+$" armTestSSHKey != null;
      armStarwispSource = builtins.path {
        path = builtins.toPath (builtins.getEnv "COREOS_STARWISP_BUTANE");
        name = "starwisp-profile.bu";
      };
      armStarwisp9pSource = builtins.path {
        path = builtins.toPath (builtins.getEnv "COREOS_STARWISP_9P_BUTANE");
        name = "starwisp-9p-profile.bu";
      };
      armWorld1Source = builtins.path {
        path = builtins.toPath (builtins.getEnv "COREOS_WORLD1_BUTANE");
        name = "shoal-world1-9p-profile.bu";
      };
      mkArmStarwispIgnition = name: source: assert armValidSSHKey; armPkgs.runCommand name {
        nativeBuildInputs = [ armPkgs.butane armPkgs.coreutils ];
        COREOS_TEST_SSH_PUBLIC_KEY = armTestSSHKey;
      } ''
        mkdir -p "$out"
        substitute ${source} "$TMPDIR/starwisp.bu" \
          --replace-fail "@COREOS_TEST_SSH_PUBLIC_KEY@" "$COREOS_TEST_SSH_PUBLIC_KEY"
        butane --strict --pretty "$TMPDIR/starwisp.bu" > "$out/config.ign"
      '';
      armStarwispIgnition = mkArmStarwispIgnition "starwisp-ignition-aarch64" armStarwispSource;
      armStarwisp9pIgnition = mkArmStarwispIgnition "starwisp-9p-ignition-aarch64" armStarwisp9pSource;
      armStarwispData9pIgnition = mkArmStarwispIgnition "starwisp-data-9p-ignition-aarch64" armStarwisp9pSource;
      armWorld1Ignition = mkArmStarwispIgnition "shoal-world1-9p-ignition-aarch64" armWorld1Source;
      armQemu = armPkgs.qemu.override { enableBlobs = true; };
      armEntrypoint = armPkgs.writeShellScriptBin "agni-coreos-qemu" ''
        set -euo pipefail
        case "''${1:-}" in
          img)
            shift
            exec ${armQemu}/bin/qemu-img "$@"
            ;;
          run|run-shared-nix)
            mode="$1"
            shift
            firmware=
            for candidate in ${armQemu}/share/qemu/edk2-aarch64-code.fd ${armQemu}/share/qemu/QEMU_EFI.fd; do
              if [ -f "$candidate" ]; then firmware="$candidate"; break; fi
            done
            if [ -z "$firmware" ]; then
              echo 'ARM64 QEMU UEFI firmware is missing from the OCI runner' >&2
              exit 1
            fi
            fs_args=()
            if [ "$mode" = run-shared-nix ]; then
              test -d /host-nix/store || {
                echo 'Missing read-only Nix store volume at /host-nix/store' >&2
                exit 1
              }
              fs_args=(
                -fsdev local,id=nixstore,path=/host-nix/store,security_model=none,readonly=on
                -device virtio-9p-pci,fsdev=nixstore,mount_tag=nixstore
              )
            fi
            exec ${armQemu}/bin/qemu-system-aarch64 -L ${armQemu}/share/qemu \
              -bios "$firmware" "''${fs_args[@]}" "$@"
            ;;
          *)
            echo "Usage: agni-coreos-qemu img|run|run-shared-nix [arguments...]" >&2
            exit 2
            ;;
        esac
      '';
      armRunner = armPkgs.dockerTools.buildLayeredImage {
        name = "localhost/agni-coreos-qemu-runner";
        tag = "${armRelease}-aarch64";
        created = "1970-01-01T00:00:01Z";
        contents = [ armEntrypoint armQemu ];
        config.Entrypoint = [ "${armEntrypoint}/bin/agni-coreos-qemu" ];
      };
      pkgs = import nixpkgs { inherit system; };
      release = "44.20261012.3.1";
      astrochickenInputs = pkgs.writeShellApplication {
        name = "agni-astrochicken-inputs";
        runtimeInputs = with pkgs; [ bash coreutils findutils gawk git gzip gnugrep ];
        text = builtins.readFile ../profiles/astrochicken/prepare-inputs.sh;
      };
      configDir = builtins.path {
        path = builtins.toPath (builtins.getEnv "COREOS_CONFIG_DIR");
        name = "coreos-profile-config";
      };
      configNameEnv = builtins.getEnv "COREOS_CONFIG_NAME";
      configName = if configNameEnv == "" then "profile.bu" else configNameEnv;
      testSSHKey = builtins.getEnv "COREOS_TEST_SSH_PUBLIC_KEY";
      validTestSSHKey = builtins.match "^ssh-ed25519 [A-Za-z0-9+/=]+$" testSSHKey != null;
      resourcesDir = builtins.path {
        path = builtins.toPath (builtins.getEnv "COREOS_RESOURCES_DIR");
        name = "coreos-profile-resources";
      };
      compositionNameEnv = builtins.getEnv "COREOS_COMPOSITION_NAME";
      compositionName = if compositionNameEnv == "" then "guest" else compositionNameEnv;
      validCompositionName = builtins.match "^[a-z_][a-z0-9_-]{0,18}$" compositionName != null;
      python3Qemu = pkgs.python3.override {
        packageOverrides = pyFinal: pyPrev: {
          websockify = pyPrev.websockify.overridePythonAttrs (old: {
            # These fixtures use short HMAC keys that newer jwcrypto correctly rejects.
            disabledTests = (old.disabledTests or [ ]) ++ [
              "test_symmetric_jws_token_plugin"
              "test_symmetric_jws_token_plugin_with_illigal_key_exception"
            ];
          });
        };
      };
      websockify = python3Qemu.pkgs.websockify;
      novnc = pkgs.novnc.override { python3 = python3Qemu; };
      compressedQcow = pkgs.fetchurl {
        url = "https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/44.20261012.3.1/x86_64/fedora-coreos-44.20261012.3.1-qemu.x86_64.qcow2.xz";
        sha256 = "e416c392f0c7963584516881c3cd3fac096bbe4f208ca6290ba7616c77383395";
      };
      qcow = pkgs.runCommand "fedora-coreos-${release}-x86_64-qemu" {
        nativeBuildInputs = [ pkgs.xz pkgs.coreutils ];
      } ''
        mkdir -p "$out"
        xz --decompress --stdout "${compressedQcow}" > "$out/base.qcow2"
        echo "efe134f167e22b3e21d8c3cb643e59e814286202d2f0350b080eebbc23bc31d8  $out/base.qcow2" | sha256sum --check
      '';
      ignition = assert validCompositionName;
        assert builtins.match "^[A-Za-z0-9][A-Za-z0-9._-]*\\.bu$" configName != null;
        pkgs.runCommand "coreos-profile-ignition" {
        nativeBuildInputs = [ pkgs.butane ];
        COREOS_TEST_SSH_PUBLIC_KEY = testSSHKey;
      } ''
        config="${configDir}/${configName}"
        if [ ! -f "$config" ]; then
          echo "Missing Butane configuration input: $config" >&2
          exit 1
        fi
        if [ ! -d "${resourcesDir}" ]; then
          echo "Missing Butane resource directory: ${resourcesDir}" >&2
          exit 1
        fi
        mkdir -p "$out"
        config_to_use="$config"
        if [ -n "$COREOS_TEST_SSH_PUBLIC_KEY" ]; then
          if ! ${if validTestSSHKey then "true" else "false"}; then
            echo "COREOS_TEST_SSH_PUBLIC_KEY must be an ssh-ed25519 public key without a comment" >&2
            exit 1
          fi
          config_to_use="$TMPDIR/profile-transient.bu"
          substitute "$config" "$config_to_use" \
            --replace-fail '@COREOS_TEST_SSH_PUBLIC_KEY@' "$COREOS_TEST_SSH_PUBLIC_KEY"
        elif grep -q '@COREOS_TEST_SSH_PUBLIC_KEY@' "$config"; then
          echo "The transient Butane profile requires a test SSH key" >&2
          exit 1
        fi
        generated_resources="$TMPDIR/coreos-profile-resources"
        mkdir -p "$generated_resources"
        cp -R "${resourcesDir}/." "$generated_resources/"
        mkdir -p "$generated_resources/config"
        printf '%s\n' "${compositionName}" > "$generated_resources/config/composition-name"
        echo "Transpiling $config for composition ${compositionName} with workspace resources under ${resourcesDir}"
        butane --strict --pretty \
          --files-dir "$generated_resources" \
          "$config_to_use" > "$out/config.ign" || {
            rc=$?
            echo "Butane transpilation failed (exit $rc)" >&2
            exit "$rc"
          }
      '';
      qemu = pkgs.qemu_kvm.override {
        alsaSupport = false;
        pulseSupport = false;
        pipewireSupport = false;
        sdlSupport = false;
        gtkSupport = false;
        jackSupport = false;
        # Optional browser console uses QEMU's VNC server behind pinned noVNC.
        vncSupport = true;
        smartcardSupport = false;
        spiceSupport = false;
        usbredirSupport = false;
        openGLSupport = false;
        virglSupport = false;
        libiscsiSupport = false;
        tpmSupport = false;
        fuseSupport = false;
        canokeySupport = false;
        u2fEmuSupport = false;
        brlttySupport = false;
        pluginsSupport = false;
        enableDocs = false;
        enableBlobs = true;
      };
      qemuEntrypoint = pkgs.writeShellScriptBin "agni-coreos-qemu" ''
        set -euo pipefail
        case ''${1:-} in
          img)
            shift
            exec ${qemu}/bin/qemu-img "$@"
            ;;
          run)
            shift
            exec ${qemu}/bin/qemu-system-x86_64 -L ${qemu}/share/qemu "$@"
            ;;
          run-web)
            shift
            ${qemu}/bin/qemu-system-x86_64 -L ${qemu}/share/qemu "$@" -vnc 127.0.0.1:0 &
            qemu_pid=$!
            ${websockify}/bin/websockify \
              --web ${novnc}/share/webapps/novnc \
              0.0.0.0:6080 127.0.0.1:5900 &
            web_pid=$!
            cleanup() {
              kill "$qemu_pid" "$web_pid" 2>/dev/null || true
              wait "$qemu_pid" "$web_pid" 2>/dev/null || true
            }
            trap cleanup EXIT
            trap 'exit 143' INT TERM
            set +e
            wait -n "$qemu_pid" "$web_pid"
            rc=$?
            set -e
            exit "$rc"
            ;;
          *)
            echo "Usage: agni-coreos-qemu img|run|run-web [arguments...]" >&2
            exit 2
            ;;
        esac
      '';
      qemuRunner = pkgs.dockerTools.buildLayeredImage {
        name = "localhost/agni-coreos-qemu-runner";
        tag = release;
        created = "1970-01-01T00:00:01Z";
        contents = [ qemuEntrypoint qemu novnc websockify ];
        config = {
          Entrypoint = [ "${qemuEntrypoint}/bin/agni-coreos-qemu" ];
        };
      };
      bootstrap = pkgs.runCommand "agni-coreos-qemu-bootstrap-${release}" { } ''
        mkdir -p "$out"
        cp "${qcow}/base.qcow2" "$out/base.qcow2"
        cp "${ignition}/config.ign" "$out/config.ign"
        echo '${release}' > "$out/fcos-release"
      '';
    in {
      packages.${armSystem} = {
        qemuRunner = armRunner;
        qcow = armQcow;
        ignitionStarwisp = armStarwispIgnition;
        ignitionStarwisp9p = armStarwisp9pIgnition;
        ignitionStarwispData9p = armStarwispData9pIgnition;
        ignitionShoalWorld1_9p = armWorld1Ignition;
      };
      apps.${system}.astrochicken-inputs = {
        type = "app";
        program = "${astrochickenInputs}/bin/agni-astrochicken-inputs";
      };
      packages.${system} = {
        inherit qcow ignition bootstrap qemuRunner;
        default = bootstrap;
      };
    };
}
