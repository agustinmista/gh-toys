{
  description = "Collection of small scripts built around GitHub CLI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;

        forEachSubdir =
          dir: f:
          let
            subdirs = lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir);
          in
          lib.mapAttrs (name: _: f (dir + "/${name}")) subdirs;

        scripts = forEachSubdir ./. (subdir: pkgs.callPackage subdir { });
        allScripts = pkgs.symlinkJoin {
          name = "gh-toys";
          paths = lib.attrValues scripts;
        };

      in
      {
        packages = scripts // {
          default = allScripts;
        };
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.gh
            allScripts
          ];
        };
      }
    );
}
