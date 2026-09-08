<p align="center">
  <img src="https://img.shields.io/badge/PortProtonQt-1.4.1-blue" alt="Version"/>
  <img src="https://img.shields.io/badge/NixOS-grey?logo=nixos" alt="NixOS"/>
  <img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="License"/>
  <a href="README.md"><img src="https://img.shields.io/badge/🇷🇺%20Русский-blue" alt="Русский"/></a>
</p>

# PortProtonQt for NixOS

A Nix flake to build **PortProtonQt** — a modern GUI (PySide6) for launching and
managing games from PortProton, Steam, Epic Games Store and GOG.

The package is built **from source** (meson + Python/C), not from an AppImage.

## What's inside

- `flake.nix` — the flake with our package and an overlay.
- `overlay.nix` — an overlay that adds `portprotonqt` to nixpkgs.
- `pkgs/portprotonqt/default.nix` — the derivation, pinned to the fixed `v1.4.1` release.

## Features

- GUI starts through an isolated `python3.withPackages` (all PySide6 and support deps).
- The native C gamepad module (SDL3) and the `vk_gpu_info` (Vulkan) utility are built via meson.
- **PortProton's bash engine** (`start.sh`) runs inside an **FHS environment** through
  `steam-run`, so that the dynamically compiled Wine/Proton builds downloaded by the
  app itself run correctly on NixOS.
- The data path is configured in the GUI/config, no source patching needed.

## Usage

### Run directly from the flake

```bash
nix run github:dark_siders/portprotonqt-nix
```

### Build

```bash
nix build .
```

### Use in your own config via overlay

Add this to your `flake.nix`:

```nix
{
  inputs = {
    portprotonqt-nix.url = "github:dark_siders/portprotonqt-nix";
  };

  outputs = { self, nixpkgs, portprotonqt-nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ portprotonqt-nix.overlays.default ];
      };
    in {
      packages.${system}.default = pkgs.portprotonqt;
    };
}
```

Inside `configuration.nix` / `home.nix`:

```nix
{ ... }: {
  environment.systemPackages = [ pkgs.portprotonqt ];
}
```

> **Note:** the package depends on `steam-run` and requires
> `config.allowUnfree = true;` (already set inside the flake itself).

## Caveats / known limitations

- **PortProtonQt's polkit rule is not installed.** The upstream build ships a polkit
  rule with a known vulnerability (see oss-security, July 2026), so the
  `share/polkit-1/rules.d` and `lib/sysusers.d` blocks are excluded from the install.
  If you really need polkit-level privileges, apply the rule deliberately and at your
  own risk.
- The build assumes a clean NixOS. The bash engine runs through `steam-run`, so the
  first Wine/Proton initialization may take noticeably longer.
- Tested on `x86_64-linux`.

## License

The wrapper package code (the `nix` expressions) is MIT. **PortProtonQt** itself is
distributed under the **GPL-3.0** license.