{
  lib,
  stdenv,
  fetchFromGitLab,
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
  src = fetchFromGitLab {
    domain = "git.linux-gaming.ru";
    owner = "Linux-Gaming";
    repo = "PortProtonQt";
    rev = "f1a5db4f34ce7edcbc7aa8e8b687d917c3f79458";
    hash = "sha256-xrp9RQlgoLJdN1/lKgmxN1ApGURvgs7Mu1IA8JBgcmY=";
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
        --prefix PATH : ${runtimeBinPath}:${steam-run}/bin \
        --prefix QT_PLUGIN_PATH : ${qt6.qtbase}/${qt6.qtbase.qtPluginPrefix} \
        --prefix XDG_DATA_DIRS : "$out/share"

      # XDG_DATA_DIRS=$out/share — апстрим (f1a5db4f) ищет через него и скрипты
      # ($out/share/portproton/scripts), и локали ($out/share/locale/*.mo).
      # Поэтому APPDIR/SHARUN_DIR-костыли больше не нужны.
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
