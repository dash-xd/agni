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
      mkSmokeNativeQualifier = pkgs: pkgs.writeShellApplication {
            name = "agni-fatline-native-qualifier";
            runtimeInputs = [ pkgs.go_1_26 pkgs.coreutils pkgs.gnugrep pkgs.openssh ];
            text = ''
              set -Eeuo pipefail
              mode="''${1:---check-build}"
              test "$(uname -s)" = Linux || { echo 'Native qualifier requires Linux Nix-Alpine' >&2; exit 1; }
              case "$mode" in
                --check-build|--check-transport) ;;
                *) echo 'Available gates: --check-build, --check-transport' >&2; exit 2 ;;
              esac

              revision=${smokeRevision}
              source=${smokeSource}
              if [[ -n "''${NIX_XD_NATIVE_BINARY:-}" ]]; then
                binary="$NIX_XD_NATIVE_BINARY"
                [[ "$mode" == --check-transport ]] || { echo 'Prebuilt binary only accepted for transport' >&2; exit 2; }
                [[ "$binary" =~ ^/nix/store/[a-z0-9]{32}-smoke$ && -x "$binary" ]] ||
                  { echo 'Expected a native Smoke binary in the mounted Nix store' >&2; exit 1; }
                go version -m "$binary" | grep -Fq 'GOOS=linux'
                echo 'AGNI_NATIVE_SMOKE_REUSED=passed'
              else
                root="''${HOME}/.local/state/agni/fatline/smoke/$revision"
                mkdir -p "$root/cache" "$root/mod"
                export GOCACHE="$root/cache" GOMODCACHE="$root/mod"
                export GOOS=linux CGO_ENABLED=0
                work="$(mktemp -d "$root/build.XXXXXXXX")"
                trap 'rm -rf -- "$work"' EXIT
                (cd "$source" && go build -mod=readonly -trimpath -buildvcs=false -ldflags=-buildid= -o "$work/smoke" ./cmd/smoke-wisp)
                binary="$(nix-store --add "$work/smoke")"
                nix-store --realise --add-root "$root/gcroot" "$binary" >/dev/null
                go version -m "$binary" | grep -Fq 'GOOS=linux'
                printf 'AGNI_NATIVE_SMOKE_BUILD=passed source=%s store=%s sha256=%s\n' \
                  "$revision" "$binary" "$(sha256sum "$binary" | cut -d' ' -f1)"
              fi

              printf 'NIX_XD_NATIVE_ARTIFACT=%s\n' "$binary"
              if [[ "$mode" == --check-build ]]; then
                echo 'AGNI_RESOURCE_QUALIFICATION=pending phase=transport-and-credential-contract'
                exit 0
              fi

              endpoint="''${NIX_XD_TRANSPORT_ENDPOINT:-}"
              if [[ -z "$endpoint" ]]; then endpoint="''${AGNI_COREOS_ENDPOINT:-}"; fi
              port="''${NIX_XD_TRANSPORT_PORT:-}"
              if [[ -z "$port" ]]; then port="''${AGNI_COREOS_PORT:-}"; fi
              identity="''${NIX_XD_TRANSPORT_IDENTITY:-}"
              if [[ -z "$identity" ]]; then identity="''${AGNI_COREOS_IDENTITY:-}"; fi
              known_hosts="''${NIX_XD_TRANSPORT_KNOWN_HOSTS:-}"
              if [[ -z "$known_hosts" ]]; then known_hosts="''${AGNI_COREOS_KNOWN_HOSTS:-}"; fi
              guest_user="''${NIX_XD_TRANSPORT_USER:-}"
              if [[ -z "$guest_user" ]]; then guest_user="''${AGNI_COREOS_USER:-wisp}"; fi
              evidence_dir="''${NIX_XD_EVIDENCE_DIR:-}"
              if [[ -z "$evidence_dir" ]]; then evidence_dir="''${AGNI_EVIDENCE_DIR:-}"; fi
              [[ -n "$endpoint" && "$port" =~ ^[0-9]{1,5}$ ]] || {
                echo 'Missing or invalid CoreOS endpoint and port' >&2; exit 2;
              }
              [[ "$identity" == /run/nix-xd/mounts/secrets/identity &&
                 "$known_hosts" == /run/nix-xd/mounts/secrets/known_hosts ]] || {
                echo 'SSH trust paths must be explicitly volume-mounted' >&2; exit 1;
              }
              [[ -f "$identity" && -f "$known_hosts" ]] || {
                echo 'SSH trust material is not mounted into the qualifier' >&2; exit 1;
              }
              "$binary" wisp qualify \
                --address "$endpoint:$port" \
                --user "$guest_user" \
                --identity "$identity" \
                --known-hosts "$known_hosts" \
                --timeout 2m
              if [[ -n "$evidence_dir" ]]; then
                [[ "$evidence_dir" == /run/nix-xd/mounts/evidence ]] || exit 2
                printf 'AGNI_NATIVE_WISP_TRANSPORT=passed\n' > "$evidence_dir/native-wisp-transport.txt"
              fi
              echo 'AGNI_NATIVE_WISP_TRANSPORT=passed'
              echo 'AGNI_RESOURCE_QUALIFICATION=pending phase=resource-authorization-and-delivery'
            '';
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
          native-smoke-qualifier = mkSmokeNativeQualifier pkgs;
          secret-volume-fixture = pkgs.writeShellApplication {
            name = "agni-secret-volume-fixture";
            runtimeInputs = with pkgs; [ age sops jq coreutils ];
            text = ''
              set -Eeuo pipefail
              secret_dir=/run/nix-xd/mounts/secrets
              evidence_dir=/run/nix-xd/mounts/evidence
              identity="$secret_dir/identity.txt"
              encrypted="$secret_dir/fixture.sops.json"
              case "''${1:-}" in
                init)
                  [[ ! -e "$identity" && ! -e "$encrypted" ]] || {
                    echo 'Existing secrets volume; refusing to overwrite fixture' >&2
                    exit 1
                  }
                  [[ -d "$secret_dir" && -w "$secret_dir" ]] || exit 1
                  umask 077
                  age-keygen -o "$identity"
                  recipient="$(age-keygen -y "$identity")"
                  scratch="$(mktemp -d)"
                  trap 'rm -rf -- "$scratch"' EXIT
                  printf '%s\\n' '{"fixture":"persistent-podman-volume","valid":true}' > "$scratch/fixture.json"
                  sops --encrypt --age "$recipient" --input-type json --output-type json "$scratch/fixture.json" > "$encrypted"
                  chmod 0600 "$identity" "$encrypted"
                  echo 'AGNI_SECRET_VOLUME_INITIALIZED=passed mode=0600'
                  ;;
                verify)
                  [[ -r "$identity" && -r "$encrypted" && -w "$evidence_dir" ]] || exit 1
                  [[ "$(stat -c %a "$identity")" == 600 ]] || exit 1
                  if ( : > "$secret_dir/unauthorized-write" ) 2>/dev/null; then
                    rm -f "$secret_dir/unauthorized-write"
                    echo 'Secret volume unexpectedly writable by qualifier' >&2
                    exit 1
                  fi
                  scratch="$(mktemp -d)"
                  trap 'rm -rf -- "$scratch"' EXIT
                  umask 077
                  SOPS_AGE_KEY_FILE="$identity" sops --decrypt --input-type json --output-type json "$encrypted" |
                    jq -e '.fixture == "persistent-podman-volume" and .valid == true' > "$scratch/verified"
                  [[ "$(cat "$scratch/verified")" == true ]] || exit 1
                  test -r "$identity"
                  printf '%s\\n' 'SECRETS_VOLUME_AGE_SOPS=passed' > "$evidence_dir/secret-volume-gate.txt"
                  printf '%s\\n' 'SECRETS_VOLUME_NIX_STORE=protected' >> "$evidence_dir/secret-volume-gate.txt"
                  echo 'AGNI_SECRET_VOLUME_QUALIFICATION=passed'
                  ;;
                *)
                  echo 'Usage: agni-secret-volume-fixture init|verify' >&2
                  exit 2
                  ;;
              esac
            '';
          };
          runtime-grants = pkgs.writeText "agni-fatline-runtime-grants.json" (builtins.readFile ./qualification/runtime-grants.json);
          isolated-runtime-grants = pkgs.writeText "agni-fatline-isolated-runtime-grants.json" (builtins.readFile ./qualification/isolated-runtime-grants.json);
          coreos-plan-vm1 = pkgs.writeText "agni-coreos-vm1-plan.json" (builtins.toJSON coreosPlans.${system}.vm1);
          coreos-plan-vm2 = pkgs.writeText "agni-coreos-vm2-plan.json" (builtins.toJSON coreosPlans.${system}.vm2);
          host-link-vm1 = import ./host-link { inherit pkgs; };
          host-link-vm2 = import ./host-link { inherit pkgs; scope = "fatline-arm-vm2"; };
          coreos-services-vm1 = import ./coreos-services { inherit pkgs; };
          coreos-startup-profile = import ./startup-profile { inherit pkgs; };
          probot-rootfs-archive = pkgs.runCommand "agni-vm1-probot-rootfs.tar" { nativeBuildInputs = [ pkgs.gnutar ]; } ''
            mkdir -p rootfs/bin rootfs/etc rootfs/run rootfs/tmp rootfs/var/lib
            cp ${pkgs.pkgsStatic.busybox}/bin/busybox rootfs/bin/busybox
            chmod 0555 rootfs/bin/busybox
            ln -s busybox rootfs/bin/sh
            tar -C rootfs -cf "$out" .
          '';
          probot-guest-tools = pkgs.runCommand "agni-probot-vm1-guest-tools" {} ''
            mkdir -p "$out"
            cp ${./startup-profile/probot-guest-stage.sh} "$out/probot-guest-stage.sh"
            cp ${./startup-profile/probot-stage.py} "$out/probot-stage.py"
            cp ${./startup-profile/probot-render.py} "$out/probot-render.py"
            cp ${./startup-profile/render.py} "$out/render.py"
            cp ${./startup-profile/runtime.sh} "$out/runtime.sh"
            cp ${./startup-profile/probot-adoption.py} "$out/probot-adoption.py"
            cp ${./startup-profile/probot-adoption-review.py} "$out/probot-adoption-review.py"
            cp ${./startup-profile/probot-migrate.py} "$out/probot-migrate.py"
            cp ${./startup-profile/probot-migration-verify.py} "$out/probot-migration-verify.py"
            cp ${./startup-profile/probot-activation-plan.py} "$out/probot-activation-plan.py"
            cp ${./startup-profile/probot-activation-check.py} "$out/probot-activation-check.py"
            cp ${./startup-profile/probot-recovery-qualify.py} "$out/probot-recovery-qualify.py"
            cp ${./startup-profile/probot-sandbox-http-recover.py} "$out/probot-sandbox-http-recover.py"
            cp ${./startup-profile/probot-runtime-qualify.py} "$out/probot-runtime-qualify.py"
            cp ${./startup-profile/probot-network-diagnose.py} "$out/probot-network-diagnose.py"
            cp ${self.packages.${system}.coreos-startup-profile}/metadata.json "$out/metadata.json"
            cat > "$out/migration-paths.json" <<'JSON'
            ${builtins.toJSON { bundle = "${self.packages.${system}.coreos-startup-profile}"; archive = "${self.packages.${system}.probot-rootfs-archive}"; }}
            JSON
            cp ${./coreos-services/probot-credentials.py} "$out/probot-credentials.py"
            cp ${./scripts/render-users-acl.py} "$out/render-users-acl.py"
            printf '%s\n' "${pkgs.python3}/bin/python3" > "$out/python-path"
            chmod 0555 "$out/probot-guest-stage.sh" "$out/runtime.sh"
          '';
          vm1-probot-guest-stage =
            let tools = self.packages.${system}.probot-guest-tools;
            in pkgs.runCommand "agni-vm1-probot-guest-stage" {} ''
              mkdir -p "$out"
              cp ${./startup-profile/probot-guest-app.sh} "$out/guest.sh"
              substituteInPlace "$out/guest.sh" \
                --replace-fail '@AGNI_PROBOT_GUEST_TOOL_STORE@' "${tools}"
              chmod 0555 "$out/guest.sh"
            '';
          vm1-guest-check = pkgs.runCommand "agni-vm1-guest-check-v1" {} ''
            mkdir -p "$out"
            cp ${./coreos-services/vm1-check.sh} "$out/guest.sh"
            chmod 0555 "$out/guest.sh"
          '';
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
          smokeNativeQualifier = mkSmokeNativeQualifier pkgs;
          smokeHostArtifact = pkgs.writeShellApplication {
            name = "agni-fatline-smoke-host-artifact";
            runtimeInputs = [ pkgs.go_1_26 pkgs.coreutils ];
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
              printf 'ARTIFACT_SOURCE_REV=%s\n' "$revision"
              printf 'ARTIFACT_STORE_PATH=%s\n' "$path"
              printf 'ARTIFACT_SHA256=%s\n' "$(sha256sum "$path" | cut -d' ' -f1)"
              printf 'ARTIFACT_TARGET=%s\n' darwin-arm64
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
          runtime-grants = {
            type = "app";
            program = "${pkgs.writeShellScript "agni-fatline-runtime-grants" ''
              exec ${pkgs.coreutils}/bin/cat ${self.packages.${system}.runtime-grants}
            ''}";
          };
          isolated-runtime-grants = {
            type = "app";
            program = "${pkgs.writeShellScript "agni-fatline-isolated-runtime-grants" ''
              exec ${pkgs.coreutils}/bin/cat ${self.packages.${system}.isolated-runtime-grants}
            ''}";
          };
          resource-preflight = {
            type = "app";
            program = "${smokeNativeQualifier}/bin/agni-fatline-native-qualifier";
          };
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
          qualify-integration = {
            type = "app";
            program = "${pkgs.writeShellScript "agni-fatline-qualify-integration" ''
              if [[ "''${1:-}" == --scenario ]]; then
                export PATH="${pkgs.lib.makeBinPath [ pkgs.nodejs_22 pkgs.python3 pkgs.coreutils pkgs.bash pkgs.go_1_26 pkgs.git pkgs.gnugrep pkgs.file pkgs.redis ]}:$PATH"
                export AGNI_PROBOT_SOURCES="${./qualification/probot-webhook-sources.json}"
                export AGNI_PROBOT_ARTIFACT_BUILDER="${./qualification/probot-artifacts.sh}"
                export AGNI_PROBOT_GUEST_BUNDLE_BUILDER="${./qualification/probot-guest-bundle.py}"
                export AGNI_CANDIDATE_OUTPUT="${./coreos-services/candidate-output.py}"
                export AGNI_PROBOT_GUEST_PLANNER="${./coreos-services/probot-plan.py}"
                export AGNI_PROBOT_REDIS_PLANNER="${./coreos-services/probot-redis-policy.py}"
                export AGNI_PROBOT_REDIS_PLANNER_TEST="${./coreos-services/test_probot_redis_policy.py}"
                export AGNI_PROBOT_REDIS_BASELINE="${./acl-policy.json}"
                export AGNI_PROBOT_REDIS_RUNTIME="${./qualification/probot-acl-runtime.sh}"
                export AGNI_PROBOT_PROFILE_RENDERER="${./startup-profile/probot-render.py}"
                export AGNI_PROBOT_STARTUP_RENDERER="${./startup-profile/render.py}"
                export AGNI_PROBOT_PROFILE_RENDER_TEST="${./startup-profile/test_probot_render.py}"
                export AGNI_PROBOT_CREDENTIAL_GENERATOR="${./coreos-services/probot-credentials.py}"
                export AGNI_PROBOT_CREDENTIAL_GENERATOR_TEST="${./coreos-services/test_probot_credentials.py}"
                export AGNI_PROBOT_REDIS_RENDERER="${./scripts/render-users-acl.py}"
                export AGNI_PROBOT_GUEST_PLANNER_TEST="${./coreos-services/test_probot_plan.py}"
                exec ${pkgs.bash}/bin/bash ${./qualification/probot-webhook.sh} "$@"
              fi
              exec ${runner}/bin/agni-fatline qualify-integration "$@"
            ''}";
          };
          advance-pin = app "advance-pin";
          default = app "preflight";
        });
    };
}
