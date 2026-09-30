<p align="center">
  <img src="assets/Logo.jpg" alt="PortProtonQt" width="60%"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/PortProtonQt-1.4.1-blue" alt="Version"/>
  <img src="https://img.shields.io/badge/NixOS-unstable-yellow?logo=nixos" alt="NixOS"/>
  <img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="License"/>
  <a href="README.md"><img src="https://img.shields.io/badge/🇷🇺%20Русский-blue" alt="Russian"/></a>
</p>

# PortProtonQt for NixOS

A Nix flake that builds **PortProtonQt** — a PySide6 graphical interface for
launching and managing games from PortProton, Steam, Epic Games Store and GOG.

Built **from upstream sources** via Meson. No AppImage involved.

## Quick start

```bash
nix run gitlab:dark_siders/portprotonqt-nix
```

or from a clone of this repository:

```bash
nix run .#portproton
```

Build:

```bash
nix build .
./result/bin/portprotonqt
```

## What is inside

The whole package is a single `flake.nix` file. There are no separate
derivations, overlays or `pkgs/` directories: the package is built from the
`portprotonqt-src` input, which pulls the official upstream repository.

| | |
| --- | --- |
| Source | `git+https://git.linux-gaming.ru/Linux-Gaming/PortProtonQt`, branch `main` |
| Pinned revision | `flake.lock` (`portprotonqt-src`) |
| Build | Meson + Nix, version `1.4.1` |
| Python | `python313.withPackages` with the full dependency set |
| FHS layer | `steam-run` |

## Version

The package is built from the **`main` branch, not a release tag**: the version
in the derivation is `1.4.1`, but the sources are always current. The exact
revision is pinned in `flake.lock`. This way upstream NixOS fixes are picked up
immediately, without waiting for the next release.

## How it works

PortProtonQt is not just a GUI. It also pulls in and runs the **PortProton
bash engine** (`start.sh`), which downloads Wine/Proton and launches games. That
engine needs an ordinary FHS system with glibc, bash and system utilities, none
of which NixOS provides.

That is why the package runs through **`steam-run`** — an FHS environment based
on bubblewrap that is already available in nixpkgs. Nothing hand-rolled: a custom
FHS build is not needed, `steam-run` covers everything required.

## NixOS fixes

Upstream does not officially support NixOS, so three things have to be fixed in
`postInstall`. The details are in **[NIXOS_NOTES.md](NIXOS_NOTES.md)**.

1. **Absolute interpreter in the engine scripts.** `steam-run` exposes a `PATH`
   inside the sandbox where `python3` is a foreign interpreter from the FHS
   image. It picks up pure-Python modules like `babel`, but fails to load
   compiled ones (`orjson`, `pyside6`) because the ABI tag differs. An absolute
   path to the env interpreter is substituted into every
   `python3 -m portprotonqt...` call.
2. **`kill_portwine` guard.** The function looks for bwrap via
   `pgrep -f wrap | grep PortProton` and sends `kill -n 9`. Under `steam-run`
   that bwrap *is* the session's own container, and it carries
   `--die-with-parent`, so everything died with SIGKILL (exit code 137) before the
   game even started. bwrap PIDs that are ancestors of the current shell are
   dropped from the kill list.
3. **Strict substitution checks.** If upstream renames its calls or moves the
   anchor in `functions_helper`, the build fails with a clear error instead of
   breaking silently for the user.

No source-level Python patches — everything happens at the level of the
installed scripts.

## Checks

```bash
nix flake check
```

| attribute | what it checks |
| --- | --- |
| `package` | the build itself |
| `cli` | the wrapper calls `steam-run` and sets `PYTHONPATH`; the engine scripts contain no bare `python3 -m portprotonqt` calls; the `kill_portwine` guard is in place; `bash -n` passes for both scripts; the CLI prints its help; `orjson` and `babel` import under the same interpreter the engine helpers are called with |

Running a single check:

```bash
nix build .#checks.x86_64-linux.cli
```

## Using it in your own config

Via inputs (recommended):

```nix
{
  inputs = {
    portprotonqt-nix.url = "gitlab:dark_siders/portprotonqt-nix";
  };

  outputs = { nixpkgs, portprotonqt-nix, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ modulesPath, ... }: {
          imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
          nixpkgs.overlays = [ portprotonqt-nix.overlays.default ];
          environment.systemPackages = [ pkgs.portprotonqt ];
        })
      ];
    };
  };
}
```

Or directly in a flake config:

```nix
{
  inputs.portprotonqt-nix.url = "gitlab:dark_siders/portprotonqt-nix";
  # ...
  nixpkgs.overlays = [ inputs.portprotonqt-nix.overlays.default ];
  environment.systemPackages = [ pkgs.portprotonqt ];
}
```

> **Note:** the package depends on `steam-run` (proprietary), so
> `nixpkgs.config.allowUnfree = true;` is required — it is already set in this
> flake.

## Wine permissions (polkit) — optional

Upstream closed CVE-2026-59678 in 1.3.1: the polkit rule
`ru.linux_gaming.PortProtonQt.rules` no longer relies on inspecting `ps` and
instead grants privileges only to members of the `portprotonqt` group. NixOS does
not create that group automatically. If you want seamless disk mounting and
NetworkManager edits straight from the GUI, add:

```nix
users.groups.portprotonqt = { };
users.users.YOUR_USER.extraGroups = [ "portprotonqt" ];
```

Without this the polkit rule simply will not fire (a safe default) and the
application keeps working.

## Limitations

- `x86_64-linux` only: `steam-run` does not build for other systems.
- The first Wine/Proton initialisation takes noticeably longer than usual: the
  engine downloads distributions and compiles modules inside the FHS
  environment.
- The package tracks upstream's `main` branch rather than a tag, so surprises are
  possible when `flake.lock` is updated. The pinned revision is always in
  `flake.lock`.
- `legendary` is absent from nixpkgs and is not included in the closure. Install
  it separately if you need it for the Epic Games Store.
- The PortProton data path is set in the GUI or via `PORT_DATA_PATH`. No personal
  paths are hardcoded in the flake.
- `meta.maintainers` is empty — a maintainer has to be appointed before this can
  go into nixpkgs.

## License

The flake expressions are MIT. **PortProtonQt** itself is distributed under the
**GPL-3.0** license.
