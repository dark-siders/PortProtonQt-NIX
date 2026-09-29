{
  lib,
  stdenv,
  fetchurl,
  meson,
  ninja,
  pkg-config,
  gettext,
  python3,
  sdl3,
  vulkan-headers,
  vulkan-loader,
  qt6,
  steam-run,
  makeWrapper,
  runCommand,
  # runtime-утилиты, которые нужны bash-движку PortProton и GUI
  cabextract,
  p7zip,
  unzip,
  unrar,
  curl,
  file,
  gawk,
  gnused,
  gnugrep,
  gnutar,
  gzip,
  util-linux,
  which,
  xz,
  zstd,
  findutils,
  coreutils,
  pciutils,
  procps,
  psmisc,
  pulseaudio,
  ffmpeg_6, # для медиа-поддержки (gstreamer/ffmpeg база)
  perlPackages,
  mesa-demos,
  xrandr,
  bash,
  # для проверок: валидация desktop-файлов и AppStream-метаинфо
  appstream,
  desktop-file-utils,
  # tests.nixos собирается из passthru.tests (см. ниже)
  testers,}:
let
  # Релиз 1.4.1 — от 2026-08-26. Наш src новее: в main есть NixOS-фиксы,
  # которых в релизе ещё нет, поэтому версия помечена как unreleased.
  version = "1.4.1-unreleased-20260929";
  pname = "portprotonqt";

  # upstream main на git.linux-gaming.ru: коммит f1a5db4f «fix: use XDG
  # data paths on NixOS» — фикс поиска скриптов/локалей через XDG_DATA_DIRS,
  # ещё не попавший в релиз. Апстрим отложил мердж до 1.5.
  # Инстанс git.linux-gaming.ru работает на Gitea/Forgejo — у него НЕТ API
  # `/api/v4/...` (fetchFromGitLab давал 404), поэтому берём архив по Gitea-URL.
  upstreamCommit = "f1a5db4f34ce7edcbc7aa8e8b687d917c3f79458";
  src = fetchurl {
    url = "https://git.linux-gaming.ru/Linux-Gaming/PortProtonQt/archive/${upstreamCommit}.tar.gz";
    hash = "sha256-VkWjpdVeDIFn75fYfPeCOyj4HxAubxLJ/lYj/PgKm+Y=";
  };

  patches = [ ./fix-autoinstall-cache.patch ];

  # Python-окружение со всеми зависимостями GUI
  python = python3.withPackages (ps: [
    ps.requests
    ps.babel
    ps.evdev
    ps.orjson
    ps.psutil
    ps.tqdm
    ps.vdf
    ps.libarchive-c
    ps.pyside6
    ps.rapidfuzz
    ps.pefile
    ps.pillow
    ps.websocket-client
    ps.qrcode
    ps.dbus-fast
  ]);

  # Бинари, которые должны быть в PATH у bash-движка (FHS-окружение через
  # steam-run) и у GUI. FHS steam-run (arch-based) закрывает часть потребностей,
  # но не все: lsblk/pactl/xrandr/7z/unrar/curl в нём отсутствуют.
  runtimeBins = [
    cabextract
    p7zip
    unzip
    unrar
    curl
    file
    gawk
    gnused
    gnugrep
    gnutar
    gzip
    util-linux # lsblk: определение fuseblk-дисков (NTFS/exFAT) в GUI и движке
    which
    xz
    zstd
    findutils
    coreutils
    pciutils
    procps
    psmisc
    pulseaudio # pactl: переключение аудиоустройств (system_manager/audio.py)
    xrandr # режим разрешения для X11-сессий
    ffmpeg_6
    perlPackages.ImageExifTool
    mesa-demos
  ];

  runtimeBinPath = lib.makeBinPath runtimeBins;

  # Утилиты, которые движок и GUI вызывают напрямую. Ни одна не должна
  # приходить из системного PATH: на NixOS-системе без них в systemPackages
  # приложение деградирует (ровно тот класс бага, что был с python3).
  requiredBins = [
    "7z"
    "awk"
    "cabextract"
    "curl"
    "exiftool"
    "file"
    "find"
    "grep"
    "gzip"
    "killall"
    "lsblk"
    "pactl"
    "pgrep"
    "pkill"
    "sed"
    "tar"
    "timeout"
    "unrar"
    "unzip"
    "which"
    "xrandr"
    "xz"
    "zstd"
  ];

  # Модули, импорт которых проверяем без дисплея: они тянут PySide6, нативный
  # модуль геймпада и всю обвязку локализации.
  pythonModules = [
    "portprotonqt"
    "portprotonqt.app"
    "portprotonqt.cli"
    "portprotonqt.localization"
    "portprotonqt.main_window"
    "portprotonqt.native_gamepad"
    "portprotonqt.qt_utils"
    "portprotonqt.portproton_api"
    "portprotonqt.downloader"
    "portprotonqt.disc_image_utils"
    "portprotonqt.port_data_path_selector"
    "portprotonqt.compatibility_report"
  ];
