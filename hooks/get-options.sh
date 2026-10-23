#!/usr/bin/env bash
# hooks/get-options.sh
# run before build-docs.sh
# usage:
# bash hooks/get-options.sh \
#   --flake /path/to/your/flake \
#   --hostname desktop

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"   # repo root
HOOKS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"       # hooks/ (where this script lives)
PROJECT_TOML="$SCRIPT_DIR/project.toml"
FLAKE_REF="$SCRIPT_DIR"
HOSTNAME_ARG="${HOSTNAME:-}"
option1=""
OPTIONAL_ARG2=""

usage() {
  cat >&2 <<'EOF'
Usage: get-options.sh [--flake REF] [--hostname HOST]
                      [--option1 PATH] [--option2 PATH]

Options:
  --flake REF       Nix flake path or reference (defaults to project directory)
  --hostname HOST   NixOS configuration name (defaults to $HOSTNAME)
  --option1 PATH    Attribute path for options.json (overrides project.toml)
  --option2 PATH    Attribute path for service.json (overrides project.toml)
  -h, --help        Show this help

Default option paths are read from project.toml:
  [options]
  include = ["yo", "services.yo-rs"]
EOF
}


if [[ ! -f "$PROJECT_TOML" ]]; then
  echo "Error: project.toml not found: $PROJECT_TOML" >&2
  exit 1
fi

mapfile -t CONFIG_OPTIONS < <(
  python3 -c '
import sys, tomllib

with open(sys.argv[1], "rb") as f:
    config = tomllib.load(f)

for option in config.get("options", {}).get("include", []):
    print(option)
' "$PROJECT_TOML"
)

option1="${CONFIG_OPTIONS[0]:-}"
OPTIONAL_ARG2="${CONFIG_OPTIONS[1]:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --flake)
      [[ $# -ge 2 ]] || {
        echo "Missing value for --flake" >&2
        usage
        exit 1
      }
      FLAKE_REF="$2"
      shift 2
      ;;
    --flake=*)
      FLAKE_REF="${1#*=}"
      shift
      ;;
    --hostname)
      [[ $# -ge 2 ]] || {
        echo "Missing value for --hostname" >&2
        usage
        exit 1
      }
      HOSTNAME_ARG="$2"
      shift 2
      ;;
    --hostname=*)
      HOSTNAME_ARG="${1#*=}"
      shift
      ;;
    --option1)
      [[ $# -ge 2 ]] || {
        echo "Missing value for --option1" >&2
        usage
        exit 1
      }
      option1="$2"
      shift 2
      ;;
    --option1=*)
      option1="${1#*=}"
      shift
      ;;
    --option2)
      [[ $# -ge 2 ]] || {
        echo "Missing value for --option2" >&2
        usage
        exit 1
      }
      OPTIONAL_ARG2="$2"
      shift 2
      ;;
    --option2=*)
      OPTIONAL_ARG2="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

: "${FLAKE_REF:?--flake must not be empty}"
: "${HOSTNAME_ARG:?--hostname (or \$HOSTNAME) is required}"
: "${option1:?No options configured in project.toml; provide --option1}"


build_doc() {
  local opt_path="$1"
  local out="$2"
  local nix_out

  echo "Building $out from option path: $opt_path" >&2

  nix_out="$(
    cd "$SCRIPT_DIR"

    nix build \
      --impure \
      --no-link \
      --print-out-paths \
      --expr "
        let
          flake = builtins.getFlake \"${FLAKE_REF}\";
          pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
          cfg = flake.nixosConfigurations.\"${HOSTNAME_ARG}\";
          doc = pkgs.nixosOptionsDoc {
            options = cfg.options.${opt_path};
            warningsAreErrors = false;
          };
        in
          doc.optionsJSON
      "
  )"

  jq . "$nix_out/share/doc/nixos/options.json" > "$out"
}

cd "$SCRIPT_DIR"

build_doc "$option1" "$HOOKS_DIR/options.json"
files=("$HOOKS_DIR/options.json")

if [[ -n "$OPTIONAL_ARG2" ]]; then
  build_doc "$OPTIONAL_ARG2" "$HOOKS_DIR/service.json"
  files+=("$HOOKS_DIR/service.json")
fi

# echo undocumented options and examples.
for f in "${files[@]}"; do
  jq -r --arg f "$(basename "$f")" '
    def undoc:
      (.value.description == null)
      or (.value.description == "")
      or (.value.description == "This option has no description.");

    def noExample:
      ((.value.example.text // "") == "");

    (to_entries | length) as $total
    | ([to_entries[] | select(undoc)]) as $missingDesc
    | ([to_entries[] | select(noExample)]) as $missingEx

    | "### \($f) — \($total) options",
      "  descriptions: \($total - ($missingDesc|length))/\($total) (\(((if $total == 0 then 100 else (($total - ($missingDesc|length)) / $total * 100) end) * 100 | floor) / 100)%)",
      "  examples:     \($total - ($missingEx|length))/\($total) (\(((if $total == 0 then 100 else (($total - ($missingEx|length)) / $total * 100) end) * 100 | floor) / 100)%)",
      "",
      (
        if ($missingDesc|length) == 0 then
          "  Missing descriptions: (none)"
        else
          "  Missing descriptions:",
          ($missingDesc[] | "    - \(.key)")
        end
      ),
      "",
      (
        if ($missingEx|length) == 0 then
          "  Missing examples: (none)"
        else
          "  Missing examples:",
          ($missingEx[] | "    - \(.key)")
        end
      )
  ' "$f"

  echo
done
