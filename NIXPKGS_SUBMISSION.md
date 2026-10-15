# Добавление PortProtonQt в официальный nixpkgs: план

Пошаговый план внесения пакета в `NixOS/nixpkgs`. Документ самодостаточный:
все факты ниже проверены и не требуют повторного ресёрча.

> **Статус (2026-10-15):** тег **v1.5.0** вышел (2026-10-14). Отправная точка —
> тег `v1.5.0`, а не текущая ветка `main`.
>
> **Этап A закрыт, идёт этап B.** Флейк уже обновлён под 1.5.0
> (`version = "1.5.0"`, `qrcode` добавлен). Дальше — B → C без пауз.
>
> - ✅ **A1** — GitHub-аккаунт готов: `dark-siders`, `githubId 29074260`
> - ✅ **A2** — срок релиза подтверждён апстримом (письмо писать не нужно)
> - ✅ **A3** — слежка за тегами: тег v1.5.0 вышел (проверка 2026-10-14)
> - ✅ **A4** — `qrcode` добавлен в `python313.withPackages` во флейке (flake.nix)
> - ⬜ **A5** — черновик `package.nix` (необязательно, делается на этапе B)
>
> **Текущая фаза:** переход к этапу B по «runbook дня X» ниже. Дальше A5 → B → C.

## Цель

Пакет `pkgs.portprotonqt` в официальном nixpkgs, собираемый из исходников
апстрима, работоспособный на NixOS и **без `allowUnfree`**.

---

## Часть 0. Runbook дня X: тег вышел, что делать

Короткий порядок действий. Детали — в частях 3 и 4. Тег вышел — это активный
порядок действий.

1. Проверить тег и поставить хеш (≈1 мин):

   ```bash
   curl -s https://git.linux-gaming.ru/api/v1/repos/Linux-Gaming/PortProtonQt/tags | head -c 400
   nix-prefetch-url --type sha256 \
     "https://git.linux-gaming.ru/Linux-Gaming/PortProtonQt/archive/v1.5.0.tar.gz"
   # результат: 0s1hww98zc47ghfwj28nwj98k32rhhqgv9bb2slpf0lwsb5p14m0
   ```

2. Развернуть nixpkgs (≈5 мин): shallow-клон `master` в
   `/tmp/opencode/nixpkgs`, remote `upstream`, ветка `portprotonqt-init`.
3. **Сверка релиза** — пункт B3. Это единственное место, где могут вылезти
   неожиданности (udev-правило, новые Python-зависимости, смена meson-опций).
4. Написать `pkgs/by-name/po/portprotonqt/package.nix` по пунктам B5–B10.
   Первое, что ломается по дороге, — `-Dpython_purelibdir`: без него meson
   определит purelib через `sysconfig` интерпретатора и полезет писать в
   read-only store-путь.
5. Заменить `pkgs.steam-run` на `steam.run-free` и **локально проверить
   запуск GUI и движка** — пункт B4. Это риск номер один по объёму
   неизвестного: смена unfree-FHS на free-FHS требует ручной проверки.
6. Тесты (B11), `nix fmt`, `nixpkgs-review wip`.
7. Коммиты и PR — часть 4.

Оценка: 1–3 дня работы, если смена FHS идёт без сюрпризов.

**Принцип порядка:** сначала пакет собирается в nixpkgs, потом наш флейк
переводится на него же (или удаляется в пользу `pkgs.portprotonqt` из
nixpkgs). Решение по флейку принимается отдельно, после мержа.

---

## Часть 1. Проверенные факты

Этот раздел не перепроверять на каждом шаге — он собран один раз и остаётся
актуальным. Что нужно перепроверять явно, помечено в этапе B (пункт B3).

### 1.1 Стартовая позиция

| | |
| --- | --- |
| В nixpkgs пакета нет | PR по `portprotonqt` никогда не существовало, атрибута `pkgs.portprotonqt` нет |
| Прецедент в других дистрибутивах | Void Linux (`Event-Horizon-VL/blackhole-vl`) |
| Апстрим | `https://git.linux-gaming.ru/Linux-Gaming/PortProtonQt` — self-hosted Gitea организации Linux-Gaming |
| Теги | С префиксом `v`. Последний на момент проверки — `v1.5.0` (2026-10-14) |

