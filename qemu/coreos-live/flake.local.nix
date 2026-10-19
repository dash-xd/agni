{
  description = "Agni local Fedora CoreOS QEMU runner";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      each = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in {
      apps = each (pkgs: {
        default = {
          type = "app";
          program = "${pkgs.writeShellApplication {
            name = "agni-coreos-local";
            runtimeInputs = [ pkgs.qemu pkgs.coreutils pkgs.systemd pkgs.gnugrep pkgs.gnused ];
            text = builtins.readFile ./deploy-local.sh;
          }}/bin/agni-coreos-local";
        };
      });
    };
}
