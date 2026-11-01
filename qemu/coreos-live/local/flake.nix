{
  description = "Pinned Fedora CoreOS QEMU bootstrap artifacts for Fatline";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/02c087f3fe673c9e317f206a627cb6b910336dbe";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      release = "44.20261012.3.1";
      configDir = builtins.path {
        path = builtins.toPath (builtins.getEnv "COREOS_CONFIG_DIR");
        name = "fatline-coreos-config";
      };
      configNameEnv = builtins.getEnv "COREOS_CONFIG_NAME";
      configName = if configNameEnv == "" then "fatline-bootstrap.bu" else configNameEnv;
      testSSHKey = builtins.getEnv "COREOS_TEST_SSH_PUBLIC_KEY";
      validTestSSHKey = builtins.match "^ssh-ed25519 [A-Za-z0-9+/=]+$" testSSHKey != null;
      resourcesDir = builtins.path {
        path = builtins.toPath (builtins.getEnv "COREOS_RESOURCES_DIR");
        name = "fatline-coreos-resources";
      };
      compositionNameEnv = builtins.getEnv "COREOS_COMPOSITION_NAME";
      compositionName = if compositionNameEnv == "" then "fatline" else compositionNameEnv;
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
        pkgs.runCommand "fatline-coreos-bootstrap-ignition" {
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
          config_to_use="$TMPDIR/fatline-bootstrap-transient.bu"
          substitute "$config" "$config_to_use" \
            --replace-fail '@COREOS_TEST_SSH_PUBLIC_KEY@' "$COREOS_TEST_SSH_PUBLIC_KEY"
        elif grep -q '@COREOS_TEST_SSH_PUBLIC_KEY@' "$config"; then
          echo "The transient Butane profile requires a test SSH key" >&2
          exit 1
        fi
        generated_resources="$TMPDIR/fatline-coreos-resources"
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
      qemuEntrypoint = pkgs.writeShellScriptBin "fatline-qemu" ''
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
            echo "Usage: fatline-qemu img|run|run-web [arguments...]" >&2
            exit 2
            ;;
        esac
      '';
      qemuRunner = pkgs.dockerTools.buildLayeredImage {
        name = "localhost/fatline-qemu-runner";
        tag = release;
        created = "1970-01-01T00:00:01Z";
        contents = [ qemuEntrypoint qemu novnc websockify ];
        config = {
          Entrypoint = [ "${qemuEntrypoint}/bin/fatline-qemu" ];
        };
      };
      bootstrap = pkgs.runCommand "fatline-coreos-qemu-bootstrap-${release}" { } ''
        mkdir -p "$out"
        cp "${qcow}/base.qcow2" "$out/base.qcow2"
        cp "${ignition}/config.ign" "$out/config.ign"
        echo '${release}' > "$out/fcos-release"
      '';
    in {
      packages.${system} = {
        inherit qcow ignition bootstrap qemuRunner;
        default = bootstrap;
      };
    };
}