### 1.2 Источник

```nix
src = fetchurl {
  url = "https://git.linux-gaming.ru/Linux-Gaming/PortProtonQt/archive/v${version}.tar.gz";
  hash = "…";
};
```

- В архиве **один** top-level каталог `portprotonqt/` — `unpackPhase` снимет его
  сам, `stripRoot` не нужен.
- Для `v1.4.1` sha256 = `sha256-McJXkNE+cosorh3iZ4imVj0A5pbWxnwEaZ+M5PSqih0=`
  (совпал с контрольной суммой из Void Linux, то есть tarball воспроизводим).
- Для 1.5 пересчитать: `nix-prefetch-url --type sha256 <url>`.
- Эндпоинт `archive/` не закрыт анти-ботом (Anubis) — проверено, скачивание
  работает. Закрыты только HTML-страницы.

### 1.3 NixOS-фиксы — главная деталь

Правки, без которых на NixOS ничего не запускается, живут в ветке `main`:

- коммит `e25b52f3d5ad5c8fdc7ae4a20038b1301441e9e7`
- заголовок: `fix: support game launches inside steam-run`
- автор: Boris Yumankulov; в `CHANGELOG.md` добавлен соавтор `@dark_siders`
- объём: 3 файла, +23/−10

Что именно:

| Файл | Правка |
| --- | --- |
| `portprotonqt/app.py` | `os.environ["PORTPROTONQT_PYTHON"] = sys.executable` |
| `build-aux/share/portproton/scripts/start.sh` | `${PORTPROTONQT_PYTHON:-python3}` вместо голого `python3` |
| `build-aux/share/portproton/scripts/functions_helper` | то же в `python_module`, `PW_INHIBIT_SLR`, `PW_TERM`; плюс guard `pw_ancestor_pid` в `kill_portwine`, отбрасывающий предков текущего шелла из списка на `kill -9` |

Смысл: `steam-run` перетирает `PATH`, и `python3` внутри песочницы — чужой
интерпретатор из FHS-образа. Он подхватывает чистые модули с нашего
`PYTHONPATH`, но не грузит скомпилированные (`orjson`, `pyside6`) — не
совпадает ABI-тег. Второй правкой `kill_portwine` искал bwrap через
`pgrep -f wrap | grep PortProton` и убивал **собственный контейнер сессии**,
а у того стоит `--die-with-parent`, поэтому всё падало с SIGKILL (код 137).

**В теге `v1.4.1` этих правок не было** — они вошли в `v1.5.0`. Подробности — в
`NIXOS_NOTES.md`.

Состояние ветки `main` на момент, когда ждали релиз: **163 коммита** после
`v1.4.1`, `[Unreleased]` заполнен (Epic-интеграция, Proton CachyOS WineLand,
реорганизация библиотеки, `$XDG_DATA_HOME/PortProtonQt/{cache,launcher,bin}`,
Python ≥3.11). Отсюда и решение было: ждать 1.5, а не паковать 1.4.1 с патчем.
Теперь `v1.5.0` вышел — эти правки в релизе.

Проверено на v1.4.1 как запасной вариант: патч `e25b52f3` применяется
(`functions_helper` — 7 хунков, `start.sh`, `app.py`), падают только два хунка
в `CHANGELOG.md`. Если 1.5 не выйдет, вариант с патчем технически возможен
через `fetchpatch2 { excludes = [ "CHANGELOG.md" ]; }`.

### 1.4 unfree-зависимость — как снимается

| | |
| --- | --- |
| Сейчас в нашем флейке | `pkgs.steam-run` — это `steam.run`, лицензия unfree |
| Свободная альтернатива | `(steam.override { … }).run-free` |
| Чем отличается | та же FHS на `buildFHSEnv`, но **без** `steam-unwrapped`; `license = lib.licenses.mit` |
| Прецедент в nixpkgs | `pkgs/by-name/pr/protontricks/package.nix` — ровно этот приём; `pkgs/by-name/it/itch/package.nix` — `makeWrapper` поверх `steam-run` |
| Что это даёт | пакет становится **free**: `allowUnfree` не нужен, ofborg его собирает, а не пропускает |