in
  stdenv.mkDerivation (finalAttrs: {
    inherit pname version src patches;

    strictDeps = true;

    nativeBuildInputs = [
      meson
      ninja
      pkg-config
      gettext
      makeWrapper
      python
    ];

    buildInputs = [
      sdl3
      vulkan-headers
      vulkan-loader
      qt6.qtbase
      qt6.qtsvg
      qt6.qtimageformats
      qt6.qtmultimedia
      steam-run
      bash
    ] ++ runtimeBins;

    # nativeCheckInputs не нужны: checkPhase проверяет только command -v по
    # объявленным зависимостям. Проверки установленного вывода (импорты,
    # desktop/metainfo, синтаксис движка, запуск CLI) живут в
    # passthru.tests.package — nixpkgs гоняет checkPhase до installPhase.

    # Python-пакет portprotonqt meson ставит в $out/<python.sitePackages>
    # (pure install dir), поэтому указываем место под PYTHONPATH в обёртке.
    dontWrapQtApps = true;

    # Генерируем обёртку entry-point после установки, чтобы приложение
    # запускалось изолированным Python-окружением с нужными Qt и бинарями.
    postInstall = let
      pythondir = "${python}/${python.sitePackages}";
    in ''
      # Entry-point из апстрима — это python-скрипт с shebang
      # `#!/usr/bin/env python3`. В nix-store нет /usr/bin/env, поэтому такой
      # shebang работает только если python3 есть в системном PATH: на чистом
      # NixOS запуск падает с «env: 'python3': No such file or directory».
      # Прописываем интерпретатор из store, чтобы запуск вообще не зависел от
      # системного PATH.
      substituteInPlace "$out/bin/portprotonqt" \
        --replace-fail "/usr/bin/env python3" "${python}/bin/python3"

      # polkit-правило и sysusers.d оставляем как в апстриме (CVE-2026-59678
      # закрыт в 1.3.1): правило теперь даёт привилегии только членам группы
      # portprotonqt, которую создаёт /lib/sysusers.d/portprotonqt.conf.
      # На NixOS группу нужно завести через users.groups.portprotonqt = { };
      # (см. README).

      # Скрипты bash-движка, которые meson положил в $out/share/portproton/scripts,
      # должны исполняться внутри FHS (steam-run), т.к. PortProton скачивает
      # динамические бинари Wine/Proton вне nix-store.
      # start.sh апстрима вычисляет PORT_SCRIPTS_PATH как dirname(realpath $0),
      # поэтому реальный скрипт обязан лежать в самой scripts/ (не в подпапке),
      # иначе он не находит functions_helper/var/conf. Переименовываем оригинал
      # и кладём рядом обёртку, запускающую двигатель внутри steam-run.
      mv "$out/share/portproton/scripts/start.sh" "$out/share/portproton/scripts/start.sh.real"
      cat > "$out/share/portproton/scripts/start.sh" <<'WRAP'
      #!/usr/bin/env bash
      exec ${steam-run}/bin/steam-run "$(dirname "$(realpath "$0")")/start.sh.real" "$@"
      WRAP
      chmod +x "$out/share/portproton/scripts/start.sh"

      wrapProgram "$out/bin/portprotonqt" \
        --set PYTHONPATH "$out/${python.sitePackages}:${pythondir}" \
        --prefix PATH : ${lib.makeBinPath [ python ]}:${runtimeBinPath}:${steam-run}/bin \
        --prefix QT_PLUGIN_PATH : ${qt6.qtbase}/${qt6.qtbase.qtPluginPrefix} \
        --set SHARUN_DIR "$out" \
        --prefix XDG_DATA_DIRS : "$out/share"
      # SHARUN_DIR=$out — штатный механизм апстрима (AppImage/sharun):
      # get_portproton_scripts_path() берёт $SHARUN_DIR/share/portproton/scripts,
      # а localization.py — $SHARUN_DIR/share/locale.

      # XDG_DATA_DIRS:$out/share — как в системной установке апстрима (/usr/share):
      # Qt/GIO при регистрации в xdg-desktop-portal ищет desktop-файл
      # ru.linux_gaming.PortProtonQt.desktop по XDG_DATA_DIRS самого приложения.
      # Без этого префикса портал не находит app info → ошибка
      # «Could not register app ID: App info not found».
    '';

    # nixpkgs выполняет checkPhase ДО installPhase, поэтому здесь проверяем
    # только то, что видно на этапе сборки, — наличие объявленных зависимостей.
    # Всё, что требует установленного $out, живёт в passthru.tests.package.
    doCheck = true;

    checkPhase = ''
      # strictDeps не добавляет buildInputs в PATH, а проверять надо ровно тот
      # набор, который реально попадает в PATH обёртки.
      export PATH="${runtimeBinPath}:$PATH"

      echo "--- наличие утилит, которые движок и GUI зовут напрямую"
      for bin in ${lib.concatStringsSep " " requiredBins}; do
        if ! command -v "$bin" > /dev/null; then
          echo "MISSING в замыкании: $bin" >&2
          exit 1
        fi
      done
      echo "  все ${toString (builtins.length requiredBins)} утилит на месте"
    '';

    meta = with lib; {
      description = "Modern GUI for managing and launching games from PortProton, Steam, Epic Games Store and GOG";
      longDescription = ''
        PortProtonQt — современный интерфейс на PySide6 для управления и запуска
        игр из PortProton, Steam, Epic Games Store и GOG.

        На NixOS bash-движок PortProton исполняется внутри FHS-окружения
        (steam-run), чтобы динамически скомпилированные Wine/Proton-сборки,
        скачиваемые самим приложением, корректно запускались.
      '';
      homepage = "https://git.linux-gaming.ru/Linux-Gaming/PortProtonQt";
      license = licenses.gpl3;
      # steam-run поставляет FHS только для x86_64, и сам флейк собирается
      # только под x86_64-linux (см. flake-utils.eachSystem в flake.nix).
      platforms = [ "x86_64-linux" ];
      mainProgram = "portprotonqt";
    };

    passthru = {
      inherit upstreamCommit;

      # Проверки установленного вывода: импорты python-модулей, валидация
      # desktop-файлов и AppStream-метаинфо, синтаксис bash-движка и — главное —
      # запуск CLI в полностью пустом окружении (env -i без системного PATH).
      # Это регресс-тест на тот же класс бага, что был с python3.
      tests.package = runCommand "portprotonqt-tests" {
        nativeBuildInputs = [
          appstream
          desktop-file-utils
          python
        ];
      } ''
        export PYTHONPATH="${finalAttrs.finalPackage}/${python.sitePackages}:${python}/${python.sitePackages}"

        # Уходим из build-каталога: он в sys.path первым и подменяет установленный
        # пакет исходниками (а в исходниках нет собранных .so).
        cd "$TMPDIR"

        # Импорт app/cli на этапе import создаёт кэш в $HOME, а в песочнице
        # это /homeless-shelter без прав на запись.
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"

        echo "--- импорт python-модулей (без системного python3)"
        for module in ${lib.concatStringsSep " " (map (m: "\"${m}\"") pythonModules)}; do
          echo "  import $module"
          python -c 'import importlib, sys; importlib.import_module(sys.argv[1])' "$module"
        done

        echo "--- валидация desktop-файлов"
        for desktop in ${finalAttrs.finalPackage}/share/applications/*.desktop; do
          echo "  desktop-file-validate $desktop"
          desktop-file-validate "$desktop"
        done

        echo "--- валидация AppStream-метаинфо"
        for metainfo in ${finalAttrs.finalPackage}/share/metainfo/*.xml; do
          echo "  appstreamcli validate $metainfo"
          appstreamcli validate --no-net "$metainfo"
        done

        echo "--- синтаксис bash-скриптов движка"
        while IFS= read -r -d "" script; do
          if [ "$(head -c 2 "$script")" = "#!" ]; then
            bash -n "$script"
          fi
        done < <(find ${finalAttrs.finalPackage}/share/portproton/scripts -type f -print0)

        echo "--- изолированный запуск CLI в пустом окружении"
        env -i HOME="$HOME" ${finalAttrs.finalPackage}/bin/portprotonqt --help > /dev/null

        touch $out
      '';

      # NixOS VM-тест: поднимает систему, где в systemPackages лежит только
      # portprotonqt (то есть без python3), и проверяет, что пакет запускается
      # без системного PATH.
      tests.nixos = testers.nixosTest {
        name = "portprotonqt";
        nodes.machine = { pkgs, ... }: {
          environment.systemPackages = [ finalAttrs.finalPackage pkgs.coreutils ];
          virtualisation.memorySize = 2048;
          virtualisation.diskSize = 6144;
          virtualisation.graphics = false;
        };
        testScript = ''
          # В системе нет python3 — интерпретатор пакет обязан взять из своего
          # замыкания (именно так чинился баг «env: 'python3': No such file»).
          machine.fail("command -v python3")

          # Обычный запуск: shebang, PYTHONPATH, обёртка.
          machine.succeed("portprotonqt --help")

          # Запуск в пустом окружении: ничего не берём из системного PATH.
          machine.succeed("env -i HOME=/root portprotonqt --help")

          # Утилиты, которых в системных пакетах нет (sed, lsblk, pactl, xrandr),
          # обязаны приходить из замыкания пакета — проверяем, что обёртка
          # действительно прокидывает их в PATH.
          wrapper = machine.succeed("readlink -f $(command -v portprotonqt)").strip()
          for marker in ("gnused", "util-linux", "pulseaudio", "xrandr", "p7zip", "cabextract"):
              machine.succeed(f"grep -q {marker} {wrapper}")
        '';
      };
    };
  })
