{ pkgs, images, transports ? { logma = "unix"; skymill = "unix"; } }:
let
  provider = name: image: let transport = transports.${name} or "unix"; in assert builtins.elem transport [ "unix" "tcp-proxy" ]; ''
    [Unit]
    Description=Fatline ${name} provider
    Wants=fatline-redis.service
    After=fatline-redis.service
    ConditionPathExists=%h/.config/fatline/${name}.env

    [Container]
    Image=${image}
    Pull=never
    ContainerName=fatline-${name}
    Network=fatline.network
    ${if transport == "unix" then "Volume=%t/fatline/redis:/run/redis" else ""}
    Environment=FATLINE_REDIS_TRANSPORT=${transport}
    EnvironmentFile=%h/.config/fatline/${name}.env
    ReadOnly=true
    NoNewPrivileges=true
    DropCapability=all

    [Service]
    Restart=on-failure

    [Install]
    WantedBy=default.target
  '';
in pkgs.runCommand "fatline-deployment" {} ''
  mkdir -p "$out/quadlets" "$out/config" "$out/metadata" "$out/readiness"
  cat > "$out/metadata/components.json" <<'EOF'
  ${builtins.toJSON { inherit (images) redis logma skymill; inherit transports; }}
  EOF
  cat > "$out/quadlets/fatline.network" <<'EOF'
  [Network]
  NetworkName=fatline
  Internal=true
  EOF
  cat > "$out/quadlets/fatline-redis.container" <<'EOF'
  [Unit]
  Description=Fatline volatile Redis
  ConditionPathExists=%h/.config/fatline/redis/users.acl

  [Container]
  Image=${images.redis}
  Pull=never
  ContainerName=fatline-redis
  Network=none
  User=65534:65534
  ReadOnly=true
  Volume=%h/.config/fatline/redis/redis.conf:/etc/redis/redis.conf:ro
  Volume=%h/.config/fatline/redis/users.acl:/etc/redis/users.acl:ro
  Volume=%t/fatline/redis:/run/redis
  Exec=/etc/redis/redis.conf
  NoNewPrivileges=true
  DropCapability=all

  [Service]
  ExecStartPre=/usr/bin/install -d -m 0700 %t/fatline
  ExecStartPre=/usr/bin/podman unshare install -d -o 65534 -g 65534 -m 0770 %t/fatline/redis
  Restart=on-failure
  ExecStartPost=/usr/bin/systemctl --user --no-block start fatline-reconcile.service

  [Install]
  WantedBy=default.target
  EOF
  cat > "$out/quadlets/fatline-logma.container" <<'EOF'
  ${provider "logma" images.logma}
  EOF
  cat > "$out/quadlets/fatline-skymill.container" <<'EOF'
  ${provider "skymill" images.skymill}
  EOF
  cat > "$out/quadlets/fatline-reconcile.service" <<'EOF'
  [Unit]
  Description=Converge Fatline Redis derived state
  After=fatline-redis.service
  # Missing reconciliation implementation is an error, not a skipped success.

  [Service]
  Type=oneshot
  ExecStartPre=/usr/bin/test -x %h/.config/fatline/reconcile
  ExecStart=%h/.config/fatline/reconcile
  TimeoutStartSec=120
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
  cat > "$out/readiness/redis" <<'EOF'
  #!/usr/bin/env bash
  set -Eeuo pipefail
  socket="''${XDG_RUNTIME_DIR:?}/fatline/redis/redis.sock"
  test -S "$socket"
  : "''${FATLINE_REDIS_USER:?Redis user required}"
  : "''${FATLINE_REDIS_PASSWORD_FILE:?Redis password file required}"
  test -r "$FATLINE_REDIS_PASSWORD_FILE"
  password=$(cat "$FATLINE_REDIS_PASSWORD_FILE")
  test -n "$password"
  REDISCLI_AUTH="$password" redis-cli -s "$socket" --user "$FATLINE_REDIS_USER" PING | grep -Fx PONG
  EOF
  cat > "$out/readiness/logma" <<'EOF'
  #!/usr/bin/env bash
  set -Eeuo pipefail
  : "''${FATLINE_LOGMA_READINESS_URL:?Readiness URL required}"
  case "$FATLINE_LOGMA_READINESS_URL" in http://127.0.0.1:*|http://localhost:*) ;; *) exit 2;; esac
  curl --fail --silent --show-error --max-time 3 "$FATLINE_LOGMA_READINESS_URL" >/dev/null
  EOF
  cat > "$out/readiness/skymill" <<'EOF'
  #!/usr/bin/env bash
  set -Eeuo pipefail
  : "''${FATLINE_SKYMILL_READINESS_URL:?Readiness URL required}"
  case "$FATLINE_SKYMILL_READINESS_URL" in http://127.0.0.1:*|http://localhost:*) ;; *) exit 2;; esac
  curl --fail --silent --show-error --max-time 3 "$FATLINE_SKYMILL_READINESS_URL" >/dev/null
  EOF
  chmod 755 "$out"/readiness/*
  # Probes fail closed without credentials or explicit loopback endpoints.
  # Endpoint semantics and socket permissions require runtime qualification.
  ! grep -q "fatline-nginx" "$out"/quadlets/*.container
  ! grep -Eq "PartOf=|BindsTo=" "$out"/quadlets/*.container
''
