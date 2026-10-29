{ pkgs, images, scope, skymillStream, transports ? { logma = "unix"; skymill = "unix"; } }:
let
  redisEnvironment = name: transport:
    if name == "logma" then
      if transport == "unix" then "Environment=REDIS_NETWORK=unix\nEnvironment=REDIS_SOCKET=/run/redis/redis.sock"
      else "Environment=REDIS_NETWORK=tcp\nEnvironment=REDIS_URI=fatline-redis-proxy:6379"
    else if transport == "unix" then "Environment=REDIS_URL=unix:///run/redis/redis.sock"
    else "Environment=REDIS_URL=redis://fatline-redis-proxy:6379";
  reconcileCommand = pkgs.writeShellScript "fatline-reconcile" ''
    exec ${pkgs.bash}/bin/bash ${./scripts/reconcile-redis.sh} \
      '${images.logma}' '${images.redis}' '${scope}' \
      "$HOME/.config/fatline/redis/credentials" \
      "''${XDG_RUNTIME_DIR:?}/fatline/redis"
  '';
  needsProxy = builtins.any (name: (transports.${name} or "unix") == "tcp-proxy") [ "logma" "skymill" ];
  provider = name: image: let transport = transports.${name} or "unix"; in assert builtins.elem transport [ "unix" "tcp-proxy" ]; ''
    [Unit]
    Description=Fatline ${name} provider
    Wants=${if transport == "tcp-proxy" then "fatline-redis-proxy.service" else "fatline-redis.service"}
    After=${if transport == "tcp-proxy" then "fatline-redis-proxy.service" else "fatline-redis.service"}
    ConditionPathExists=%h/.config/fatline/${name}.env

    [Container]
    Image=${image}
    Pull=never
    ContainerName=fatline-${name}
    Network=fatline.network
    ${if transport == "unix" then "Volume=%t/fatline/redis:/run/redis" else ""}
    Environment=FATLINE_REDIS_TRANSPORT=${transport}
    Environment=FATLINE_SCOPE=${scope}
    ${if name == "skymill" then "Environment=SKYMILL_SCOPED_PROVIDER=true\nEnvironment=SKYMILL_STREAM=${skymillStream}" else ""}
    ${redisEnvironment name transport}
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
  test -n '${scope}'
  test '${skymillStream}' = '${scope}:skymill:stream:github.webhooks'
  mkdir -p "$out/quadlets" "$out/config" "$out/metadata" "$out/readiness"
  cat > "$out/metadata/components.json" <<'EOF'
  ${builtins.toJSON { inherit (images) redis logma skymill; inherit transports scope skymillStream; }}
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
  ${if needsProxy then ''
  cat > "$out/quadlets/fatline-redis-proxy.container" <<'EOF'
  [Unit]
  Description=Fatline Redis TCP-to-Unix transport adapter
  Requires=fatline-redis.service
  After=fatline-redis.service

  [Container]
  Image=${images.nginx}
  Pull=never
  ContainerName=fatline-redis-proxy
  Network=fatline.network
  NetworkAlias=fatline-redis-proxy
  User=65534:65534
  ReadOnly=true
  Volume=%t/fatline/redis:/run/redis
  Volume=%h/.config/fatline/nginx/redis-proxy.conf:/etc/nginx/nginx.conf:ro
  Tmpfs=/tmp:rw,noexec,nosuid,size=4m
  NoNewPrivileges=true
  DropCapability=all

  [Service]
  Restart=on-failure

  [Install]
  WantedBy=default.target
  EOF
  cat > "$out/config/redis-proxy.conf" <<'EOF'
  worker_processes 1;
  pid /tmp/nginx.pid;
  error_log /dev/stderr warn;
  events { worker_connections 128; }
  stream {
    server {
      listen 0.0.0.0:6379;
      proxy_connect_timeout 3s;
      proxy_timeout 7200s;
      proxy_pass unix:/run/redis/redis.sock;
    }
  }
  EOF
  '' else ""}
  cat > "$out/quadlets/fatline-reconcile.service" <<'EOF'
  [Unit]
  Description=Converge Fatline Redis derived state
  After=fatline-redis.service
  # Missing reconciliation implementation is an error, not a skipped success.

  [Service]
  Type=oneshot
  ExecStartPre=/usr/bin/test -x %h/.config/fatline/reconcile
  ExecStart=${reconcileCommand}
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
  cat > "$out/config/users.acl.README" <<'EOF'
  Render users.acl with local/fatline/scripts/render-users-acl.py and the host-only
  credentials directory described in local/fatline/README.md.
  EOF
  cp ${./acl-policy.json} "$out/config/acl-policy.json"
  cp ${./scripts/render-users-acl.py} "$out/config/render-users-acl.py"
  cp ${./scripts/reconcile-redis.sh} "$out/config/reconcile-redis.sh"
  chmod 755 "$out/config/render-users-acl.py" "$out/config/reconcile-redis.sh"
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
  grep -qx 'Environment=FATLINE_SCOPE=${scope}' "$out/quadlets/fatline-logma.container"
  grep -qx 'Environment=FATLINE_SCOPE=${scope}' "$out/quadlets/fatline-skymill.container"
  grep -qx 'Environment=SKYMILL_SCOPED_PROVIDER=true' "$out/quadlets/fatline-skymill.container"
  grep -qx 'Environment=SKYMILL_STREAM=${skymillStream}' "$out/quadlets/fatline-skymill.container"
  ${if (transports.logma or "unix") == "unix" then ''
    grep -qx 'Environment=REDIS_NETWORK=unix' "$out/quadlets/fatline-logma.container"
    grep -qx 'Environment=REDIS_SOCKET=/run/redis/redis.sock' "$out/quadlets/fatline-logma.container"
  '' else ''
    grep -qx 'Environment=REDIS_NETWORK=tcp' "$out/quadlets/fatline-logma.container"
    grep -qx 'Environment=REDIS_URI=fatline-redis-proxy:6379' "$out/quadlets/fatline-logma.container"
  ''}
  ${if (transports.skymill or "unix") == "unix" then ''
    grep -qx 'Environment=REDIS_URL=unix:///run/redis/redis.sock' "$out/quadlets/fatline-skymill.container"
  '' else ''
    grep -qx 'Environment=REDIS_URL=redis://fatline-redis-proxy:6379' "$out/quadlets/fatline-skymill.container"
  ''}
  # Probes fail closed without credentials or explicit loopback endpoints.
  # Endpoint semantics and socket permissions require runtime qualification.
  # Proxy is generated only when a provider selects TCP transport.
  ! grep -Eq "PartOf=|BindsTo=" "$out"/quadlets/*.container
''
