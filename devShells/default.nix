# devShells/default.nix
{
  pkgs,
  system,
  self,
  inputs,
  ...
}:
{
  packages = with pkgs; [
    bash
    coreutils
    findutils
    gnused
    gawk
    jq
    curl
    git
    rustc
    cargo
  ];

  shellHook = ''
    echo "Entering devShell..."
  '';
}
