{
  lib,
  stdenv,
  fetchFromGitHub,
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

  src = fetchFromGitHub {
    owner = "linux-gaming-ru";
    repo = "PortProtonQt";
    rev = "18ae09f4b0d084353e4166053df435d64a573507"; # v1.4.1
    hash = "sha256-I07eFM9lHqnu2RPpgE5v7fI69mgXVwd/X33A2vCzyVQ=";
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
      # polkit-правило из апстрима содержит известную уязвимость
      # (oss-security, июль 2026) — не устанавливаем его и sysusers.d.
      rm -rf "$out/share/polkit-1" "$out/lib/sysusers.d"

      # Скрипты bash-движка, которые meson положил в $out/share/portproton/scripts,
      # должны исполняться внутри FHS (steam-run), т.к. PortProton скачивает
      # динамические бинари Wine/Proton вне nix-store.
      mkdir -p "$out/share/portproton/scripts/.nix-real"
      mv "$out/share/portproton/scripts/start.sh" "$out/share/portproton/scripts/.nix-real/start.sh"
      cat > "$out/share/portproton/scripts/start.sh" <<'WRAP'
      #!/usr/bin/env bash
      exec ${steam-run}/bin/steam-run "$(dirname "$(realpath "$0")")/.nix-real/start.sh" "$@"
      WRAP
      chmod +x "$out/share/portproton/scripts/start.sh"

      wrapProgram "$out/bin/portprotonqt" \
        --set PYTHONPATH "$out/${python.sitePackages}:${pythondir}" \
        --set APPDIR "$out" \
        --set SHARUN_DIR "$out" \
        --prefix PATH : ${runtimeBinPath}:${steam-run}/bin \
        --prefix QT_PLUGIN_PATH : ${qt6.qtbase}/${qt6.qtbase.qtPluginPrefix} \
        --prefix XDG_DATA_DIRS : "$out/share"

      # SHARUN_DIR указывает localization.py на $out/share/locale, где лежат
      # скомпилированные .mo (ru, de, es ...) — без этого GUI всегда английский,
      # т.к. на NixOS нет системного /usr/share/locale.
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
