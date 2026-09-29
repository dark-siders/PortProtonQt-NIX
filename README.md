<p align="center">
  <img src="assets/Logo.jpg" alt="PortProtonQt" width="60%"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/PortProtonQt-1.4.1--unreleased-20260908-blue" alt="Версия"/>
  <img src="https://img.shields.io/badge/NixOS-grey?logo=nixos" alt="NixOS"/>
  <img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="Лицензия"/>
  <a href="README_en.md"><img src="https://img.shields.io/badge/🇬🇧%20English-blue" alt="English"/></a>
</p>

# PortProtonQt for NixOS

Nix-флейк для сборки **PortProtonQt** — современного GUI (PySide6) для запуска и
управления играми из PortProton, Steam, Epic Games Store и GOG.

Пакет собирается **из исходников** (meson + Python/C), а не из AppImage.

## Что внутри

- `flake.nix` — флейк с нашим пакетом, overlay и проверками (`checks`).
- `overlay.nix` — overlay, добавляющий `portprotonqt` в nixpkgs.
- `pkgs/portprotonqt/default.nix` — derivation.

## Версия

Пакет собирается **не с тега releases, а с `main`**: в `main` есть NixOS-фиксы,
которых в релиз 1.4.1 (2026-08-26) ещё не было. Поэтому версия честно помечена
как `1.4.1-unreleased-20260908`, а точная ревизия лежит в
`passthru.upstreamCommit`. Ожидается, что эти изменения войдут в релиз 1.5 —
после него пин можно будет перевести на тег.

## Возможности

- Запуск GUI через изолированный `python3.withPackages` (все зависимости PySide6 и поддержки).
  Системный `python3` в `PATH` не требуется — интерпретатор берётся из nix-store.
- Нативный C-модуль геймпада (SDL3) и утилита `vk_gpu_info` (Vulkan) собираются через meson.
- **Bash-движок PortProton** (`start.sh`) исполняется внутри **FHS-окружения** через
  `steam-run`, чтобы динамически скомпилированные сборки Wine/Proton, которые
  скачивает само приложение, корректно запускались на NixOS.
- Пакет **самодостаточен по утилитам**: `sed`, `lsblk`, `pactl`, `xrandr`, `7z`,
  `cabextract`, `unrar`, `curl` и прочее берутся из его замыкания, а не из
  системного `PATH`. FHS `steam-run` часть из них не содержит.
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

## Проверки

```bash
nix flake check
```

Прогоняются три набора:

| атрибут | что проверяет |
| --- | --- |
| `package` | сама сборка + `checkPhase`: все утилиты, которые движок и GUI зовут напрямую, доступны в замыкании |
| `package-tests` | импорт python-модулей (PySide6, нативный модуль геймпада), `desktop-file-validate`, `appstreamcli validate`, синтаксис всех bash-скриптов движка и запуск CLI в пустом окружении (`env -i` без системного `PATH`) |
| `nixos` | NixOS VM, где в `systemPackages` лежит только `portprotonqt` — без `python3`. Проверяет, что пакет стартует и что утилиты приходят из его замыкания |

Быстрый прогон без VM:

```bash
nix build .#checks.x86_64-linux.package .#checks.x86_64-linux.package-tests
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
- `src` собирается с `main`, а не с тега: `version` = `1.4.1-unreleased-20260908`.
  Это осознанно — релизных NixOS-правок в 1.4.1 ещё нет.
- Пакет доступен только для `x86_64-linux` (`steam-run` не собирается под другие системы).
- Полное закрытое окружение: `steam`, `flatpak`, `legendary`/`gogdl` для лаунчеров
  Epic/GOG ожидаются установленными в системе — пакет их не тянет.
- `meta.maintainers` пуст: для попадания в nixpkgs нужно завести maintainer.

Подробные NixOS-нюансы (автоинсталл, внешние лаунчеры, FHS, путь данных) — в **[NIXOS_NOTES.md](NIXOS_NOTES.md)**.

## Лицензия

Код пакета обёртки (`nix`-выражения) — MIT. Сам **PortProtonQt** распространяется
под лицензией **GPL-3.0**.
