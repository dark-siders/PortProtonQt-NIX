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
  # runtime-утилиты, которые нужны bash-движку PortProton и GUI
  cabextract,
  p7zip,
  unzip,
  unrar,
  curl,
  file,
  gawk,
  gnugrep,
  gnutar,
  gzip,
  xz,
  zstd,
  findutils,
  coreutils,
  pciutils,
  procps,
  psmisc,
  ffmpeg_6, # для медиа-поддержки (gstreamer/ffmpeg база)
  perlPackages,
  mesa-demos,
  desktop-file-utils,
  bash,
}: let
  version = "1.4.1";
  pname = "portprotonqt";

  # upstream main на git.linux-gaming.ru: содержит фикс поиска скриптов/локалей
  # через XDG_DATA_DIRS (коммит f1a5db4f, ещё не попавший в релиз/GitHub-зеркало).
  # Инстанс git.linux-gaming.ru работает на Gitea/Forgejo — у него НЕТ API
  # `/api/v4/...` (fetchFromGitLab давал 404), поэтому берём архив по Gitea-URL.
  src = fetchurl {
    url = "https://git.linux-gaming.ru/Linux-Gaming/PortProtonQt/archive/f1a5db4f34ce7edcbc7aa8e8b687d917c3f79458.tar.gz";
    hash = "sha256-VkWjpdVeDIFn75fYfPeCOyj4HxAubxLJ/lYj/PgKm+Y=";
  };

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

  # Бинари, которые должны быть в PATH у bash-движка (FHS-окружение через steam-run)
  runtimeBins = [
    cabextract
    p7zip
    unzip
    unrar
    curl
    file
    gawk
    gnugrep
    gnutar
    gzip
    xz
    zstd
    findutils
    coreutils
    pciutils
    procps
    psmisc
    ffmpeg_6
    perlPackages.ImageExifTool
    mesa-demos
    gnugrep
  ];

  runtimeBinPath = lib.makeBinPath runtimeBins;
in
  stdenv.mkDerivation {
    inherit pname version src;

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
      #
      # XDG_DATA_DIRS:$out/share — как в системной установке апстрима (/usr/share):
      # Qt/GIO при регистрации в xdg-desktop-portal ищет desktop-файл
      # ru.linux_gaming.PortProtonQt.desktop по XDG_DATA_DIRS самого приложения.
      # Без этого префикса портал не находит app info → ошибка
      # «Could not register app ID: App info not found».
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
      maintainers = with maintainers; [ ];
      platforms = platforms.linux;
      mainProgram = "portprotonqt";
    };
  }
