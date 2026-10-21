{
  description = "Agni local Fatline composition executed inside Nix-Alpine";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in {
      devShells = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; };
        in { default = pkgs.mkShell { packages = with pkgs; [ go_1_26 git ]; }; });
      apps = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          runner = pkgs.writeShellApplication {
            name = "agni-fatline";
            runtimeInputs = with pkgs; [ bash coreutils findutils git gnumake go_1_26 stdenv.cc redis gnugrep gnused ];
            text = ''
              exec bash ${./scripts/fatline.sh} "$@"
            '';
          };
          app = command: {
            type = "app";
            program = "${pkgs.writeShellScript "agni-fatline-${command}" ''
              exec ${runner}/bin/agni-fatline ${command} "$@"
            ''}";
          };
        in {
          bootstrap = app "bootstrap";
          preflight = app "preflight";
          build = app "build";
          qualify = app "qualify";
          test = app "test";
          test-workspace = app "test-workspace";
          qualify-integration = app "qualify-integration";
          check-quadlets = {
            type = "app";
            program = "${pkgs.writeShellScript "agni-check-quadlets" ''
              export FATLINE_QUADLET_DIR=${./systemd}
              exec ${pkgs.bash}/bin/bash ${./scripts/check-quadlets.sh}
            ''}";
          };
          advance-pin = app "advance-pin";
          default = app "preflight";
        });
    };
}
