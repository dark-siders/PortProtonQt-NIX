{
  description = "PortProtonQt — PortProton Qt frontend (official Linux-Gaming.ru repo)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    portprotonqt-src.url = "git+https://git.linux-gaming.ru/Linux-Gaming/PortProtonQt";
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
        ]);

        # Build PortProtonQt via meson
        portprotonqt = pkgs.stdenvNoCC.mkDerivation {
          pname = "portprotonqt";
          version = "1.4.1";

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
          ];

          buildInputs = with pkgs; [
            sdl3
            vulkan-loader
            vulkan-headers
            python
          ];

          # Meson build
          mesonFlags = [ "-Dnightly=false" ];

          #--- Обёртка: запуск через steam-run (FHS), как в Redm00use
          postInstall = ''
            mv $out/bin/portprotonqt $out/bin/.portprotonqt-unwrapped

            #--- NixOS/FHS: steam-run отдаёт в песочницу PATH=/run/wrappers/bin:/usr/bin:...
            # поэтому `python3` там — ЧУЖОЙ интерпретатор. Наши скомпилированные
            # модули (orjson, pyside6) он не грузит, а чистые (babel) грузит —
            # отсюда разнородные ошибки. Подставляем абсолютный python из env
            # во все вызовы хелперов PortProton.
            # Внимание: functions_helper БЕЗ расширения .sh — глоб по *.sh его не ловит.
            # --replace-fail (а не просто --replace) упадёт сам, если апстрим
            # переименует вызовы: ломаться молча нельзя.
            for f in "$out/share/portproton/scripts/start.sh" \
                     "$out/share/portproton/scripts/functions_helper" ; do
              substituteInPlace "$f" \
                --replace-fail "python3 -m portprotonqt" \
                               "${python}/bin/python3 -m portprotonqt"
            done

            # Строгая проверка: если апстрим переименует вызовы, молча ломаться
            # нельзя — падаем на сборке, а не у пользователя в GUI.
            if grep -rqE "(^|[^/[:alnum:]_.-])python3 -m portprotonqt" \
                 "$out/share/portproton/scripts/start.sh" \
                 "$out/share/portproton/scripts/functions_helper" ; then
              echo "portprotonqt: остались голые вызовы 'python3 -m portprotonqt'" >&2
              exit 1
            fi

            makeWrapper ${lib.getExe pkgs.steam-run} $out/bin/portprotonqt \
              --add-flags $out/bin/.portprotonqt-unwrapped \
              --prefix PYTHONPATH ':' "$out/lib/python3.13/site-packages" \
              --prefix XDG_DATA_DIRS ':' "$out/share" \
              --prefix PATH ':' "$out/bin:${python}/bin" \
              --set STEAM_RUNTIME 1 \
              --set STEAM_RUNTIME_PREFER_FRESH 1

            #--- NixOS/steam-run: kill_portwine() убивает собственный контейнер
            # kill_portwine() ищет bwrap через `pgrep -f wrap | grep PortProton`
            # и шлёт ему SIGKILL. Под steam-run этот bwrap — наш же контейнер,
            # а у bwrap стоит --die-with-parent, поэтому сессия умирает с
            # SIGKILL (137), и GUI показывает "ProcessError.Crashed code: 9".
            # Выкидываем из списка на kill все bwrap-PID, являющиеся предками
            # текущего шелла. Вставляем перед циклом kill — он единственный.
            _pp_fh="$out/share/portproton/scripts/functions_helper"
            _pp_anchor='    for pw_kill_pids in ''${bwrap_pids} ''${wine_pids}; do'
            if ! grep -q "_pw_collect_ancestor_pids" "$_pp_fh" ; then
              if ! grep -qF "$_pp_anchor" "$_pp_fh" ; then
                echo "portprotonqt: НЕ НАЙДЕН якорь kill_portwine в functions_helper" >&2
                exit 1
              fi
              # Блок передаём через переменную окружения, а не `awk -v`:
              # -v переинтерпретирует escape-последовательности в значении.
              _pp_block="$(cat <<'PPBLOCK'
    # --- NixOS/steam-run fix: never SIGKILL our own bwrap container ---
    _pw_collect_ancestor_pids() {
        local pid=$$ ppid out=""
        while [[ -n "$pid" && "$pid" -gt 1 ]]; do
            ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d '[:space:]')
            [[ -z "$ppid" ]] && break
            [[ "$ppid" == "0" || "$ppid" == "$pid" ]] && break
            out="$out $ppid"
            pid=$ppid
        done
        echo "$out"
    }
    if [[ -n "''${bwrap_pids:-}" ]]; then
        _pw_ancestors="$(_pw_collect_ancestor_pids)"
        _pw_kept=""
        for _pw_bwrap in $bwrap_pids; do
            case " $_pw_ancestors " in
                *" $_pw_bwrap "*) continue ;;
            esac
            _pw_kept="''${_pw_kept:+$_pw_kept }$_pw_bwrap"
        done
        bwrap_pids="$_pw_kept"
    fi
    # --- end steam-run fix ---
PPBLOCK
)"
              _pp_block="$_pp_block" awk -v anchor="$_pp_anchor" '
                !done && index($0, anchor) { printf "%s\n", ENVIRON["_pp_block"]; done=1 }
                { print }
              ' "$_pp_fh" > "$_pp_fh.tmp"
              mv "$_pp_fh.tmp" "$_pp_fh"
              grep -q "_pw_collect_ancestor_pids" "$_pp_fh" || {
                echo "portprotonqt: не удалось вставить защиту kill_portwine" >&2
                exit 1
              }
              echo "portprotonqt: защита kill_portwine установлена"
            fi
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
              nativeBuildInputs = [ python pkgs.bash ];
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

            # 1. Обёртка обязана звать steam-run и прописывать PYTHONPATH
            wrapper=$out/bin/portprotonqt
            grep -q "steam-run" "$wrapper" || {
              echo "FAIL: обёртка не вызывает steam-run" >&2
              exit 1
            }
            grep -q "python3.13/site-packages" "$wrapper" || {
              echo "FAIL: в обёртке нет PYTHONPATH" >&2
              exit 1
            }

            # 2. Регресс: NixOS-правки на месте (апстрим их не содержит)
            #    a) вызовы python3 -m указывают на интерпретатор из env
            if grep -rqE "(^|[^/[:alnum:]_.-])python3 -m portprotonqt" \
                 "$out/share/portproton/scripts/start.sh" \
                 "$out/share/portproton/scripts/functions_helper" ; then
              echo "FAIL: остались голые вызовы python3 -m portprotonqt" >&2
              exit 1
            fi
            #    b) защита kill_portwine от самоубийства контейнера
            grep -q "_pw_collect_ancestor_pids" \
              "$out/share/portproton/scripts/functions_helper" || {
              echo "FAIL: нет защиты kill_portwine" >&2
              exit 1
            }
            #    c) синтаксис движка не сломан
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