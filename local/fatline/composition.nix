{ pkgs, lib, config }:
let
  inherit (config) redis images;
  requireDigest = name: image:
    assert lib.assertMsg (builtins.match ".+@sha256:[0-9a-f]{64}" image != null)
      "${name} image must be pinned to an OCI sha256 digest";
    image;
  service = name: image: ''
    [Unit]
    Description=Fatline ${name}
    Requires=fatline-redis.service
    After=fatline-redis.service
    ConditionPathExists=/etc/fatline/${name}.env

    [Container]
    Image=${requireDigest name image}
    ContainerName=fatline-${name}
    Network=none
    Volume=/run/fatline/redis:/run/redis
    EnvironmentFile=/etc/fatline/${name}.env

    [Service]
    Restart=always

    [Install]
    WantedBy=multi-user.target
  '';
  redisConf = ''
    port 0
    unixsocket /run/redis/redis.sock
    unixsocketperm 770
    save ""
    appendonly no
    maxmemory ${toString redis.memoryMiB}mb
    maxmemory-policy noeviction
    aclfile /etc/redis/users.acl
    protected-mode yes
  '';
  redisUnit = ''
    [Unit]
    Description=Fatline shared Redis
    ConditionPathExists=/etc/fatline/redis/users.acl
    After=local-fs.target

    [Container]
    Image=${requireDigest "redis" images.redis}
    ContainerName=fatline-redis
    Network=none
    ReadOnly=true
    Volume=/etc/fatline/redis/redis.conf:/etc/redis/redis.conf:ro
    Volume=/etc/fatline/redis/users.acl:/etc/redis/users.acl:ro
    Volume=/run/fatline/redis:/run/redis
    Exec=redis-server /etc/redis/redis.conf
    NoNewPrivileges=true
    DropCapability=all

    [Service]
    ExecStartPre=/usr/bin/install -d -m 0770 /run/fatline/redis
    Restart=always

    [Install]
    WantedBy=multi-user.target
  '';
in pkgs.runCommand "fatline-quadlet-composition" { } ''
  mkdir -p "$out/quadlets" "$out/config"
  cat > "$out/quadlets/fatline-redis.container" <<'EOF'
${redisUnit}
EOF
  cat > "$out/quadlets/fatline-logma.container" <<'EOF'
${service "logma" images.logma}
EOF
  cat > "$out/quadlets/fatline-skymill.container" <<'EOF'
${service "skymill" images.skymill}
EOF
  cat > "$out/config/redis.conf" <<'EOF'
${redisConf}
EOF
'';
