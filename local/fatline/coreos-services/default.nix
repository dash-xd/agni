{ pkgs }:
let
  logmaRev = "870c9f0c21796bb670cb6f1a142ca38fc21b653a";
  skymillRev = "907346ecd74a4d39830347b2ea01dc2b1c6b8969";
  logmaSource = builtins.fetchGit { url = "https://github.com/xd-dash/logma.git"; rev = logmaRev; ref = "codex/fatline-keyspace-v2"; };
  skymillSource = builtins.fetchGit { url = "https://github.com/xd-dash/skymill.git"; rev = skymillRev; ref = "codex/scoped-requirements-qualification"; };
  build = pkgs.buildGoModule.override { go = pkgs.go_1_26; };
  logma = build {
    pname = "fatline-logma-api"; version = "1"; src = logmaSource;
    vendorHash = "sha256-Fw2my1ueJZBlHES4l656zALRMgaHUIHop+B0QT4FwAo=";
    subPackages = [ "cmd/api" "cmd/fatline-services-probe" ];
    env.CGO_ENABLED = "0";
    postPatch = ''mkdir -p cmd/fatline-services-probe; cp ${./probe.go} cmd/fatline-services-probe/main.go; cp ${./probe_test.go} cmd/fatline-services-probe/main_test.go'';
    doCheck = true;
    checkPhase = "go test -mod=vendor ./cmd/fatline-services-probe";
  };
  skymill = build {
    pname = "fatline-skymill-http"; version = "1"; src = skymillSource;
    vendorHash = "sha256-UUt7lGXSaQ8gGm6XbJEe86Zvy9y9s7RS6vRIYsUwXgQ=";
    proxyVendor = true; subPackages = [ "cmd/skymill-http" ]; env.CGO_ENABLED = "0"; doCheck = false;
  };
  metadata = { schema = 1; inherit logmaRev skymillRev;
    ratelimiterRev = "f9dd9465d98be5be2277908091237186ef606ca1";
    logma = "${logma}/bin/api"; probe = "${logma}/bin/fatline-services-probe";
    skymill = "${skymill}/bin/skymill-http";
  };
in pkgs.runCommand "agni-coreos-fatline-services-v1" {} ''
 mkdir -p "$out"
 cp ${./guest.sh} "$out/guest.sh"
 cp ${./render.py} "$out/render.py"
 cp ${../acl-policy.json} "$out/acl-policy.json"
 cp ${../scripts/render-users-acl.py} "$out/render-users-acl.py"
 cat > "$out/metadata.json" <<'JSON'
 ${builtins.toJSON metadata}
 JSON
''
