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
    echo "🦆 zigduck dev shell  ($(uname -m))"

    _z2m_version=$(
      zigbee2mqtt --help 2>&1 \
        | grep -oE 'zigbee2mqtt-[0-9]+\.[0-9]+\.[0-9]+' \
        | head -n1 | cut -d'-' -f2
    )
    printf '  %-12s %s\n' "zigbee2mqtt:" "''${_z2m_version:-unknown}"

    _print_version() {
      printf '  %-12s %s\n' "$1" "''${2:-unknown}"
    }
    _print_version "mosquitto:"   "$(mosquitto -h 2>/dev/null | awk '/^mosquitto version/{print $3}')"
    _print_version "zigbee2mqtt:" "$_z2m_version"
    _print_version "rustc:"       "$(rustc --version 2>/dev/null | awk '{print $2}')"
    _print_version "python3:"     "$(python3 --version 2>/dev/null | awk '{print $2}')"
    _print_version "adb:"         "$(adb --version 2>/dev/null | head -n1 | awk '{print $NF}')"
    unset -f _print_version
    unset _z2m_version

    export MQTT_BROKER="''${MQTT_BROKER:-127.0.0.1}"
    export MQTT_USER="''${MQTT_USER:-duckmqtt}"
    export API_URL="''${API_URL:-http://127.0.0.1:13336}"
  '';
}
