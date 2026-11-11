{ pkgs }:
let services = import ../coreos-services { inherit pkgs; };
in pkgs.runCommand "agni-fatline-startup-profile-v1" {} ''
  mkdir -p "$out"
  cp ${./render.py} "$out/render.py"
  cp ${./runtime.sh} "$out/runtime.sh"
  cp ${./bootstrap.sh} "$out/bootstrap.sh"
  cp ${../coreos-services/boot-wait.sh} "$out/boot-wait.sh"
  cp ${services}/metadata.json "$out/metadata.json"
''
