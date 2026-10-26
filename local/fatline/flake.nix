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
          # Redis artifacts are produced and qualified by Nix-Alpine.
          # Agni consumes only the release-ledger-selected image reference.
          nginx-image = pkgs.dockerTools.buildLayeredImage {
            name = "localhost/fatline-nginx";
            tag = "candidate";
            contents = [ pkgs.nginx ];
            extraCommands = ''
              mkdir -p etc
              printf 'root:x:0:0:root:/root:/bin/sh\nnobody:x:65534:65534:nobody:/:/sbin/nologin\n' > etc/passwd
              printf 'root:x:0:\nnogroup:x:65534:\n' > etc/group
            '';
            config = {
              Entrypoint = [ "${pkgs.nginx}/bin/nginx" ];
              Cmd = [ "-g" "daemon off;" "-c" "/etc/nginx/nginx.conf" ];
            };
          };
          nginx-qualification = pkgs.runCommand "fatline-nginx-qualification-template" { } ''
            mkdir -p "$out/quadlets" "$out/config"
            cat > "$out/quadlets/fatline-qualify-nginx.container" <<'EOF'
            [Unit]
            Description=Disposable Fatline Nginx candidate qualification
            [Container]
            Image=__CANDIDATE_IMAGE_ID__
            Pull=never
            ContainerName=fatline-qualify-nginx
            Network=none
            ReadOnly=true
            User=65534:65534
            Volume=%h/.config/fatline-qualify/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
            Tmpfs=/tmp:rw,noexec,nosuid,size=4m
            Exec=-g "daemon off;" -c /etc/nginx/nginx.conf
            NoNewPrivileges=true
            DropCapability=all
            [Service]
            Restart=no
            EOF
            cat > "$out/config/nginx.conf" <<'EOF'
            worker_processes 1;
            pid /tmp/nginx.pid;
            error_log /dev/stderr warn;
            events { worker_connections 128; }
            http {
              access_log off;
              server {
                listen 127.0.0.1:8080;
                location /health { return 200 "ok"; }
              }
            }
            EOF
            grep -qx 'Network=none' "$out/quadlets/fatline-qualify-nginx.container"
            grep -qx 'Image=__CANDIDATE_IMAGE_ID__' "$out/quadlets/fatline-qualify-nginx.container"
          '';
          # Build-only template. Smoke substitutes the inspected immutable image ID
          # into its disposable scope; no candidate can enter production composition.
          redis-qualification = pkgs.runCommand "fatline-redis-qualification-template" { } ''
            mkdir -p "$out/quadlets" "$out/config"
            cat > "$out/quadlets/fatline-qualify-redis.container" <<'EOF'
            [Unit]
            Description=Disposable Fatline Redis candidate qualification
            ConditionPathExists=%h/.config/fatline-qualify/redis/users.acl

            [Container]
            Image=__CANDIDATE_IMAGE_ID__
            Pull=never
            ContainerName=fatline-qualify-redis
            Network=none
            ReadOnly=true
            Volume=%h/.config/fatline-qualify/redis/redis.conf:/etc/redis/redis.conf:ro
            Volume=%h/.config/fatline-qualify/redis/users.acl:/etc/redis/users.acl:ro
            Volume=%t/fatline-qualify/redis:/run/redis
            Exec=/etc/redis/redis.conf
            NoNewPrivileges=true
            DropCapability=all

            [Service]
            ExecStartPre=/usr/bin/install -d -m 0700 %t/fatline-qualify/redis
            Restart=on-failure
            EOF
            cat > "$out/config/redis.conf" <<'EOF'
            port 0
            unixsocket /run/redis/redis.sock
            unixsocketperm 770
            save ""
            appendonly no
            maxmemory 40mb
            maxmemory-policy noeviction
            aclfile /etc/redis/users.acl
            protected-mode yes
            EOF
            grep -qx 'Image=__CANDIDATE_IMAGE_ID__' "$out/quadlets/fatline-qualify-redis.container"
            grep -qx 'Network=none' "$out/quadlets/fatline-qualify-redis.container"
            grep -qx 'maxmemory-policy noeviction' "$out/config/redis.conf"
          '';
          # Qualification-only topology artifact. Never deployed or promoted.
          # Runtime selects and verifies actual immutable image IDs separately.
          composition-qualification = let
            config = import ./composition-config.nix;
          in import ./composition.nix {
            inherit pkgs;
            lib = pkgs.lib;
            config = config;
            components = {
              redis = "localhost/nix-alpine/redis:qualified-2026.10.23";
              nginx = "localhost/nix-alpine/nginx:qualified-2026.10.23.1";
              logma = "localhost/fatline/logma:2026.10.23";
              skymill = "localhost/fatline/skymill:2026.10.23";
            };
          };
          deployment = let config = import ./composition-config.nix; in import ./deployment.nix {
            inherit pkgs;
            inherit (config) images transports;
          };
          # Disposable structural fixture: mixed transport without changing production defaults.
          deployment-mixed = let config = import ./composition-config.nix; in import ./deployment.nix {
            inherit pkgs;
            inherit (config) images;
            transports = { logma = "unix"; skymill = "tcp-proxy"; };
          };
          fatline = let
            config = import ./composition-config.nix;
          in import ./composition.nix {
            inherit pkgs config;
            lib = pkgs.lib;
            components = config.images;
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
