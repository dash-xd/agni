self: super: {
  sops = self.stdenv.mkDerivation rec {
    pname = "sops";
    version = "3.10.2";

    src = self.fetchurl {
      url = "https://github.com/getsops/sops/releases/download/v${version}/sops-v${version}.linux.amd64";
      sha256 = "sha256-ebD4RCN71LBEbk3IhNvBdl/H3tw5aPdD1ZScby5wFzk=";
    };

    checksumsTxt = self.fetchurl {
      url = "https://github.com/getsops/sops/releases/download/v${version}/sops-v${version}.checksums.txt";
      sha256 = "sha256-BxoKk5yNnWhhl3McXCGszgw79YrX5shhkwt3QZs2Lxw=";
    };

    sig = self.fetchurl {
      url = "https://github.com/getsops/sops/releases/download/v${version}/sops-v${version}.checksums.sig";
      sha256 = "sha256-TOV1iC0m4E4N3fshgmk73XlSsV4HFl9UYQPbVfk5Jy4=";
    };

    pem = self.fetchurl {
      url = "https://github.com/getsops/sops/releases/download/v${version}/sops-v${version}.checksums.pem";
      sha256 = "sha256-MUNK8UKNaVxarJC9HWqbbySp58BBzHth3KbVS2c72RA=";
    };

    nativeBuildInputs = [
      self.coreutils
      self.curl
      self.gnupg
      self.cosign
      self.openssl
    ];

    unpackPhase = "true";

    buildPhase = ''
      export HOME=$(mktemp -d)

      cp ${checksumsTxt} sops-${version}.checksums.txt
      cp ${sig} sops-${version}.checksums.sig
      cp ${pem} sops-${version}.checksums.pem
      cp ${src} sops-v${version}.linux.amd64

      echo "✅ Verifying Cosign signature on checksums.txt..."
      cosign verify-blob sops-${version}.checksums.txt \
        --certificate sops-${version}.checksums.pem \
        --signature sops-${version}.checksums.sig \
        --certificate-identity-regexp=https://github.com/getsops \
        --certificate-oidc-issuer=https://token.actions.githubusercontent.com

      echo "✅ Verifying binary checksum..."
      sha256sum -c sops-${version}.checksums.txt --ignore-missing

      chmod +x sops-v${version}.linux.amd64
      mv sops-v${version}.linux.amd64 sops
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp sops $out/bin/
    '';

    meta = with self.lib; {
      description = "Secrets OPerationS - encrypted file manager (verified binary)";
      homepage = "https://github.com/getsops/sops";
      license = licenses.mpl20;
      platforms = [ "x86_64-linux" ];
    };
  };
}