Что уже есть в базе `run-free` (то, что `steam` кладёт в FHS по умолчанию):
`bash`, `coreutils`, `file`, `lsb-release`, `pciutils`, `usbutils`, `xdg-utils`,
`xz`, `zenity`, плюс библиотеки steamrt (`glibc`, `libxcrypt`, `libGL`,
`libdrm`, `libgbm`, `udev`, `libva`, `vulkan-loader`, `networkmanager`, `libcap`).

Своя FHS-сборка не нужна — `steam.run-free` умеет всё требуемое.

### 1.5 Сборка

| | |
| --- | --- |
| Meson-опции | `python_purelibdir`, `udev_rulesdir`, `nightly` (по умолчанию `false`). Набор **одинаков** и в `v1.4.1`, и в `main` |
| Цели установки | udev-правило, MIME-xml, polkit-правило, sysusers — тоже **одинаковы** в `v1.4.1` и `main` |
| Обязательные зависимости | `msgfmt` → `gettext` (жёстко, `find_program('msgfmt', required: true)`), `sdl3`, `vulkan`, `pkg-config` |
| Python | в nixpkgs `python3` = 3.13.15; в 1.5 `requires-python >= 3.11` — подходит |
| Python-модули | все нужные есть в `python3Packages` (проверено: `pyside6`, `shiboken6`, `orjson`, `babel`, `dbus-fast`, `pillow`, `vdf`, `requests`, `tqdm`, `pefile`, `websocket-client`, `psutil`, `evdev`, `libarchive-c`, `rapidfuzz`, `qrcode`) |
| Нужны вручную | генерация комплишенов: `bash dev-scripts/generate-completions.sh` (в tarball отсутствуют, генерируются в дереве исходников) |

### 1.6 Требования nixpkgs

Путь: `pkgs/by-name/po/portprotonqt/package.nix`.

Обязательно:

- `meta.description` — короткое предложение, с заглавной буквы, **без имени
  пакета**, без точки в конце, без оценочных прилагательных
- `meta.license = lib.licenses.gpl3Only` (meson: `license: 'GPL-3.0'`)
- `meta.maintainers` — непустой, иначе пакет не примут
- `meta.platforms` — иначе не будет бинарных сабститутов
- `meta.mainProgram = "portprotonqt"`
- Форматирование `nixfmt` — CI валит без него

Рекомендуется / проверяется ревьюером:

- `passthru.updateScript = nix-update-script { }`
- `passthru.tests` — тесты пакета
- Не переопределять список `phases`; переопределяя фазу — начинать с
  `runHook preX` и кончать `runHook postX`
- Каждый недефолтный флаг, патч и `substituteInPlace` — с комментарием **зачем**
- Патчи, доступные удалённо, — `fetchpatch2`, а не вендоринг в репозиторий
- Функция пакета — с точным списком аргументов, без `with args;`, имена
  переменных в lowerCamelCase

### 1.7 Формат коммитов и PR

- Коммит 1: `maintainers: add <handle>` — **только** `maintainer-list.nix`
- Коммит 2: `portprotonqt: init at 1.5.0`
- Без точки в summary коммита
- Ветка — от `upstream/master`
- Коммитов много не надо: одна логическая единица = один коммит
- PR в `NixOS/nixpkgs` → `master`, с заполненными чекбоксами шаблона (sandbox,
  platforms, binaries, nixpkgs-review, contribution standards) и лейблами

### 1.8 Про mейнтейнера — почему GitLab не подходит

`maintainers/maintainer-list.nix` требует именно GitHub-идентичность:
в текущем мастере 4983 записи, из них 4981 с `github =` и 4980 с
`githubId =`. Нужен GitHub-аккаунт; он может быть служебным, активность в нём
больше не потребуется. Поле `email` может быть любым.

Зачем это нужно:

- `githubId` — официальный стабильный идентификатор (берётся из
  `https://api.github.com/user/<id>`), проверяется на совпадение с handle
- после мержа — автоматический приглашение в GitHub-команду
  `nixpkgs-maintainers`: пинг на ревью + право пользоваться merge-ботом
- `commit access` для этого **не нужен**

