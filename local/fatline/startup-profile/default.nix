{ pkgs }:
let services = import ../coreos-services { inherit pkgs; };
in pkgs.runCommand "agni-fatline-startup-profile-v1" {} ''
  mkdir -p "$out"
  cp ${./render.py} "$out/render.py"
  cp ${./runtime.sh} "$out/runtime.sh"
  cp ${./probot-render.py} "$out/probot-render.py"
  cp ${./probot-stage.py} "$out/probot-stage.py"
  cp ${./probot-guest-stage.sh} "$out/probot-guest-stage.sh"
  cp ${../coreos-services/probot-credentials.py} "$out/probot-credentials.py"
  cp ${../coreos-services/probot-redis-policy.py} "$out/probot-redis-policy.py"
  cp ${../scripts/render-users-acl.py} "$out/render-users-acl.py"
  cp ${../qualification/probot-webhook-sources.json} "$out/probot-webhook-sources.json"
  cp ${../acl-policy.json} "$out/acl-policy.json"
  printf '%s\\n' "${pkgs.python3}/bin/python3" > "$out/python-path"
  cp ${./bootstrap.sh} "$out/bootstrap.sh"
  cp ${../coreos-services/boot-wait.sh} "$out/boot-wait.sh"
  cp ${services}/metadata.json "$out/metadata.json"
''
