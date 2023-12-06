{
  lib,
  flake-parts-lib,
  ...
}: let
  inherit (flake-parts-lib) mkPerSystemOption;
  inherit (lib) mkOption types;
in {
  options.perSystem = mkPerSystemOption (
    {
      config,
      pkgs,
      ...
    }: let
      zmkConfig = config.zmk;

      zmk-python = pkgs.python3.withPackages (ps:
        with ps; [
          setuptools
          pip
          west
          # BASE: required to build or create images with zephyr
          #
          # While technically west isn't required it's considered in base since it's
          # part of the recommended workflow

          # used by various build scripts
          pyelftools

          # used by dts generation to parse binding YAMLs, also used by
          # twister to parse YAMLs, by west, zephyr_module,...
          pyyaml

          # YAML validation. Used by zephyr_module.
          pykwalify

          # used by west_commands
          canopen
          packaging
          progress
          psutil

          # for ram/rom reports
          anytree

          # intelhex used by mergehex.py
          intelhex

          west
        ]);

      gnuarmemb = pkgs.pkgsCross.arm-embedded.buildPackages.gcc;

      buildInputs = with pkgs; [
        gcc
        ninja
        dfu-util
        autoconf
        bzip2
        ccache
        libtool
        cmake
        xz
        dtc
        zmk-python
        gnuarmemb
      ];
    in {
      options = {
        zmk = {
          config-dir = mkOption {
            type = types.str;
            description = "The directory where the zmk config is stored";
            default = "./config";
          };

          matrix = mkOption {
            type = types.attrsOf (types.submodule ({
              name,
              config,
              ...
            }: let
              cfg = config;
            in {
              options = {
                board = mkOption {
                  type = types.str;
                  description = "The name of the board";
                  example = "nice_nano_v2";
                };
                shield = mkOption {
                  type = types.str;
                  description = "The name of the shield plus any shield adapters";
                  example = "corne_left nice_view_adapter nice_view";
                };
                name = mkOption {
                  type = types.str;
                  description = "The name of the keyboard, defaults to shield and board";
                  example = "name of this build, defaults to the key of this entry";
                  default = name;
                };
                build = mkOption {
                  type = types.package;
                  readOnly = true;
                  description = "The build script for this board and shield";
                };
              };

              config = let
                shield = cfg.shield;
                board = cfg.board;
                name = cfg.name;
              in {
                build = pkgs.writeShellApplication {
                  name = "build_${name}";
                  runtimeInputs = buildInputs;
                  checkPhase = "";
                  text = ''
                    echo "---<Building ${name}>---"
                    west build -s ./zmk/app -b ${board} -d build/${name} -- -DZMK_CONFIG=$PWD/${zmkConfig.config-dir} -DSHIELD=${shield}
                    echo '---<done>---'
                    echo '---<Copying to build/artifacts/${name}>---'
                    mkdir -p build/artifacts
                    cp build/${name}/zephyr/zmk.uf2 build/artifacts/${name}.uf2
                  '';
                };
              };
            }));
          };

          devShell = mkOption {
            type = types.package;
            readOnly = true;
            description = "The devshell for zmk, add it to your devShell";
            example = ''
              devShells.default = pkgs.mkShell {
                name = "zmk-keyboards";
                inputsFrom = [
                  config.zmk.devShell
                ];
              };
            '';
          };

          init = mkOption {
            type = types.package;
            readOnly = true;
            description = ''
              The init script for zmk and west, it is included in zmk devshell
              but exposed here for your convienence.

              This will clone zmk and init west.
            '';
          };

          update = mkOption {
            type = types.package;
            readOnly = true;
            description = ''
              The update script for west, it is included in zmk devshell
              but exposed here for your convienence.

              This will update west and export zephyr.
            '';
          };

          build = mkOption {
            type = types.package;
            readOnly = true;
            description = ''
              The build script for zmk, it is included in zmk devshell
              but exposed here for your convienence.

              This will iterate through all the keyboards in zmk.include and build them.
            '';
          };

          cleanup = mkOption {
            type = types.package;
            readOnly = true;
            description = ''
              The cleanup script for zmk, it is included in zmk devshell
              but exposed here for your convienence.

              This will remove the build directory and zmk.
            '';
          };
        };
      };

      config = let
        matrix = zmkConfig.matrix;

        cleanup = pkgs.writeShellScriptBin "cleanup" ''
          rm -rf build
          rm -rf zmk
          rm -rf zephyr
        '';
        init = pkgs.writeShellScriptBin "init" ''
          git clone https://github.com/zmkfirmware/zmk.git
          west init -l ${zmkConfig.config-dir}
        '';

        update = pkgs.writeShellScriptBin "update" ''
          west update
          west zephyr-export
        '';

        # iterate through the build matrix and build each keyboard
        build-boards = pkgs.writeShellApplication {
          name = "build-boards";
          runtimeInputs = [
            pkgs.gum
          ];
          text = let
            mtxi = lib.attrValues matrix;
          in ''
            ${lib.concatStringsSep "\n" (map (x: ''
                build_${x.name}() {
                  mkdir -p build/${x.name}
                  ${x.build}/bin/build_${x.name}
                }
              '')
              mtxi)}
            if [ "$#" -eq 1 ]; then
              if [ "$1" = "all" ]; then
                opt="$1"
              elif ! declare -F "build_$1" > /dev/null; then
                echo "build_$1 does not exist" >&2
                exit 1
              fi
              opt="$1"
            else
              opt=$(gum choose "all" ${lib.concatStringsSep " " (map (x: x.name) mtxi)})
            fi
            if [ "$opt" = "all" ]; then
              ${lib.concatStringsSep "\n  " (map (x: "build_${x.name}") mtxi)}
            else
              build_"$opt"
            fi
          '';
        };
      in {
        zmk.devShell = pkgs.mkShell {
          buildInputs =
            buildInputs
            ++ [
              init
              update
              build-boards
              cleanup
            ];
          shellHook = ''
            export ZEPHYR_TOOLCHAIN_VARIANT="gnuarmemb"
            export GNUARMEMB_TOOLCHAIN_PATH=${pkgs.gcc-arm-embedded};
          '';
        };
        zmk.init = init;
        zmk.update = update;
        zmk.build = build-boards;
        zmk.cleanup = cleanup;
      };
    }
  );
}
