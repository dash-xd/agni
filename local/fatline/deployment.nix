{ pkgs, images }:
let
  provider = name: image: ''
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
  mkdir -p "$out/quadlets" "$out/config" "$out/metadata"
  cat > "$out/metadata/components.json" <<'EOF'
  ${builtins.toJSON { inherit (images) redis logma skymill; }}
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
  ExecStartPre=/usr/bin/install -d -m 0770 %t/fatline/redis
  Restart=on-failure

  [Install]
  WantedBy=default.target
  EOF
  cat > "$out/quadlets/fatline-logma.container" <<'EOF'
  ${provider "logma" images.logma}
  EOF
  cat > "$out/quadlets/fatline-skymill.container" <<'EOF'
  ${provider "skymill" images.skymill}
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
  ! grep -q "fatline-nginx" "$out"/quadlets/*.container
  ! grep -Eq "PartOf=|BindsTo=" "$out"/quadlets/*.container
'';
