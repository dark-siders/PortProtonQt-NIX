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

        # `nix flake check` прогоняет все три:
        #   package — сборка + checkPhase (наличие утилит в замыкании);
        #   package-tests — импорты, desktop/metainfo, синтаксис движка и
        #                 запуск CLI в пустом окружении на собранном $out;
        #   nixos — NixOS VM без python3 и util-linux в systemPackages.
        # Быстрый прогон без VM: nix build .#checks.x86_64-linux.package{,-tests}
        checks = {
          package = self.packages.${system}.portprotonqt;
          package-tests = self.packages.${system}.portprotonqt.tests.package;
          nixos = self.packages.${system}.portprotonqt.tests.nixos;
        };
      }
    )
    // {
      overlays.default = import ./overlay.nix;
    };
}
