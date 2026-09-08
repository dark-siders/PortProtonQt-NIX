{
  description = "PortProtonQt packaged for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachSystem [
      "x86_64-linux"
    ] (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ self.overlays.default ];
        };
      in {
        packages = {
          default = pkgs.portprotonqt;
          portprotonqt = pkgs.portprotonqt;
        };

        overlays.default = self.overlays.default;

        checks = {
          inherit (self.packages.${system}) portprotonqt;
        };
      }
    )
    // {
      overlays.default = import ./overlay.nix;
    };
}