Альтернатив нет: Discourse-категория Patches статус мейнтейнера не даёт и
фактически мертва (последний реальный тред — февраль 2025, обсуждается
закрытие). Отдать пакет чужому мейнтейнеру (bottles/protontricks) не стоит —
пакет заточен под NixOS.

### 1.9 Что больше не нужно

Вычищается при переносе в nixpkgs:

- `gcc` и `stdenv.cc` в `nativeBuildInputs` (проект и так С, `stdenv` достаточно)
- `appstream-glib` (не вызывается meson)
- `desktop-file-utils` (desktop-файлы ставит сам meson)
- `ninja`, `pkg-config`, `python` в `nativeBuildInputs` (даёт `mesonHook`)
- `steam-run` из build-входов
- `config.allowUnfree = true` в импорте nixpkgs
- хардкод `python3.13` в тесте
- самодельные grep-проверки в `postInstall` → в `passthru.tests`

### 1.10 Найденный и исправленный баг во флейке

`pyproject.toml` апстрима требует `qrcode>=8.2`, а в `flake.nix` пакета `qrcode`
не было. **Исправлено** (коммит `bc09800`): `ps.qrcode` добавлен в
`python313.withPackages`. Для nixpkgs-пакета это неважно — список всё равно
берём из релиза (пункт B3).

---

## Часть 2. Этап A — завершён (тег 1.5.0 вышел)

### A1. GitHub-аккаунт — ✅ готово

| | |
| --- | --- |
| handle | `dark-siders` |
| `githubId` | `29074260` |
| `name` | `dark_siders` |
| email через API | не публичный → в `maintainer-list.nix` поле `email` можно не указывать (в мастере nixpkgs около 400 записей только с `github`/`githubId`) |
| зеркало проекта | <https://github.com/dark-siders/PortProtonQt-NIX> — не форк, ручное зеркало, синхронизировано с нашим HEAD (`bc09800`) |

Проверено: в `maintainers/maintainer-list.nix` мастера nixpkgs ключа
`dark_siders`/`dark-siders` **нет** (есть только `darkalex`, `darkonion0`,
`darkyzhou`, `liberodark`), и `githubId` `29074260` не занят. Коллизий нет.

Важно: PR в nixpkgs надо открывать **с этого аккаунта** — ревьюеры сверяют
handle с автором коммита.

Зеркало на GitHub — отдельно полезно: его можно указать в PR как место, где
живёт пользовательский флейк, и в документации (`nix run` по `github:` вместо
`gitlab:`). Но это правка README — отдельная задача, не в этом плане.

Готовая запись для `maintainer-list.nix` (шаг C1):

```nix
  dark-siders = {
    email = "";
    name = "dark_siders";
    github = "dark-siders";
    githubId = 29074260;
  };
```

> Если ревьюер попросит реальный `email`, подставить почту (GitLab-почта
> годится — проверяется только формат).

### A2. Релиз 1.5 — ✅ вышел

Тег `v1.5.0` выпущен **2026-10-14**. Письмо с просьбой о релизе не
понадобилось.

Запасной сценарий (патч-релиз `v1.4.2` вместо полноценного 1.5) не
активировался; он сохранён ниже в части 5 на случай отката.

### A3. Следить за тегами — ✅ выполнено

Последняя проверка: **2026-10-14** — появился тег `v1.5.0`.

```bash
curl -s https://git.linux-gaming.ru/api/v1/repos/Linux-Gaming/PortProtonQt/tags
```

Тег найден → переход к этапу B по «runbook дня X».


### A4. Отдельный вопрос: починить `flake.nix` — ✅ сделано

`ps.qrcode` добавлен в `python313.withPackages` (пункт 1.10) коммитом `bc09800`.
На этап B не влияет.

### A5. Черновик выражения

Держать черновик `package.nix` под текущий `main` в `/tmp` — не в репозитории.
Нужен, чтобы этап B был механической работой.

---

## Часть 3. Этап B — после выхода тега `v1.5.0`

### B1. Окружение

