{
  description = "A nix shell for zmk";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    boulder = {
      url = "github:BerkeleyTrue/nix-boulder-banner/2532c51d42e7bfba0bbe2a6d88f882dc85291cf4";
    };

    keymap-drawer = {
      url = "github:caksoylar/keymap-drawer";
      flake = false;
    };

    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];
      imports = [
        inputs.boulder.flakeModule
        ./nix/zmk.nix
      ];
      perSystem = {
        pkgs,
        config,
        system,
        ...
      }: let
        inherit (inputs.poetry2nix.lib.mkPoetry2Nix {inherit pkgs;}) defaultPoetryOverrides mkPoetryApplication;

        keymap-drawer = mkPoetryApplication {
          projectDir = inputs.keymap-drawer;
          overrides =
            defaultPoetryOverrides.extend
            (self: super: {
              deptry =
                super.deptry.overridePythonAttrs
                (
                  old: {
                    buildInputs = (old.buildInputs or []) ++ [super.poetry];
                  }
                );
            });
        };

        server-keymap = pkgs.writeShellScriptBin "serve-keymap" ''
          ${pkgs.nodePackages.serve}/bin/serve -d keymap-drawer
        '';

        gen-keymap-img = pkgs.writeShellScriptBin "gen-keymap-img" ''
          ${keymap-drawer}/bin/keymap -c keymap-drawer/config.yml parse -z config/corne.keymap > keymap-drawer/corne.yaml
          ${keymap-drawer}/bin/keymap -c keymap-drawer/config.yml draw keymap-drawer/corne.yaml > keymap-drawer/corne.svg
        '';

        watch-keymap-drawer = pkgs.writeShellScriptBin "watch-keymap-drawer" ''
          echo "Watching for changes in keymap-drawer/corne.yaml"
          echo -e "./keymap-drawer/corne.yaml\n./keymap-drawer/config.yml" | ${pkgs.entr}/bin/entr ${gen-keymap-img}/bin/gen-keymap-img
        '';

        watch-keymap-and-server = pkgs.writeShellScriptBin "watch-keymap-and-server" ''
          echo "Watching for changes in keymap-drawer/corne.yaml"
          ${pkgs.nodePackages.concurrently}/bin/concurrently --name "keymap,serve" "${watch-keymap-drawer}/bin/watch-keymap-drawer" "${server-keymap}/bin/serve-keymap"
        '';
      in {
        formatter = pkgs.alejandra;
        boulder = {
          commands = [
            {
              description = "Generate keymap image";
              exec = gen-keymap-img;
              category = "documentation";
            }
            {
              description = "Watch keymap drawer";
              exec = watch-keymap-and-server;
              category = "documentation";
            }
            {
              description = "Initialize zmk";
              exec = config.zmk.init;
              category = "development";
            }
            {
              description = "Update zmk";
              exec = config.zmk.update;
              category = "development";
            }
            {
              description = "Build zmk uf2 files";
              exec = config.zmk.build;
              category = "development";
            }
          ];
        };
        zmk = {
          matrix = {
            corne-left = {
              board = "nice_nano_v2";
              shield = "corne_left nice_view_adapter nice_view";
            };
            corne-right = {
              board = "nice_nano_v2";
              shield = "corne_right nice_view_adapter nice_view";
            };
          };
        };
        devShells.default = pkgs.mkShell {
          name = "zmk-keyboards";
          inputsFrom = [
            config.boulder.devShell
            config.zmk.devShell
          ];
          packages = with pkgs; [
            keymap-drawer
            gen-keymap-img
            nodePackages.serve
            watch-keymap-drawer
            config.zmk.matrix.corne-left.build
          ];
        };
      };
    };
}
