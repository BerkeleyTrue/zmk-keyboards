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
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];
      imports = [
        inputs.boulder.flakeModule
      ];
      perSystem = {
        pkgs,
        inputs,
        config,
        ...
      }: {
        formatter = pkgs.alejandra;
        boulder = {
        };
        devShells.default = pkgs.mkShell {
          name = "zmk-keyboards";
          inputsFrom = [
            config.boulder.devShell
          ];
          packages = with pkgs; [
            python311Packages.west
          ];
        };
      };
    };
}
