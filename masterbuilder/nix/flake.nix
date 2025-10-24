{
  description = "Unified flake providing both a portable static environment and PKI tool tarball.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/d31a91c9b3bee464d054633d5f8b84e17a637862";
    flake-utils.url = "github:numtide/flake-utils";
    workingDir.url = "path:/home/cloudsdk/nix-devops";
  };

  outputs = { self, nixpkgs, flake-utils, workingDir, ... }:
    let
      overlaysList = [
        (import ./overlays/sops-overlay.nix)
        (import ./overlays/age-overlay.nix)
        (import ./overlays/terraform-overlay.nix)
        (import ./overlays/s6-overlay.nix)
      ];
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = overlaysList;
        };

        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          ansible-core
          google-auth
          google-auth-httplib2
          google-api-python-client
          grpcio
        ]);

        staticTools = pkgs.buildEnv {
          name = "portable-static-tools";
          paths = [
            pkgs.sops
            pkgs.age
            pkgs.terraform
            pkgs.s6-overlay-noarch
            pkgs.s6-overlay-x86_64
            pkgs.mkcert
            pkgs.socat
            pythonEnv
          ];
        };

        pkiTools = [
          pkgs.sops
          pkgs.age
          pkgs.mkcert
          pkgs.terraform
          pkgs.butane
          pkgs.socat
        ];

        pkiTarball = pkgs.runCommandLocal "pki-tools.tar.gz" {
          nativeBuildInputs = [ pkgs.gnutar pkgs.coreutils ];
        } ''
          mkdir -p work/bin

          for tool in ${toString pkiTools}; do
            for bin in "$tool/bin/"*; do
              install -Dm755 "$bin" "work/bin/$(basename "$bin")"
            done
          done

          tar -czf pki-tools.tar.gz -C work .
          install -m644 pki-tools.tar.gz $out
        '';
      in {
        packageSet = pkgs;
        overlays = overlaysList;
        packages.default = staticTools;
        packages.pki-tools = pkiTarball;
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.sops
            pkgs.age
            pkgs.terraform
            pkgs.s6-overlay-noarch
            pkgs.s6-overlay-x86_64
            pkgs.mkcert
            pkgs.socat
            pythonEnv
          ];

          shellHook = ''
            export ANSIBLE_COLLECTIONS_PATH="$PWD/.ansible/collections"
            echo "✅ Ansible with GCP support ready."
            echo "📦 Using Python: $(which python3)"
            echo "📦 Ansible path: $(which ansible)"
            echo "You may now run: ansible-galaxy collection install google.cloud"
          '';
        };
      }
    );
}
