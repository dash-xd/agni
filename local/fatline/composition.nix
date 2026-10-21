{ pkgs, lib, config }:
let
  inherit (config) redis images;
  validMemory = assert lib.assertMsg (redis.memoryMiB == 40) "Only the 40 MiB Redis profile is qualified"; true;
  requireLocalImage = name: image:
    assert lib.assertMsg (builtins.isString image && builtins.match "sha256:[0-9a-f]{64}" image != null)
      "${name} image must be a verified local Podman sha256 image ID";
    image;
  service = name: image: ''
    [Unit]
    Description=Fatline ${name}
    Requires=fatline-redis.service
    After=fatline-redis.service
    ConditionPathExists=%h/.config/fatline/${name}.env

    [Container]
    Image=${requireLocalImage name image}
    Pull=never
    ContainerName=fatline-${name}
    Network=none
    Volume=%t/fatline/redis:/run/redis
    EnvironmentFile=%h/.config/fatline/${name}.env

    [Service]
    Restart=always

    [Install]
    WantedBy=default.target
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
    ConditionPathExists=%h/.config/fatline/redis/users.acl

    [Container]
    Image=${requireLocalImage "redis" images.redis}
    Pull=never
    ContainerName=fatline-redis
    Network=none
    ReadOnly=true
    Volume=%h/.config/fatline/redis/redis.conf:/etc/redis/redis.conf:ro
    Volume=%h/.config/fatline/redis/users.acl:/etc/redis/users.acl:ro
    Volume=%t/fatline/redis:/run/redis
    # The Redis image entrypoint is redis-server; Exec supplies its config argument.
    Exec=/etc/redis/redis.conf
    NoNewPrivileges=true
    DropCapability=all

    [Service]
    ExecStartPre=/usr/bin/install -d -m 0770 %t/fatline/redis
    Restart=always

    [Install]
    WantedBy=default.target
  '';
in assert validMemory; pkgs.runCommand "fatline-quadlet-composition" { } ''
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
  grep -qx 'Pull=never' "$out/quadlets/fatline-redis.container"
  grep -qx 'port 0' "$out/config/redis.conf"
  grep -qx 'maxmemory 40mb' "$out/config/redis.conf"
  grep -qx 'maxmemory-policy noeviction' "$out/config/redis.conf"
  grep -qx 'aclfile /etc/redis/users.acl' "$out/config/redis.conf"
  for provider in logma skymill; do
    grep -qx 'Pull=never' "$out/quadlets/fatline-$provider.container"
    grep -qx 'Requires=fatline-redis.service' "$out/quadlets/fatline-$provider.container"
    grep -qx 'After=fatline-redis.service' "$out/quadlets/fatline-$provider.container"
  done
''