- [ ] Shallow-клон nixpkgs `master` в `/tmp/opencode/nixpkgs`
- [ ] `git remote add upstream https://github.com/NixOS/nixpkgs`
- [ ] `git switch --create portprotonqt-init upstream/master`
- [ ] `nixos-version --revision` — зафиксировать ревизию nixpkgs, на которой шла сборка

Репозиторий этого проекта и конфиг `nixosniri` не трогаем.

### B2. Вводные под 1.5

- [ ] `version = "1.5.0"`
- [ ] `src = fetchurl` по шаблону из пункта 1.2
- [ ] sha256 через `nix-prefetch-url --type sha256 <url>`

### B3. Сверка с релизом — обязательный шаг

Не переносить список зависимостей и флаги вслепую из черновика:

- [ ] `meson_options.txt` — набор опций (`python_purelibdir`, `udev_rulesdir`, `nightly`)
- [ ] `meson.build` — цели установки udev/MIME/polkit/sysusers. В `main` убрана
      ассоциация с исполняемыми файлами Linux, udev-правило может измениться
- [ ] `pyproject.toml` — список зависимостей: Epic-интеграция могла добавить модули
- [ ] `dev-scripts/generate-completions.sh` — на месте ли, не изменился ли интерфейс
- [ ] `LICENSE` — не сменилась ли лицензия
- [ ] `README` / `CHANGELOG.md` — для `meta.description` и `meta.changelog`

### B4. Перевести на free-FHS

Заменить `pkgs.steam-run` на `(steam.override { extraPkgs = …; }).run-free`.

- [ ] Локально проверить: GUI стартует
- [ ] Локально проверить: движок PortProton качает Wine/Proton и запускает игру
- [ ] Если движку не хватает утилит — добавить в `extraPkgs` **списком с
      комментариями**. Кандидаты: `curl`, `p7zip`, `cabextract`, `unzip`,
      `unrar`, `procps`, `psmisc`, `mesa-utils`, `libarchive`, `exiftool`,
      `squashfs-tools`, `gawk`, `findutils`, `tar`, `zstd`
- [ ] Начинать с пустого списка `extraPkgs`: база FHS уже покрывает текущий
      рабочий сценарий

### B5. `package.nix`

- [ ] Функция с точным списком аргументов, без `with`, lowerCamelCase
- [ ] `buildInputs = [ sdl3 vulkan-loader vulkan-headers python3 ]`
- [ ] `nativeBuildInputs` — только `meson` и `gettext` (`mesonHook` даёт
      meson+ninja), плюс `pkg-config`
- [ ] Python-зависимости из `python3.pkgs` (не `python313.withPackages`),
      по списку из B3
- [ ] Порядок атрибутов: `meta` последним

### B6. `mesonFlags`

Каждый флаг — с комментарием «зачем»:

- [ ] `-Dnightly=false` — дефолт, но фиксируем явно
- [ ] `-Dpython_purelibdir=${placeholder "out"}/lib/python${python3.version}/site-packages`
      — иначе meson определит purelib через `sysconfig` интерпретатора и
      попытается писать в store-путь (в песочнице read-only)
- [ ] `-Dudev_rulesdir=${placeholder "out"}/lib/udev/rules.d` — если правило
      ещё есть после B3

### B7. `postInstall`

- [ ] Сгенерировать комплишены: `bash dev-scripts/generate-completions.sh`
- [ ] Установить через `installShellCompletion --bash --fish --zsh`
- [ ] Текущие grep-проверки из нашего `postInstall` **перенести в тест** (B9) —
      в nixpkgs самопроверки в `postInstall` неуместны

### B8. `postFixUp` — FHS-обёртка

- [ ] `mv $out/bin/portprotonqt $out/bin/.portprotonqt-unwrapped`
- [ ] `makeWrapper ${lib.getExe steamRun} $out/bin/portprotonqt` c флагами:
      `--prefix PYTHONPATH`, `--prefix XDG_DATA_DIRS`, `--prefix PATH`,
      `--set STEAM_RUNTIME 1`, `--set STEAM_RUNTIME_PREFER_FRESH 1`
- [ ] Комментарий «зачем FHS» обязателен: движку `start.sh` нужна настоящая
      ФС с glibc, bash и системными утилитами — её нет на NixOS

### B9. `passthru`

