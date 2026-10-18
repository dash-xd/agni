{
  description = "Agni local Fedora CoreOS world builder";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      ignition = pkgs.runCommand "agni-local-ignition" { nativeBuildInputs = [ pkgs.butane ]; } ''
        mkdir -p "$out"
        butane --strict ${./butane/local-world.bu} > "$out/config.ign"
      '';
      updater = pkgs.writeShellApplication {
        name = "agni-update-coreos";
        runtimeInputs = [ pkgs.curl pkgs.jq ];
        text = ''
          set -euo pipefail
          output="\${1:-coreos-stable.lock.json}"
          curl -fsSL https://builds.coreos.fedoraproject.org/streams/stable.json |
            jq -e '{release:.architectures.x86_64.artifacts.qemu.release,qemu:.architectures.x86_64.artifacts.qemu.formats."qcow2.xz".disk,iso:.architectures.x86_64.artifacts.live.formats.iso.disk} | select(.release and .qemu.location and .qemu.sha256 and .iso.location and .iso.sha256)' > "$output"
        '';
      };
    in {
      packages.${system}.default = ignition;
      packages.${system}.ignition = ignition;
      apps.${system}.update-coreos = {
        type = "app";
        program = "${updater}/bin/agni-update-coreos";
      };
    };
}
