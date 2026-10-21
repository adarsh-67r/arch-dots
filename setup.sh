#!/usr/bin/env bash
# One-line nagi install:  curl -fsSL https://raw.githubusercontent.com/adarsh-67r/nagi/main/setup.sh | bash
# Clones nagi to ~/nagi (or updates it) and runs install.sh; extra args pass through (… | bash -s -- --all).
set -euo pipefail

# Wrapped in a function so a cut-off download runs nothing.
main() {
  local dir=${NAGI_DIR:-$HOME/nagi}
  command -v git >/dev/null || sudo pacman -S --needed --noconfirm git
  if [[ -d $dir/.git ]]; then
    git -C "$dir" pull --ff-only
  else
    git clone https://github.com/adarsh-67r/nagi "$dir"
  fi
  # stdin is this script when piped from curl; the menu and Dux installer need the keyboard.
  exec "$dir/install.sh" "$@" </dev/tty
}

main "$@"