- [ ] `updateScript = nix-update-script { }`
- [ ] `tests` — портированный smoke-тест: обёртка зовёт FHS и прописывает
      `PYTHONPATH`; NixOS-правки на месте; `bash -n` для обоих скриптов
      движка; CLI отдаёт справку; скомпилированные модули грузятся тем же
      интерпретатором, которым зовут хелперы движка
- [ ] Без хардкода `python3.13` — через `${python3.pkgs.python.interpreter}`

### B10. `meta`

- [ ] `description` — без «PortProtonQt» и без точки. Например:
      «Graphical frontend for the PortProton compatibility layer»
- [ ] `homepage`
- [ ] `changelog`
- [ ] `license = lib.licenses.gpl3Only`
- [ ] `mainProgram = "portprotonqt"`
- [ ] `platforms = [ "x86_64-linux" ]`
- [ ] `maintainers` — см. C1
- [ ] Комментарий рядом с `platforms`: пакет по определению x86_64-linux,
      FHS/steam-run под другие системы не собирается, сабститутов не будет

### B11. Проверки

- [ ] `sandbox = true` в `/etc/nix/nix.conf`
- [ ] `nix-build -A portprotonqt` — зелёный; python-дерево легло в
      `$out/lib/python3.13/site-packages`
- [ ] `nix-build -A portprotonqt.tests`
- [ ] Прогнать все бинарники из `result/bin`: CLI напрямую (unwrapped) и через
      обёртку
- [ ] **`nix fmt`** (или `nix develop --command treefmt`) — иначе CI упадёт на lint
- [ ] `nix run nixpkgs#nixpkgs-review -- wip`

---

## Часть 4. Этап C — Pull Request

### C1. Коммит maintainer

- [x] Данные готовы: `github = "dark-siders"`, `githubId = 29074260`,
      `name = "dark_siders"` (см. A1)
- [ ] Проверить ещё раз перед отправкой: `githubId` из
      `api.github.com/users/dark-siders` совпадает с handle, handle совпадает
      с автором коммита
- [ ] В `maintainers/maintainer-list.nix` добавить запись (готовый текст — A1)
- [ ] Отдельный коммит `maintainers: add dark-siders`, **первым** в PR

### C2. Коммит пакета

- [ ] `portprotonqt: init at 1.5.0`, без точки в summary
- [ ] В теле — что за пакет и почему версия такая

### C3. Открыть PR

- [ ] В `NixOS/nixpkgs`, базовая ветка `master`
- [ ] Открывать **с аккаунта `dark-siders`** — ревьюеры сверяют handle с автором
- [ ] Заголовок: `portprotonqt: init at 1.5.0`
- [ ] В описании:
  - что это за пакет и зачем он в nixpkgs
  - почему FHS-обёртка (движок `start.sh` требует настоящей ФС)
  - почему `steam.run-free` и что `allowUnfree` не требуется
  - **что NixOS-фиксы теперь в самом релизе, патчить нечего**
  - что соавтор NixOS-правок — мейнтейнер пакета
  - природа `src`: архив генерируется Gitea на лету, не release-asset;
    контрольная сумма стабильна (сверена с Void Linux), эндпоинт `archive/`
    не закрыт анти-ботом
  - ссылка на зеркало флейка: <https://github.com/dark-siders/PortProtonQt-NIX>
    (по желанию — чтобы показать, что пакет уже используется)
- [ ] Чекбоксы шаблона: sandbox, platforms, binaries, nixpkgs-review,
      contribution standards
- [ ] Лейблы

### C4. Дальше

- [ ] Отвечать на ревью, поддерживать PR в mergeable-состоянии
- [ ] При замечаниях по конфликтам — `git rebase upstream/master` и
      `git push --force-with-lease`
- [ ] Коммитера — добровольный и неоплачиваемый: сроки от недель до месяцев,
      это нормально. Если тишина больше недели — вежливо напомнить в
      Discourse (`c/dev`) или в Matrix-комнате review-requests
- [ ] Последующие версии прилетят от `nixpkgs-update` автоматически

---

## Часть 5. Риски и запасные ходы

