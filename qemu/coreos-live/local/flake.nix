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
      resourcesDir = builtins.path {
        path = builtins.toPath (builtins.getEnv "COREOS_RESOURCES_DIR");
        name = "fatline-coreos-resources";
      };
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
      ignition = pkgs.runCommand "fatline-coreos-bootstrap-ignition" {
        nativeBuildInputs = [ pkgs.butane ];
      } ''
        config="${configDir}/fatline-bootstrap.bu"
        if [ ! -f "$config" ]; then
          echo "Missing Butane configuration input: $config" >&2
          exit 1
        fi
        if [ ! -d "${resourcesDir}" ]; then
          echo "Missing Butane resource directory: ${resourcesDir}" >&2
          exit 1
        fi
        mkdir -p "$out"
        echo "Transpiling $config with workspace resources under ${resourcesDir}"
        butane --strict --pretty \
          --files-dir "${resourcesDir}" \
          "$config" > "$out/config.ign" || {
            rc=$?
            echo "Butane transpilation failed (exit $rc)" >&2
            exit "$rc"
          }
      '';
      qemuEntrypoint = pkgs.writeShellScriptBin "fatline-qemu" ''
        set -euo pipefail
        case "${1:-}" in
          img)
            shift
            exec ${pkgs.qemu}/bin/qemu-img "$@"
            ;;
          run)
            shift
            exec ${pkgs.qemu}/bin/qemu-system-x86_64 "$@"
            ;;
          *)
            echo "Usage: fatline-qemu img|run [arguments...]" >&2
            exit 2
            ;;
        esac
      '';
      qemuRunner = pkgs.dockerTools.buildLayeredImage {
        name = "localhost/fatline-qemu-runner";
        tag = release;
        created = "1970-01-01T00:00:01Z";
        contents = [ qemuEntrypoint pkgs.qemu ];
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
