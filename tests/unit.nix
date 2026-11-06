{
  pkgs,
  inputs,
  system
  ?
  pkgs.stdenv.hostPlatform.system,
  ...
} : let
  nix-unit = inputs.nix-unit.packages.${system}.default;
  wrapper = pkgs.writeText "yo-unit-tests.nix" ''
    let
      pkgs    = import ${inputs.nixpkgs.outPath} { system = "${system}"; };
      helpers = import ${./../lib} { lib = pkgs.lib; };
    in
    import ${./unit-tests.nix} { inherit pkgs helpers; }
  '';
in
pkgs.runCommand "yo-unit-tests" {
  nativeBuildInputs = [ nix-unit pkgs.nix ];
} ''
  export HOME=$TMPDIR
  nix-unit --eval-store auto \
    --extra-experimental-features 'nix-command flakes' \
    ${wrapper}
  touch $out
''