| # | Риск | Что делать |
| --- | --- | --- |
| 1 | 1.5 может переименовать NixOS-фиксы (например имя переменной) | Проверки живут в `passthru.tests`, а не в `postInstall`: упавший тест в nixpkgs — нормальный сигнал, а не поломка у пользователя |
| 2 | `steam.run-free` — слабодокументированная связка, прецедент только у `protontricks` | Запасной ход: `buildFHSEnv` напрямую, как в `pkgs/by-name/bo/bottles/package.nix` |
| 3 | 1.5 не выйдет | Откат на `v1.4.1` + `fetchpatch2` с `excludes = [ "CHANGELOG.md" ]` (проверено, применяется). Ось минусов: 163 коммита мимо, и при автобампе патч перестанет применяться — нужен ручной follow-up |
| 4 | Мейнтейнер отойдёт | По процедуре nixpkgs: issue или пост в Discourse с упоминанием пакета, чтобы его взяли. Пакет без `meta.maintainers` в nixpkgs не остаётся |
| 5 | `python` в nixpkgs сменит мажорную версию | `mesonFlags` строится от `python3.version`, автобамп это учтёт. `>= 3.11` — большой запас |
| 6 | Сборка на Darwin при вычислении `pkgs` | `platforms = [ "x86_64-linux" ]` + `buildFHSEnv` внутри FHS; проверить, что `pkgs.portprotonqt` вычисляется без ошибки на darwin (шаг B11) |

---

## Часть 5.1. После мержа — судьба нашего флейка

Отдельное решение, принимается **после** мержа в nixpkgs, не раньше. Три
варианта, все рабочие:

1. **Оставить флейк как есть.** Он собирает тот же апстрим, но пиннит
   `nixos-unstable`, пока nixpkgs-пакет живёт в ветке `master`. Со временем
   расхождение в версиях станет заметным — минус.
2. **Перевести флейк на пакет из nixpkgs.** Флейк становится тонким: только
   `nixpkgs`-input (уже есть) и `pkgs.portprotonqt`, без своего derivation'а.
   Пользователи получают `nix run gitlab:dark_siders/portprotonqt-nix`, а
   обновления приходят из nixpkgs. Плюс: `allowUnfree` из флейка уходит.
   Рекомендуется именно этот вариант.
3. **Удалить флейк**, оставить только этот план как историю и README со
   ссылкой на инструкцию в nixpkgs. Радикально, теряется удобный `nix run`.

Что бы ни выбрали — правки в `flake.nix` и `README*` делаются отдельным
согласованием, не молча.

Дополнительно после мержа:

- [ ] В описании PR указать ссылку на флейк, чтобы ревьюер увидел живой
      пользовательский сценарий (см. C3)
- [ ] Подписаться на `nixpkgs-update` для `portprotonqt`, чтобы не пропустить
      сломанный автобамп
- [ ] `meta.maintainers` = `dark-siders`, поэтому уведомления о бампах и
      поломках придут лично

---

## Часть 6. Полезные ссылки

- CONTRIBUTING: <https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md>
- Правила для пакетов: <https://github.com/NixOS/nixpkgs/blob/master/pkgs/README.md>
- Правила для мейнтейнеров: <https://github.com/NixOS/nixpkgs/blob/master/maintainers/README.md>
- Структура `pkgs/by-name`: <https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/README.md>
- Требования к PR: <https://github.com/NixOS/nixpkgs/blob/master/doc/contributing/submitting-changes.chapter.md>
- Гайд по ревью (за пределами nixpkgs): <https://github.com/NixOS/nixpkgs/blob/master/doc/contributing/reviewing-changes.chapter.md>
- Прецедент `steam.run-free`: <https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/pr/protontricks/package.nix>
- Прецедент `buildFHSEnv`: <https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/bo/bottles/package.nix>
- Прецедент `makeWrapper` поверх steam-run: <https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/it/itch/package.nix>
- Определение `steam.run` / `steam.run-free`: <https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/st/steam/package.nix>
- Референс-пакет в Void Linux: <https://github.com/Event-Horizon-VL/blackhole-vl/blob/main/srcpkgs/portprotonqt/template>
- NixOS Discourse, «Patches» (не рекомендуется): <https://discourse.nixos.org/t/about-the-patches-category/477>
