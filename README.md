<p align="center">
  <img src="assets/Logo.jpg" alt="PortProtonQt" width="60%"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/PortProtonQt-1.4.1-blue" alt="Версия"/>
  <img src="https://img.shields.io/badge/NixOS-grey?logo=nixos" alt="NixOS"/>
  <img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="Лицензия"/>
  <a href="README_en.md"><img src="https://img.shields.io/badge/🇬🇧%20English-blue" alt="English"/></a>
</p>

# PortProtonQt for NixOS

Nix-флейк для сборки **PortProtonQt** — современного GUI (PySide6) для запуска и
управления играми из PortProton, Steam, Epic Games Store и GOG.

Пакет собирается **из исходников** (meson + Python/C), а не из AppImage.

## Что внутри

- `flake.nix` — флейк с нашим пакетом и overlay.
- `overlay.nix` — overlay, добавляющий `portprotonqt` в nixpkgs.
- `pkgs/portprotonqt/default.nix` — derivation, пин на зафиксированный релиз `v1.4.1`.

## Возможности

- Запуск GUI через изолированный `python3.withPackages` (все зависимости PySide6 и поддержки).
  Системный `python3` в `PATH` не требуется — интерпретатор берётся из nix-store.
- Нативный C-модуль геймпада (SDL3) и утилита `vk_gpu_info` (Vulkan) собираются через meson.
- **Bash-движок PortProton** (`start.sh`) исполняется внутри **FHS-окружения** через
  `steam-run`, чтобы динамически скомпилированные сборки Wine/Proton, которые
  скачивает само приложение, корректно запускались на NixOS.
- Путь к данным настраивается в GUI/конфиге, патчить исходники не нужно.

## Использование

### Запуск напрямую из флейка

```bash
nix run gitlab:dark_siders/portprotonqt-nix
```

### Сборка

```bash
nix build .
```

### Подключение в собственный конфиг через overlay

Добавьте в `flake.nix`:

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

Внутри `configuration.nix` / `home.nix`:

```nix
{ config, pkgs, ... }: {
  environment.systemPackages = [ pkgs.portprotonqt ];
}
```

> **Примечание:** пакет зависит от `steam-run` и требует `config.allowUnfree = true;`
> (в самом флейке уже задано).

### Права для wine (polkit) — опционально

Апстрим закрыл CVE-2026-59678 в 1.3.1: polkit-правило
`ru.linux_gaming.PortProtonQt.rules` больше не полагается на проверку `ps`, а
даёт привилегии только членам группы `portprotonqt`. На NixOS эта группа не
создаётся системой автоматически, поэтому, если хотите разрешить бесшовное
монтирование дисков / правку NetworkManager прямо из GUI, добавьте:

```nix
users.groups.portprotonqt = { };
users.users.YOUR_USER.extraGroups = [ "portprotonqt" ];
```

Без этой настройки группы polkit-правило просто не сработает (безопасный
дефолт), приложение продолжит работать.

## Нюансы / известные ограничения

- Сборка предполагает чистый NixOS. Bash-движок запускается через `steam-run`, из-за
  чего первая инициализация Wine/Proton может занять заметно больше времени.
- Протестировано на `x86_64-linux`.

## Лицензия

Код пакета обёртки (`nix`-выражения) — MIT. Сам **PortProtonQt** распространяется
под лицензией **GPL-3.0**.
