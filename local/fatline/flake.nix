{
  description = "Agni local Fatline composition executed inside Nix-Alpine";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in {
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
          qualify-integration = app "qualify-integration";
          advance-pin = app "advance-pin";
          default = app "preflight";
        });
    };
}
