# overlays/terraform-overlay.nix
self: super: {
  terraform = self.stdenv.mkDerivation rec {
    pname = "terraform";
    version = "1.12.2";

    src = self.fetchurl {
      url = "https://releases.hashicorp.com/terraform/${version}/terraform_${version}_linux_amd64.zip";
      sha256 = "sha256-Hq7RLKQfz+CU2j12p+mqBjmtNAnEO+AQPun1of9LdDc=";
    };

    nativeBuildInputs = [ self.unzip ];

    unpackPhase = ''
      unzip $src
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp terraform $out/bin/
      chmod +x $out/bin/terraform
    '';

    meta = with self.lib; {
      description = "Terraform is an infrastructure as code tool";
      homepage = "https://www.terraform.io";
      license = licenses.mpl20;
      platforms = platforms.linux;
    };
  };
}
