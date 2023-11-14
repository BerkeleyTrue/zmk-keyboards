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
    }: {
      options = {
        zmk.include = mkOption {
          type = types.listOf (types.submodule {
            board = mkOption {
              type = types.str;
              default = "The name of the board";
              example = "nice_nano_v2";
            };
            shield = mkOption {
              type = types.str;
              default = "The name of the shield plus any shield adapters";
              example = "corne_left nice_view_adapter nice_view";
            };
            name = mkOption {
              type = types.str;
              default = "The name of the keyboard, defaults to shield and board";
              example = "my-awesome-corne or defaults to corne_left nice_view_adapter nice_view - nice_nano_v2";
            };
          });
        };

        zmk.devShell = mkOption {
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

        zmk.init = mkOption {
          type = types.package;
          readOnly = true;
          description = ''
            The init script for zmk and west, it is included in zmk devshell
            but exposed here for your convienence.

            This will clone zmk and init west.
          '';
        };

        zmk.update = mkOption {
          type = types.package;
          readOnly = true;
          description = ''
            The update script for west, it is included in zmk devshell
            but exposed here for your convienence.

            This will update west and export zephyr.
          '';
        };

        zmk.build = mkOption {
          type = types.package;
          readOnly = true;
          description = ''
            The build script for zmk, it is included in zmk devshell
            but exposed here for your convienence.

            This will iterate through all the keyboards in zmk.include and build them.
          '';
        };
      };

      config = let
        buildMatrix = config.zmk.include or [];

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

        init = pkgs.writeShellScriptBin "init" ''
          git clone https://github.com/zmkfirmware/zmk.git
          west init -l config
        '';

        update = pkgs.writeShellScriptBin "update" ''
          west update
          west zephyr-export
        '';

        mkBuild = {
          shield,
          board,
          name,
          zmkDir ? "./zmk",
          zephyrDir ? "./zephyr",
          configDir ? "./config",
        }:
          pkgs.writeShellApplication {
            name = "build-${shield}-${board}";
            runtimeInputs = buildInputs;
            checkPhase = "";
            text = ''
              cd config
              node ../../../briefs/import-zmk.js ../../../briefs/briefs-canary.tsv
              cd ..
              source ${zephyrDir}/zephyr-env.sh
              west build -s ${zmkDir}/app -b ${board} -d build/${name} -- -DZMK_CONFIG=$PWD/${configDir} -DSHIELD=${shield}
              echo 'done'
            '';
          };

        # iterate through the build matrix and build each keyboard
        build = pkgs.writeShellScriptBin "build" ''
          ${lib.concatStringsSep "\n"
            (map
              (
                name: keyboard: let
                  shield = keyboard.shield;
                  board = keyboard.board;
                  name = keyboard.name or "${shield}-${board}";
                  build = mkBuild {
                    shield = shield;
                    board = board;
                    name = name;
                  };
                in ''
                  echo "Building ${name}"
                  mkdir -p build/${name}
                  ${build}/bin/build-${shield}-${board}
                ''
              )
              buildMatrix)}
        '';
      in {
        zmk.devShell = pkgs.mkShell {
          buildInputs =
            buildInputs
            ++ [
              init
              update
            ];
          ZEPHYR_TOOLCHAIN_VARIANT = "gnuarmemb";
          GNUARMEMB_TOOLCHAIN_PATH = pkgs.gcc-arm-embedded;
        };
        zmk.init = init;
        zmk.update = update;
        zmk.build = build;
      };
    }
  );
}
