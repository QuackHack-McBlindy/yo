{
  description = "Yo!";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    tinyFlake.url = "github:quackhack-mcblindy/tinyFlake";
  };

  outputs = { self, nixpkgs, tinyFlake, ... }@inputs:
    tinyFlake.lib.mkFlake {
      inherit self inputs;
      systems = [ "x86_64-linux" "aarch64-linux" ];
      packages = tinyFlake.lib.mapModules ./packages import;
      nixosModules.yo = { config, lib, pkgs, ... }:
        import ./module.nix {
          inherit config lib pkgs;
          self = self;
        };
      devShells = tinyFlake.lib.mapModules ./devShells (path: import path);
              
    };}
