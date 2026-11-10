{ pkgs, scope ? "fatline-arm-vm1", port ? 16379 }:
let
  logmaRev = "870c9f0c21796bb670cb6f1a142ca38fc21b653a";
  logmaSource = builtins.fetchGit { url = "https://github.com/xd-dash/logma.git"; rev = logmaRev; ref = "codex/fatline-keyspace-v2"; };
  arch = if pkgs.stdenv.hostPlatform.isAarch64 then "arm64" else "amd64";
  client = target: (pkgs.buildGoModule.override { go = pkgs.go_1_26; }) {
    pname = "fatline-host-link-${target}";
    version = "1";
    src = logmaSource;
    vendorHash = "sha256-Fw2my1ueJZBlHES4l656zALRMgaHUIHop+B0QT4FwAo=";
    postPatch = ''
      mkdir -p cmd/fatline-host-link
      cp ${./client.go} cmd/fatline-host-link/main.go
    '';
    doCheck = false;
    dontStrip = target == "darwin";
    buildPhase = ''
      runHook preBuild
      CGO_ENABLED=0 GOOS=${target} GOARCH=${arch} go build -mod=vendor -trimpath -o host-link ./cmd/fatline-host-link
      runHook postBuild
    '';
    installPhase = ''mkdir -p "$out/bin"; cp host-link "$out/bin/host-link"'';
  };
  linuxClient = client "linux";
  darwinClient = client "darwin";
  metadata = { schema = 1; inherit scope port logmaRev;
    redis = "${pkgs.redis}"; nginx = "${pkgs.nginx}";
    clientLinux = "${linuxClient}/bin/host-link";
    clientDarwin = "${darwinClient}/bin/host-link";
    status = "transport-qualification-only";
  };
in assert builtins.match "[a-z][a-z0-9-]{0,31}" scope != null;
assert port >= 1024 && port <= 65535;
pkgs.runCommand "fatline-host-link-${scope}" {} ''
 mkdir -p "$out"
 cp ${./guest.sh} "$out/guest.sh"
 cp ${./render.py} "$out/render.py"
 cat > "$out/metadata.json" <<'JSON'
 ${builtins.toJSON metadata}
 JSON
''
