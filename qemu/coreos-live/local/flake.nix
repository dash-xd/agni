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
        printf '%s  %s\\n' "efe134f167e22b3e21d8c3cb643e59e814286202d2f0350b080eebbc23bc31d8" "$out/base.qcow2" | sha256sum --check
      '';
      ignition = pkgs.runCommand "fatline-coreos-bootstrap-ignition" {
        nativeBuildInputs = [ pkgs.butane ];
      } ''
        test -f "${configDir}/fatline-bootstrap.bu"
        test -d "${resourcesDir}"
        mkdir -p "$out"
        butane --strict --pretty \
          --files-dir "${resourcesDir}" \
          "${configDir}/fatline-bootstrap.bu" > "$out/config.ign"
      '';
      bootstrap = pkgs.runCommand "fatline-coreos-qemu-bootstrap-${release}" { } ''
        mkdir -p "$out"
        cp "${qcow}/base.qcow2" "$out/base.qcow2"
        cp "${ignition}/config.ign" "$out/config.ign"
        printf '%s\\n' '${release}' > "$out/fcos-release"
      '';
    in {
      packages.${system} = {
        inherit qcow ignition bootstrap;
        default = bootstrap;
      };
    };
}
