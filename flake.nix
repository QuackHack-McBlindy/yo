{
  description = "Yo!";
  inputs = {
    nixpkgs.url   = "github:NixOS/nixpkgs/nixos-unstable";
    nix-unit.url  = "github:nix-community/nix-unit";
    tinyFlake.url = "github:quackhack-mcblindy/tinyFlake";
  };

  outputs = { self, nixpkgs, tinyFlake, ... }@inputs:
    tinyFlake.lib.mkFlake { inherit self inputs;
      systems         = [ "x86_64-linux" "aarch64-linux" ];
      packages        = tinyFlake.lib.mapModules ./packages import;
      devShells       = tinyFlake.lib.mapModules ./devShells (path: import path);
      checks = {
        unit          = import ./tests/unit.nix;
        shellCheck    = import ./tests/shellCheck.nix;
      };
      nixosModules.yo = { config, lib, pkgs, ... }:
        import ./module.nix { inherit config lib pkgs;
          self  = self;
        };


    };}
