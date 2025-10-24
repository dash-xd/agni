self: super: {
  age = self.stdenv.mkDerivation rec {
    pname = "age";
    version = "1.1.1";

    src = self.fetchurl {
      url = "https://dl.filippo.io/age/v1.2.1?for=linux/amd64";
      sha256 = "sha256-ffRabMh9TaEcwDpTmnRwwVsQQasrOWrwiP6ZkPfHnVA=";
    };

    nativeBuildInputs = [ self.gnutar self.gzip ];

    unpackPhase = ''
      tar -xzf ${src}
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp age/age $out/bin/
    '';

    meta = with self.lib; {
      description = "A simple, modern and secure encryption tool with small explicit keys";
      homepage = "https://age-encryption.org";
      license = licenses.bsd3;
      platforms = platforms.linux;
    };
  };
}
