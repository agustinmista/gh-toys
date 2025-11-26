{
  stdenv,
  fetchurl,
  nodejs,
}:
stdenv.mkDerivation rec {
  pname = "copilot";
  version = "0.0.365";
  src = fetchurl {
    url = "https://registry.npmjs.org/@github%2fcopilot/-/copilot-${version}.tgz";
    hash = "sha256-T1dbgFGbhjZG2AXpPodOTiFEBuD5YhzmimD14NY87KU=";
  };
  buildInputs = [ nodejs ];
  dontBuild = true;
  unpackPhase = ''
    tar -xf $src # contains package/
    ls -la
  '';
  installPhase = ''
    mkdir -p $out/lib
    cp -r package/* $out/lib/

    mkdir -p $out/bin
    cat > $out/bin/copilot <<EOF
    #!/bin/sh
    exec node $out/lib/index.js "\$@"
    EOF
    chmod +x $out/bin/copilot
  '';
}
