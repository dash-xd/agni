{
  description = "Agni local Fatline composition executed inside Nix-Alpine";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in {
      # Build-only provider artifacts from the owning repositories. Their revisions
      # must be recorded as flake.lock inputs before deployment authority exists.
      # This build does not install Quadlets or start Redis.
      devShells = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; };
        in { default = pkgs.mkShell { packages = with pkgs; [ go_1_26 git ]; }; });
      packages = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; };
        in {
          # Redis-only archive. Runtime configuration and ACLs are supplied by Agni Quadlets.
          redis-image = pkgs.dockerTools.buildLayeredImage {
            name = "localhost/fatline-redis";
            tag = "candidate";
            contents = [ pkgs.redis ];
            config = {
              Entrypoint = [ "${pkgs.redis}/bin/redis-server" ];
              Cmd = [ "/etc/redis/redis.conf" ];
            };
          };
          fatline = import ./composition.nix {
            inherit pkgs;
            lib = pkgs.lib;
            config = import ./composition-config.nix;
          };
          default = self.packages.${system}.fatline;
        });
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
          advance-pin = app "advance-pin";
          default = app "preflight";
        });
    };
}
