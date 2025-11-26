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

      in
      {
        packages = forEachSubdir ./. (subdir: pkgs.callPackage subdir { });
      }
    );
}
