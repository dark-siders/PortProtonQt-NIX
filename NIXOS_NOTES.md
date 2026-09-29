# NixOS-специфичные нюансы PortProtonQt

> Этот файл описывает отличия NixOS-сборки от официального AppImage и известные проблемы.

---

## Автоинсталл (.ppai скрипты) — не работает

**Симптом:** автоинсталл стартует, пишет `The first mirror in used: CLOUD`, затем процесс умирает с кодом 137 (SIGKILL).

**Причина:** функция движка `kill_portwine()` (в `functions_helper`) ищет bwrap-процессы, в командной строке которых есть «PortProton», и убивает их `kill -9`. Внутри `steam-run` (FHS) автоинсталл запускается в собственном bwrap-контейнере, у которого в cmdline есть «PortProton» → движок убивает сам контейнер.

На Fedora с официальным AppImage этой проблемы нет — там нативное окружение, без `steam-run`.

**Обходной путь:** используй вкладку **Загрузки** → вход в Epic Games Store (требует `legendary` в `systemPackages`) → установка игр из библиотеки. Автоинсталл для этого не нужен.

---

## Внешние лаунчеры (обязательно в systemPackages)

| Функция | Нужен бинарник | В nixpkgs 26.05 |
|---------|----------------|-----------------|
| Epic Games Store (вкладка Загрузки) | `legendary` | ❌ нет (собирать из исходников или использовать `heroic`) |
| GOG (вкладка Загрузки) | `gogdl` | ✅ `gogdl` |

> В пакете эти бинарники **не включены** — они ожидаются в системном окружении. Для GOG достаточно `environment.systemPackages = [ pkgs.gogdl ];`. Для Epic — собрать `legendary` самому или поставить `heroic` (в нём есть `legendary` как библиотека, но CLI-бинарник отдельного пакета в nixpkgs нет).

---

## Путь данных PortProton

Настраивается в `~/.config/PortProtonQt.conf`:

```ini
portdata_path = /media/DataLinux/PortProton # На отдельном диске
```

- Директория должна быть на **записываемом** разделе (не в `/nix/store`).
- В примере используется `/media/DataLinux`. Если раздел не смонтирован — PortProton не запустится.
---

## FHS-окружение (steam-run)

Bash-движок PortProton запускается через `steam-run` (FHS-контейнер на базе arch). Это означает:

- Внутри FHS **нет** `/usr/bin/env python3` — обёртка прописывает интерпретатор из nix-store (`postInstall`).
- Некоторые утилиты отсутствуют в FHS: `sed`, `lsblk`, `pactl`, `xrandr`, `which` — они добавлены в `runtimeBins` пакета и проброшены в PATH обёртки.
- `/tmp` внутри FHS — свой tmpfs. Автоинсталл скачивал `.ppai` в `/tmp/PortProtonQt/autoinstall/` — файл был невидим. Исправлено патчем: кэш теперь в `$HOME/.cache/PortProtonQt/autoinstall/` (видно внутри FHS, так как `$HOME` монтируется).

---

## Версия и источник

- Пакет собирается с **upstream main** (коммит `f1a5db4f` — «fix: use XDG data paths on NixOS»), а не с тега `v1.4.1`.
- Версия: `1.4.1-unreleased-20260929`.
- Точная ревизия в `passthru.upstreamCommit`.
- Ожидается, что изменения попадут в релиз 1.5 — тогда пин можно будет перевести на тег.

---

## Проверки (nix flake check)

Три набора проверок:

| атрибут | что проверяет |
|---------|---------------|
| `package` | сборка + `checkPhase`: 23 утилиты доступны в замыкании |
| `package-tests` | импорты python (PySide6, нативный геймпад), `desktop-file-validate`, `appstreamcli validate`, синтаксис bash-скриптов движка, запуск CLI в пустом окружении (`env -i`) |
| `nixos` | NixOS VM: в `systemPackages` только `portprotonqt` (нет `python3`, `util-linux`). Проверяет, что пакет стартует и утилиты приходят из замыкания |

Быстрый прогон без VM:
```bash
nix build .#checks.x86_64-linux.package .#checks.x86_64-linux.package-tests
```

---

## Известные ограничения

- **Автоинсталл** — см. выше (баг движка + steam-run).
- **legendary** отсутствует в nixpkgs — для вкладки Epic нужно вручную добавить в систему.
- Пакет только для `x86_64-linux` (steam-run не собирается под другие arch).
- `meta.maintainers` пуст — для попадания в nixpkgs нужен зарегистрированный maintainer.
- `~/PortProtonQt` может быть пустым — данные в `portdata_path` (см. выше).
