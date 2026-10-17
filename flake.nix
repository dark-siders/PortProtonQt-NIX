{
  description = "PortProtonQt — PortProton Qt frontend (official Linux-Gaming.ru repo)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    portprotonqt-src.url = "git+https://git.linux-gaming.ru/Linux-Gaming/PortProtonQt?ref=refs/tags/v1.5.0";
    portprotonqt-src.flake = false;
  };

  outputs = { self, nixpkgs, flake-utils, portprotonqt-src }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        lib = nixpkgs.lib;
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        # Python 3.13 with required packages
        python = pkgs.python313.withPackages (ps: [
          ps.pyside6
          ps.shiboken6
          ps.orjson
          ps.babel
          ps.dbus-fast
          ps.pillow
          ps.vdf
          ps.requests
          ps.tqdm
          ps.pefile
          ps.websocket-client
          ps.psutil
          ps.evdev
          ps.libarchive-c
          ps.rapidfuzz
          ps.qrcode
        ]);

        # Build PortProtonQt via meson
        portprotonqt = pkgs.stdenvNoCC.mkDerivation {
          pname = "portprotonqt";
          version = "1.5.0";

          src = portprotonqt-src;

          nativeBuildInputs = with pkgs; [
            meson
            ninja
            pkg-config
            python
            desktop-file-utils
            appstream-glib
            gettext
            gcc
            stdenv.cc
            makeWrapper
            steam-run
            kdePackages.wrapQtAppsHook
          ];

          buildInputs = with pkgs; [
            sdl3
            vulkan-loader
            vulkan-headers
            python
            qt6.qtbase
            qt6.qtdeclarative
            qt6.qtsvg
            qt6.qtwayland
            kdePackages.breeze-icons
            kdePackages.oxygen-icons
            glib
            glibmm
            gtk3
            dbus
            libappindicator-gtk3
            fontconfig
            freetype
            harfbuzz
            python313Packages.pyside6
            python313Packages.shiboken6
          ];

          # Meson build
          mesonFlags = [ "-Dnightly=false" ];

          #--- Обёртка: запуск через steam-run (FHS)
          postInstall = ''
            mv $out/bin/portprotonqt $out/bin/.portprotonqt-unwrapped

            #--- NixOS/FHS: steam-run отдаёт в песочницу PATH=/run/wrappers/bin:/usr/bin:...
            # поэтому `python3` там — ЧУЖОЙ интерпретатор. Наши скомпилированные
            # модули (orjson, pyside6) он не грузит, а чистые (babel) грузит —
            # отсюда разнородные ошибки.
            # Сейчас это чинит патч апстрима: app.py прописывает
            # PORTPROTONQT_PYTHON=$(sys.executable), а скрипты движка зовут
            # PORTPROTONQT_PYTHON с фолбэком на python3. Свою подстановку
            # абсолютного пути в postInstall убрали — она больше не нужна
            # и конфликтует с патчем.
            #
            # Строгая проверка: если апстрим переименует переменную или уберёт
            # вызовы, молча ломаться нельзя — падаем на сборке, а не у юзера.
            for f in "$out/share/portproton/scripts/start.sh" \
                     "$out/share/portproton/scripts/functions_helper" ; do
              grep -q "PORTPROTONQT_PYTHON" "$f" || {
                echo "portprotonqt: в $f нет PORTPROTONQT_PYTHON — патч не применился?" >&2
                exit 1
              }
              bash -n "$f" || {
                echo "portprotonqt: синтаксис сломан в $f" >&2
                exit 1
              }
            done

            #--- Qt-плагины: PySide6 в nixpkgs не поставляет своих Qt-плагинов,
            # а галочки в чекбоксах рисуются из SVG-картинки (styles.py —
            # QCheckBox::indicator:checked), поэтому нужен плагин формата
            # изображения из qt6.qtsvg. Путь — lib/qt-6/plugins (Qt ≥ 6.6);
            # раньше здесь стояло устаревшее lib/qt6/plugins, из-за чего
            # QT_PLUGIN_PATH указывал в никуда.
            makeWrapper ${lib.getExe pkgs.steam-run} $out/bin/portprotonqt \
              --add-flags $out/bin/.portprotonqt-unwrapped \
              --prefix PYTHONPATH ':' "$out/lib/python3.13/site-packages" \
              --prefix XDG_DATA_DIRS ':' "$out/share" \
              --prefix PATH ':' "$out/bin:${python}/bin" \
              --prefix QT_PLUGIN_PATH ':' "${pkgs.qt6.qtbase}/lib/qt-6/plugins:${pkgs.qt6.qtsvg}/lib/qt-6/plugins:${pkgs.qt6.qtwayland}/lib/qt-6/plugins" \
              --prefix XDG_DATA_DIRS ':' "${pkgs.kdePackages.breeze-icons}/share:${pkgs.kdePackages.oxygen-icons}/share" \
              --set QT_QPA_PLATFORMTHEME "qt6ct" \
              --set QT_STYLE_OVERRIDE "kvantum-dark" \
              --set ICON_THEME "breeze" \
              --set STEAM_RUNTIME 1 \
              --set STEAM_RUNTIME_PREFER_FRESH 1

            #--- Заголовок окна: только версия, без коммита.
            # В релизной сборке (-Dnightly=false) апстримный get_version()
            # всё равно зовёт `git rev-parse --short HEAD` в ТЕКУЩЕМ каталоге,
            # из-за чего при запуске из git-репы в заголовок попадал её хэш.
            # Вырезаем runtime-фоллбек целиком (ветка APP_COMMIT для nightly
            # остаётся), чтобы в файле не было мёртвого кода. Если апстрим
            # изменит функцию, --replace-fail уронит сборку.
            app_py="$out/lib/python3.13/site-packages/portprotonqt/app.py"
            substituteInPlace "$app_py" \
              --replace-fail $'    try:\n        commit = subprocess.check_output(\n            ["git", "rev-parse", "--short", "HEAD"],\n            stderr=subprocess.DEVNULL,\n        ).decode("utf-8").strip()\n        return f"{__app_version__} ({commit})"\n    except (subprocess.CalledProcessError, FileNotFoundError, OSError):\n        return __app_version__' \
              '    return __app_version__'

            #--- NixOS/steam-run: kill_portwine() убивает собственный контейнер
            # kill_portwine() ищет bwrap через `pgrep -f wrap | grep PortProton`
            # и шлёт ему SIGKILL. Под steam-run этот bwrap — наш же контейнер,
            # а у bwrap стоит --die-with-parent, поэтому сессия умирает с
            # SIGKILL (137), и GUI показывает "ProcessError.Crashed code: 9".
            # Сейчас это чинит патч апстрима: он отбрасывает bwrap-PID, являющиеся
            # предками текущего шелла ($BASHPID и выше по ps -o ppid=).
            # Свою вставку этого блока убрали — она больше не нужна.
            grep -q "pw_ancestor_pid" "$out/share/portproton/scripts/functions_helper" || {
              echo "portprotonqt: нет guard'а предков в kill_portwine — патч не применился?" >&2
              exit 1
            }
          '';

          meta = with pkgs.lib; {
            description = "PortProtonQt — graphical frontend for PortProton, Steam, and Epic Games Store";
            homepage = "https://git.linux-gaming.ru/Linux-Gaming/PortProtonQt";
            license = licenses.gpl3Only;
            maintainers = with maintainers; [ ];
            platforms = platforms.linux;
          };
        };

      in {
        packages = {
          default = portprotonqt;
          portprotonqt = portprotonqt;
          # Короткий алиас, чтобы запускать через `nix run .#portproton`
          portproton = portprotonqt;
        };

        # Приложение по умолчанию: `nix run .#portproton`
        apps = {
          default = {
            type = "app";
            program = "${portprotonqt}/bin/portprotonqt";
          };
          portproton = {
            type = "app";
            program = "${portprotonqt}/bin/portprotonqt";
          };
          portprotonqt = {
            type = "app";
            program = "${portprotonqt}/bin/portprotonqt";
          };
        };

        checks = {
          package = portprotonqt;
          # Smoke-тест: обёртка действительно зовёт steam-run, CLI отдаёт справку.
          # Вызываем .portprotonqt-unwrapped напрямую, т.к. steam-run + pressure-vessel
          # требуют полноценного окружения и не работают в build-песочнице.
          cli = pkgs.runCommand "portprotonqt-cli-test"
            {
              nativeBuildInputs = [ python pkgs.bash pkgs.git ];
            } ''
            cp -r ${portprotonqt} $out
            chmod -R +w $out

            # Приложение пишет кэш/конфиг в XDG-каталоги — уводим их в TMPDIR
            export HOME=$TMPDIR/home
            export XDG_CONFIG_HOME=$TMPDIR/home/.config
            export XDG_CACHE_HOME=$TMPDIR/home/.cache
            export XDG_DATA_HOME=$TMPDIR/home/.local/share
            export XDG_STATE_HOME=$TMPDIR/home/.local/state
            mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" \
                     "$XDG_DATA_HOME" "$XDG_STATE_HOME"

            # 0. В заголовке окна только версия. get_version() не должна
            #    подхватывать git-коммит из текущего каталога, поэтому зовём
            #    её, стоя внутри настоящего git-репозитория.
            pyinterp=$(sed -n '1s|^#!||p' "$out/bin/.portprotonqt-unwrapped")
            tmpgit=$TMPDIR/gitrepo
            mkdir -p "$tmpgit"
            git -C "$tmpgit" init -q
            git -C "$tmpgit" -c user.email=test@test -c user.name=test \
              commit -q --allow-empty -m init
            ( cd "$tmpgit" && \
              PYTHONPATH="$out/lib/python3.13/site-packages" "$pyinterp" -c \
                "from portprotonqt.app import get_version; assert '(' not in get_version(), get_version()" ) || {
              echo "FAIL: get_version() подхватывает git-коммит" >&2
              exit 1
            }

            # 1. Обёртка обязана звать steam-run и прописывать PYTHONPATH.
            # wrapQtAppsHook оборачивает нашу makeWrapper-обёртку в видимый
            # $out/bin/portprotonqt, а сама она (с steam-run и PYTHONPATH)
            # остаётся как .portprotonqt-wrapped.
            wrapper=$out/bin/.portprotonqt-wrapped
            grep -q "steam-run" "$wrapper" || {
              echo "FAIL: обёртка не вызывает steam-run" >&2
              exit 1
            }
            grep -q "python3.13/site-packages" "$wrapper" || {
              echo "FAIL: в обёртке нет PYTHONPATH" >&2
              exit 1
            }

            # 2. Регресс: NixOS-правки на месте (взяты из патча апстрима)
            #    a) скрипты движка зовут интерпретатор через PORTPROTONQT_PYTHON
            for f in "$out/share/portproton/scripts/start.sh" \
                     "$out/share/portproton/scripts/functions_helper" ; do
              grep -q 'PORTPROTONQT_PYTHON:-python3' "$f" || {
                echo "FAIL: в $f нет обращения к PORTPROTONQT_PYTHON" >&2
                exit 1
              }
            done
            #    b) app.py прописывает себе sys.executable — иначе движок
            #       запустится с чужим интерпретатором из FHS
            grep -q 'PORTPROTONQT_PYTHON.*=.*sys.executable' \
              "$out/lib/python3.13/site-packages/portprotonqt/app.py" || {
              echo "FAIL: app.py не прописывает PORTPROTONQT_PYTHON=sys.executable" >&2
              exit 1
            }
            #    c) защита kill_portwine от самоубийства контейнера
            grep -q "pw_ancestor_pid" \
              "$out/share/portproton/scripts/functions_helper" || {
              echo "FAIL: нет защиты kill_portwine" >&2
              exit 1
            }
            #    d) синтаксис движка не сломан
            for f in "$out/share/portproton/scripts/start.sh" \
                     "$out/share/portproton/scripts/functions_helper" ; do
              bash -n "$f" || {
                echo "FAIL: синтаксис сломан в $f" >&2
                exit 1
              }
            done

            # 3. Python-окружение доступно, CLI отдаёт справку
            PYTHONPATH="$out/lib/python3.13/site-packages" \
              "$out/bin/.portprotonqt-unwrapped" --help > help.txt 2>&1 || {
                echo "FAIL: CLI не запустился" >&2
                cat help.txt >&2
                exit 1
              }
            grep -q "PortProtonQt CLI" help.txt || {
              echo "FAIL: CLI не отдал справку" >&2
              cat help.txt >&2
              exit 1
            }

            # 4. Скомпилированные модули грузятся тем же интерпретатором,
            #    которым будут звать хелперы движка (регрессия на orjson).
            PYTHONPATH="$out/lib/python3.13/site-packages" \
              ${python}/bin/python3 -c "import orjson, babel" || {
                echo "FAIL: python-окружение неполное" >&2
                exit 1
              }

            echo "portprotonqt: все проверки ok"
            touch $out
          '';
        };
      }
    ) // {
      # Оверлей для системной интеграции (вне eachSystem, т.к. flake-utils
      # не поддерживает кастомные outputs вроде overlays)
      overlays = {
        default = final: _prev: {
          portprotonqt = self.packages.${final.stdenv.hostPlatform.system}.portprotonqt;
        };
      };
    };
}
