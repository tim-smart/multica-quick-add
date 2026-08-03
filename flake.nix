{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };
  outputs = {nixpkgs, ...}: let
    darwinSystems = ["aarch64-darwin" "x86_64-darwin"];
    forAllSystems = function:
      nixpkgs.lib.genAttrs darwinSystems (
        system: function nixpkgs.legacyPackages.${system}
      );
  in {
    formatter = forAllSystems (pkgs: pkgs.alejandra);
    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShellNoCC {
        packages = [
          (pkgs.writeShellScriptBin "xcodegen" ''
            exec ${pkgs.xcodegen}/bin/xcodegen "$@"
          '')
        ];
        shellHook = ''
          export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
          unset AR AS CC CXX DEVELOPER_DIR LD MACOSX_DEPLOYMENT_TARGET SDKROOT
          unset NIX_BINTOOLS NIX_CC NIX_CFLAGS_COMPILE NIX_LDFLAGS
        '';
      };
    });
  };
}
