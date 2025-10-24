self: super: {
  s6-overlay-noarch = self.stdenv.mkDerivation rec {
    pname = "s6-overlay-noarch";
    version = "3.2.1.0";

    src = self.fetchurl {
      url = "https://github.com/just-containers/s6-overlay/releases/download/v${version}/s6-overlay-noarch.tar.xz";
      sha256 = "sha256-QuA4qaAPwP73C/C8QvYlqcFPjs3+d9Stkyge33F+EMU=";
    };

    dontUnpack = true;
    dontBuild = true;

    installPhase = ''
      mkdir -p $out
      cp $src $out/s6-overlay-noarch.tar.xz
    '';

    meta = with self.lib; {
      description = "s6-overlay (noarch component)";
      homepage = "https://github.com/just-containers/s6-overlay";
      license = licenses.mit;
      platforms = platforms.all;
    };
  };

  s6-overlay-x86_64 = self.stdenv.mkDerivation rec {
    pname = "s6-overlay-x86_64";
    version = "3.2.1.0";

    src = self.fetchurl {
      url = "https://github.com/just-containers/s6-overlay/releases/download/v${version}/s6-overlay-x86_64.tar.xz";
      sha256 = "sha256-i8vCytpYQm+XaxWdzE4Gy7FFTV85JSs7sMd4zPcclDU=";
    };

    dontUnpack = true;
    dontBuild = true;

    installPhase = ''
      mkdir -p $out
      cp $src $out/s6-overlay-x86_64.tar.xz
    '';

    meta = with self.lib; {
      description = "s6-overlay (x86_64 component)";
      homepage = "https://github.com/just-containers/s6-overlay";
      license = licenses.mit;
      platforms = [ "x86_64-linux" ];
    };
  };
}
