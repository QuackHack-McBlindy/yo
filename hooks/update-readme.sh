#!/usr/bin/env bash
# scripts/update-readme.sh

set -euo pipefail

if [ -z "${UPDATE_README_IN_NIX_DEVELOP:-}" ]; then
  export UPDATE_README_IN_NIX_DEVELOP=1
  _self="$(readlink -f "$0")"
  exec nix develop --command bash "$_self" "$@"
fi


get_version() {
  {
    case "$1" in
      adb)      timeout 5 adb --version 2>/dev/null | head -n1 | awk '{print $5}' ;;
      nixos)    timeout 5 nixos-version 2>/dev/null | cut -d. -f1-2 ;;
      kernel)   timeout 5 uname -r 2>/dev/null | cut -d'-' -f1 ;;
      nix)      timeout 5 nix --version 2>/dev/null | awk '{print $3}' ;;
      bash)     timeout 5 bash --version 2>/dev/null | head -n1 | awk '{print $4}' | cut -d'(' -f1 ;;
      gnome)    timeout 5 gnome-shell --version 2>/dev/null | awk '{print $3}' ;;
      python)   timeout 5 python3 --version 2>/dev/null | awk '{print $2}' ;;
      rust)     timeout 5 rustc --version 2>/dev/null | awk '{print $2}' ;;
      mqtt)     timeout 5 mosquitto -h 2>/dev/null | awk '/^mosquitto version/{print $3}' ;;
      yo)       timeout 5 yo --version 2>/dev/null | awk '/^yo version /{print $3; exit}' ;;
      zigduck)  timeout 5 zigduck-cli --version 2>/dev/null | awk '/^zigduck version /{print $3; exit}' ;;
      z2m)
        local bin
        bin="$(readlink -f "$(command -v zigbee2mqtt 2>/dev/null)" 2>/dev/null)" || true
        printf '%s\n' "$bin" \
          | grep -oE 'zigbee2mqtt-[0-9]+\.[0-9]+\.[0-9]+' \
          | head -n1 | cut -d- -f2
        ;;
      *)      echo "unknown" ;;
    esac
  } || true
}

declare -A BADGE_SOURCE=(
  [ADB]="adb"
  [NixOS]="nixos"
  [License]="static"
  [Nix]="nix"
  ["Linux Kernel"]="kernel"
  [GNOME]="gnome"
  [Bash]="bash"
  [Python]="python"
  [Rust]="rust"
  [Mosquitto]="mqtt"
  [Zigbee2MQTT]="z2m"
  [yo]="yo"
  [zigduck]="zigduck"
)

declare -A BADGE_URL=(
  [ADB]='https://img.shields.io/badge/ADB-{version}-green?style=flat-square&logo=android&logoColor=white'
  [NixOS]='https://img.shields.io/badge/NixOS-{version}-blue?style=flat-square&logo=NixOS&logoColor=white'
  [License]='https://img.shields.io/badge/license-MIT-black?style=flat-square&logo=opensourceinitiative&logoColor=white'
  [Nix]='https://img.shields.io/badge/Nix-{version}-blue?style=flat-square&logo=nixos&logoColor=white'
  ["Linux Kernel"]='https://img.shields.io/badge/Linux-{version}-red?style=flat-square&logo=linux&logoColor=white'
  [GNOME]='https://img.shields.io/badge/GNOME-{version}-purple?style=flat-square&logo=gnome&logoColor=white'
  [Bash]='https://img.shields.io/badge/bash-{version}-red?style=flat-square&logo=gnubash&logoColor=white'
  [Python]='https://img.shields.io/badge/Python-{version}-%23FFD43B?style=flat-square&logo=python&logoColor=white'
  [Rust]='https://img.shields.io/badge/Rust-{version}-orange?style=flat-square&logo=rust&logoColor=white'
  [Mosquitto]='https://img.shields.io/badge/Mosquitto-{version}-yellow?style=flat-square&logo=eclipsemosquitto&logoColor=white'
  [Zigbee2MQTT]='https://img.shields.io/badge/Zigbee2MQTT-{version}-yellow?style=flat-square&logo=zigbee2mqtt&logoColor=white'
  [yo]='https://img.shields.io/badge/yo-{version}-black?style=flat'
  [zigduck]='https://img.shields.io/badge/🦆%20zigduck-{version}-black?style=flat'
)

update_version_badges() {
  local readme="${1:-README.md}"

  [ -f "$readme" ] || return 0
  grep -qF '<!-- VERSIONS_START -->' "$readme" || return 0
  grep -qF '<!-- VERSIONS_END -->'   "$readme" || return 0

  local section_file temp_file
  section_file="$(mktemp)"
  temp_file="$(mktemp)"
  trap 'rm -f "${section_file:-}" "${temp_file:-}"' EXIT

  awk '
    /<!-- VERSIONS_START -->/ { inside=1; next }
    /<!-- VERSIONS_END -->/   { inside=0 }
    inside
  ' "$readme" > "$section_file"

  local name source version url
  for name in "${!BADGE_SOURCE[@]}"; do
    grep -qF "![$name](" "$section_file" || continue

    source="${BADGE_SOURCE[$name]}"
    if [ "$source" = "static" ]; then
      url="${BADGE_URL[$name]}"
    else
      version="$(get_version "$source")"
      if [ -z "$version" ] || [ "$version" = "unknown" ]; then
        echo "[update-readme] skipping '$name': could not detect version" >&2
        continue
      fi
      url="${BADGE_URL[$name]//\{version\}/$version}"
    fi

    NAME="$name" URL="$url" perl -i -0pe '
      my $n = $ENV{NAME};
      my $u = $ENV{URL};
      s{!\[\Q$n\E\]\([^)]*\)}{![$n]($u)}g;
    ' "$section_file"

    if [ "$source" = "static" ]; then
      echo "[update-readme] updated '$name' (static)" >&2
    else
      echo "[update-readme] updated '$name' -> $version" >&2
    fi
  done

  awk -v sf="$section_file" '
    /<!-- VERSIONS_START -->/ {
      print
      while ((getline line < sf) > 0) print line
      close(sf)
      skip=1
      next
    }
    /<!-- VERSIONS_END -->/ { skip=0 }
    !skip
  ' "$readme" > "$temp_file"

  mv "$temp_file" "$readme"
}


update_version_badges "${1:-README.md}"
