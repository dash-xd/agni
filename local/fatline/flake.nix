{
  description = "Agni local Fatline composition executed inside Nix-Alpine";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  inputs.nix-alpine-runtime = {
    url = "github:xd-dash/nix.xd/ccb21c8f6e1defacc7da7989ba6ac8b7985d53a1";
    flake = false;
  };

  outputs = { self, nixpkgs, nix-alpine-runtime }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
      smokeRevision = "66950da9a5e4e5303f5dcd018f9039f9b6fc8496";
      smokeSource = builtins.fetchGit {
        url = "https://github.com/xd-dash/smoke.git";
        rev = smokeRevision;
      };
      coreosPlans = forAllSystems (system: {
        vm1 = import ./coreos/plan.nix { inherit system; profile = "vm1"; };
        vm2 = import ./coreos/plan.nix { inherit system; profile = "vm2"; };
      });
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
          coreos-plan-vm1 = pkgs.writeText "agni-coreos-vm1-plan.json" (builtins.toJSON coreosPlans.${system}.vm1);
          coreos-plan-vm2 = pkgs.writeText "agni-coreos-vm2-plan.json" (builtins.toJSON coreosPlans.${system}.vm2);
          host-link-vm1 = import ./host-link { inherit pkgs; };
          host-link-vm2 = import ./host-link { inherit pkgs; scope = "fatline-arm-vm2"; };
          coreos-services-vm1 = import ./coreos-services { inherit pkgs; };
          coreos-startup-profile = import ./startup-profile { inherit pkgs; };
          # Composition-owned runtime images; Nix-Alpine supplies only the build/runtime toolchain.
          redis-image = pkgs.dockerTools.buildLayeredImage {
            name = "localhost/fatline-redis";
            tag = "candidate";
            contents = [ pkgs.redis ];
            config = {
              Entrypoint = [ "${pkgs.redis}/bin/redis-server" ];
              Cmd = [ "/etc/redis/redis.conf" ];
            };
          };
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
            inherit (config) images scope skymillStream transports;
          };
          # Disposable structural fixture: mixed transport without changing production defaults.
          deployment-mixed = let config = import ./composition-config.nix; in import ./deployment.nix {
            inherit pkgs;
            inherit (config) images scope skymillStream;
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
      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          plans = coreosPlans.${system};
          valid = plan:
            plan.schema == 1
            && plan.system == system
            && plan.sourceSelection.immutableRevisionRequired
            && !plan.sourceSelection.mutableBranchAllowed
            && plan.sources.agni.repository == "dash-xd/agni"
            && builtins.match "[0-9a-f]{40}" plan.sources.agni.revision != null
            && plan.services.contract == "coreos-services-v1"
            && builtins.match "[0-9a-f]{40}" plan.services.revision != null
            && builtins.all (revision: builtins.match "[0-9a-f]{40}" revision != null)
                 (builtins.attrValues plan.componentRevisions)
            && builtins.match "[0-9a-f]{40}" plan.hostArtifacts.smoke.sourceRevision != null
            && builtins.match "github:dash-xd/agni/[0-9a-f]{40}[?]dir=local/fatline" plan.hostArtifacts.smoke.flake != null
            && plan.hostArtifacts.smoke.app == "smoke-host-artifact"
            && plan.hostArtifacts.smoke.target == "darwin-arm64"
            && !plan.fullFatlineQualified;
        in {
          coreos-plan = assert valid plans.vm1 && valid plans.vm2
            && plans.vm1.scope != plans.vm2.scope
            && plans.vm1.placement.sshPort != plans.vm2.placement.sshPort;
            pkgs.runCommand "agni-coreos-plan-contract" { } ''
              touch "$out"
            '';
        });
      apps = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          runtimePrimitives = import "${nix-alpine-runtime}/runtime" { inherit pkgs; };
          startupPython = pkgs.python3.withPackages (_: [ runtimePrimitives ]);
          startup = pkgs.writeShellApplication {
            name = "agni-startup";
            runtimeInputs = [ startupPython pkgs.bash pkgs.coreutils pkgs.gawk ];
            text = ''
              exec python3 ${./startup-profile}/controller.py "$@"
            '';
          };
          checkAclPins = pkgs.writeShellApplication {
            name = "agni-check-acl-pins";
            runtimeInputs = [ pkgs.python3 ];
            text = ''
              exec ${pkgs.python3}/bin/python3 ${./scripts/check-acl-pins.py} "$@"
            '';
          };
          runner = pkgs.writeShellApplication {
            name = "agni-fatline";
            runtimeInputs = with pkgs; [ bash coreutils findutils git gnumake go_1_26 stdenv.cc redis gnugrep gnused ];
            text = ''
              exec bash ${./scripts/fatline.sh} "$@"
            '';
          };
          smokeHostArtifact = pkgs.writeShellApplication {
            name = "agni-fatline-smoke-host-artifact";
            runtimeInputs = [ pkgs.go_1_26 pkgs.nix pkgs.coreutils ];
            text = ''
              set -euo pipefail
              source=${smokeSource}
              revision=${smokeRevision}
              state="''${HOME}/.local/state/nix-xd/agni-fatline/smoke/$revision"
              mkdir -p "$state/cache" "$state/mod"
              export GOCACHE="$state/cache"
              export GOMODCACHE="$state/mod"
              export GOOS=darwin GOARCH=arm64 CGO_ENABLED=0
              workdir="$(mktemp -d "$state/build.XXXXXXXX")"
              trap 'rm -rf -- "$workdir"' EXIT
              (cd "$source" && go build -mod=readonly -trimpath -buildvcs=false -ldflags=-buildid= -o "$workdir/smoke" ./cmd/smoke-wisp)
              path="$(nix-store --add "$workdir/smoke")"
              nix-store --realise --add-root "$state/gcroot" "$path" >/dev/null
              printf 'ARTIFACT_SOURCE_REV=%s\\n' "$revision"
              printf 'ARTIFACT_STORE_PATH=%s\\n' "$path"
              printf 'ARTIFACT_SHA256=%s\\n' "$(sha256sum "$path" | cut -d' ' -f1)"
              printf 'ARTIFACT_TARGET=%s\\n' darwin-arm64
            '';
          };
          app = command: {
            type = "app";
            program = "${pkgs.writeShellScript "agni-fatline-${command}" ''
              exec ${runner}/bin/agni-fatline ${command} "$@"
            ''}";
          };
          planRunner = pkgs.writeShellApplication {
            name = "agni-qualification-plan";
            runtimeInputs = with pkgs; [
              bash coreutils findutils git gnumake podman systemd python3
              go_1_26 stdenv.cc redis gnugrep gnused
            ];
            text = ''
              : "''${NIX_XD_PLAN_ROOT:?NIX_XD_PLAN_ROOT must point to the pinned workspace checkout}"
              exec bash "''${NIX_XD_PLAN_ROOT}/local/fatline/qualification/run-plan.sh" "$@"
            '';
          };
        in {
          smoke-host-artifact = {
            type = "app";
            program = "${smokeHostArtifact}/bin/agni-fatline-smoke-host-artifact";
          };
          coreos-plan-vm1 = {
            type = "app";
            program = "${pkgs.writeShellScript "agni-coreos-plan-vm1" ''
              exec ${pkgs.coreutils}/bin/cat ${self.packages.${system}.coreos-plan-vm1}
            ''}";
          };
          coreos-plan-vm2 = {
            type = "app";
            program = "${pkgs.writeShellScript "agni-coreos-plan-vm2" ''
              exec ${pkgs.coreutils}/bin/cat ${self.packages.${system}.coreos-plan-vm2}
            ''}";
          };
          startup = {
            type = "app";
            program = "${startup}/bin/agni-startup";
          };
          qualify-plan = {
            type = "app";
            program = "${planRunner}/bin/agni-qualification-plan";
          };
          check-acl-pins = {
            type = "app";
            program = "${checkAclPins}/bin/agni-check-acl-pins";
          };
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
