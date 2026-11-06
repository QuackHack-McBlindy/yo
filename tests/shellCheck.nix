{
  pkgs,
  self,
  inputs,
  system
  ?
  pkgs.stdenv.hostPlatform.system,
  ...
} : let
  fakeSelf = self // {
    nixosConfigurations = { };
    packages = (self.packages or { }) // {
      ${system} = ((self.packages or { }).${system} or { }) // {
        yo-rs = { version = "0.0.0-test"; };
      };
    };
  };

  fixture = { pkgs, ... }: {
    yo.legacy = true;
    yo.scripts.echo = {
      description = "Voice-list quoting test";
      binary      = "${pkgs.coreutils}/bin/echo";
      category    = "Test";
      autoStart   = false;
      logLevel    = "WARNING";
      helpFooter  = "${pkgs.coreutils}/bin/echo";
      parameters = [{
        name        = "msg";
        type        = "string";
        description = "message";
        optional    = true;
        values = [
          "Takkrona 1"
          "Motion Sensor Sovrum"
          "Dimmer Switch Kök"
          "Taket Sovrum 2"
          "Kök Bänk Slinga"
          "Sänggavel"
          "Dörrslinga"
          "Vägg"
          "två minuter"
          "en halvtimme"
          "Ocean's Eleven"
          "12:30"
        ];
      }];
    };
  };

  host = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = { self = fakeSelf; };
    modules = [ self.nixosModules.yo fixture ];
  };
  yoEcho = "${host.config.yo.pkgs}/bin/yo-echo";
in
pkgs.runCommand "yo-shellcheck" {
  nativeBuildInputs = [ pkgs.shellcheck ];
} ''
  set -euo pipefail
  shopt -s nullglob

  n=0
  for f in ${host.config.yo.pkgs}/bin/yo-*; do
    name=$(basename "$f")
    case "$name" in
      yo-do|yo-say) continue ;;
    esac
    echo "> shellcheck $name"
    shellcheck -s bash -S error -x "$f"
    n=$((n+1))
  done
  echo "shellchecked $n generated scripts"


  echo "> behaviour: realistic values accepted"
  ${yoEcho} --msg 'Takkrona 1'            >/dev/null
  ${yoEcho} --msg 'Motion Sensor Sovrum'  >/dev/null
  ${yoEcho} --msg 'Dimmer Switch Kök'     >/dev/null
  ${yoEcho} --msg 'Taket Sovrum 2'        >/dev/null
  ${yoEcho} --msg 'Kök Bänk Slinga'       >/dev/null
  ${yoEcho} --msg 'Sänggavel'             >/dev/null
  ${yoEcho} --msg 'Dörrslinga'            >/dev/null
  ${yoEcho} --msg 'Vägg'                  >/dev/null
  ${yoEcho} --msg 'två minuter'           >/dev/null
  ${yoEcho} --msg 'en halvtimme'          >/dev/null
  ${yoEcho} --msg "Ocean's Eleven"        >/dev/null
  ${yoEcho} --msg '12:30'                 >/dev/null


  echo "> behaviour: invalid values rejected"
  if ${yoEcho} --msg 'not in the list' >/dev/null 2>&1; then
    echo "FAIL: invalid value was accepted" >&2
    exit 1
  fi

  touch $out
''
