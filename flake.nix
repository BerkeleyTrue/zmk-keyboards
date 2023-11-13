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

        gen-keymap-img = pkgs.writeShellScriptBin "gen-keymap-img" ''
          #!${pkgs.stdenv.shell}
          ${keymap-drawer}/bin/keymap -c keymap-drawer/config.yml parse -z config/corne.keymap > keymap-drawer/corne.yaml
          ${keymap-drawer}/bin/keymap -c keymap-drawer/config.yml draw keymap-drawer/corne.yaml > keymap-drawer/corne.svg
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
          ];
        };
        devShells.default = pkgs.mkShell {
          name = "zmk-keyboards";
          inputsFrom = [
            config.boulder.devShell
          ];
          packages = with pkgs; [
            python311Packages.west
            keymap-drawer
            gen-keymap-img
          ];
        };
      };
    };
}
