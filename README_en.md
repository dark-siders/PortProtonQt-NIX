<p align="center">
  <img src="assets/Logo.jpg" alt="PortProtonQt" width="60%"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/PortProtonQt-1.4.1--unreleased-20260908-blue" alt="Version"/>
  <img src="https://img.shields.io/badge/NixOS-grey?logo=nixos" alt="NixOS"/>
  <img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="License"/>
  <a href="README.md"><img src="https://img.shields.io/badge/🇷🇺%20Русский-blue" alt="Русский"/></a>
</p>

# PortProtonQt for NixOS

A Nix flake to build **PortProtonQt** — a modern GUI (PySide6) for launching and
managing games from PortProton, Steam, Epic Games Store and GOG.

The package is built **from source** (meson + Python/C), not from an AppImage.

## What's inside

- `flake.nix` — the flake with our package, an overlay and the checks (`checks`).
- `overlay.nix` — an overlay that adds `portprotonqt` to nixpkgs.
- `pkgs/portprotonqt/default.nix` — the derivation.

## Version

The package is built from **`main`, not from a release tag**: `main` carries NixOS
fixes that were not in the 1.4.1 release (2026-08-26). The version is therefore
honestly labelled `1.4.1-unreleased-20260908`, and the exact revision lives in
`passthru.upstreamCommit`. These changes are expected to land in the 1.5 release —
after that the pin can be moved to a tag.

## Features

- GUI starts through an isolated `python3.withPackages` (all PySide6 and support deps).
  No system `python3` in `PATH` is required — the interpreter comes from the nix store.
- The native C gamepad module (SDL3) and the `vk_gpu_info` (Vulkan) utility are built via meson.
- **PortProton's bash engine** (`start.sh`) runs inside an **FHS environment** through
  `steam-run`, so that the dynamically compiled Wine/Proton builds downloaded by the
  app itself run correctly on NixOS.
- The package is **self-contained in its utilities**: `sed`, `lsblk`, `pactl`, `xrandr`,
  `7z`, `cabextract`, `unrar`, `curl` and the rest come from its own closure rather
  than from the system `PATH`. The `steam-run` FHS does not provide some of them.
- The data path is configured in the GUI/config, no source patching needed.

## Usage

### Run directly from the flake

```bash
nix run gitlab:dark_siders/portprotonqt-nix
```

### Build

```bash
nix build .
```

## Checks

```bash
nix flake check
```

Three sets run:

| attribute | what it checks |
| --- | --- |
| `package` | the build itself plus `checkPhase`: every utility the engine and the GUI invoke directly is available in the closure |
| `package-tests` | python module imports (PySide6, the native gamepad module), `desktop-file-validate`, `appstreamcli validate`, the syntax of every bash script of the engine, and a CLI run in an empty environment (`env -i` with no system `PATH`) |
| `nixos` | a NixOS VM whose `systemPackages` contains only `portprotonqt` — no `python3`. Verifies that the package starts and that the utilities come from its own closure |

Fast run without the VM:

```bash
nix build .#checks.x86_64-linux.package .#checks.x86_64-linux.package-tests
```

### Use in your own config via overlay

Add this to your `flake.nix`:

```nix
{
  inputs = {
    portprotonqt-nix.url = "gitlab:dark_siders/portprotonqt-nix";
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

### Polkit privileges for wine — optional

Upstream fixed CVE-2026-59678 in 1.3.1: the polkit rule
`ru.linux_gaming.PortProtonQt.rules` no longer relies on a `ps` check, instead it
grants privileges only to members of the `portprotonqt` group. NixOS does not
create that group automatically, so to allow seamless disk mounting / NetworkManager
editing from the GUI, add:

```nix
users.groups.portprotonqt = { };
users.users.YOUR_USER.extraGroups = [ "portprotonqt" ];
```

Without this the polkit rule simply won't trigger (safe default); the app keeps
working.

## Caveats / known limitations

- The build assumes a clean NixOS. The bash engine runs through `steam-run`, so the
  first Wine/Proton initialization may take noticeably longer.
- `src` is built from `main`, not from a tag: `version` = `1.4.1-unreleased-20260908`.
  This is deliberate — 1.4.1 does not contain the NixOS fixes yet.
- The package is available for `x86_64-linux` only (`steam-run` does not build for
  other systems).
- The environment is not fully closed: `steam`, `flatpak` and `legendary`/`gogdl` for
  the Epic/GOG launchers are expected to be installed in the system — the package does
  not pull them in.
- `meta.maintainers` is empty: a maintainer has to be registered before the package
  can go into nixpkgs.

Detailed NixOS-specific notes (autoinstall, external launchers, FHS, data path) — in **[NIXOS_NOTES.md](NIXOS_NOTES.md)**.

## License

The wrapper package code (the `nix` expressions) is MIT. **PortProtonQt** itself is
distributed under the **GPL-3.0** license.