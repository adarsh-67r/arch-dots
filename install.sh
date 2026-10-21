#!/usr/bin/env bash
# nagi (凪): Arch Linux + niri + Dux Shell setup.
#   ./install.sh        restore everything on a fresh archinstall system (run as your user, not root);
#                       a menu picks the optional groups below
#   ./install.sh --all  same, with every optional group and no menu
#   ./install.sh save   copy this machine's setup into the repo
#   ./install.sh update apply the repo to an installed system (new packages, configs, scripts); nagi-update pulls first
set -euo pipefail
cd "$(dirname "$0")"
source lib/ui.sh

# Dotfiles, relative to $HOME, saved under dotfiles/<group>/. Never add anything holding tokens/keys.
SHELL_FILES=(.zshrc .config/fastfetch .config/ohmyposh .config/bat)
# niri + Dux Shell. Applied after the Dux installer, which overwrites niri and kitty configs on every run.
DESKTOP_FILES=(.config/niri/config.kdl .config/niri/dms .config/DankMaterialShell/settings.json .config/kitty/kitty.conf
  .config/environment.d/95-qt.conf .config/gtk-3.0/settings.ini .config/gtk-4.0/settings.ini .config/gtk-3.0/gtk.css .config/gtk-4.0/gtk.css .gtkrc-2.0
  .config/xdg-desktop-portal .config/fontconfig)
APP_FILES=(.config/btop .config/cava .config/htop .config/topgrade.toml .config/mimeapps.list .config/spotify-flags.conf)
WALLPAPER_DIR=Pictures/wallpaper
# Set on first login of a fresh install; every color is generated from it.
DEFAULT_WALLPAPER=giyu.jpeg
# Generic /etc files.
ETC_FILES=(X11/xorg.conf.d/00-keyboard.conf snapper/configs/root systemd/zram-generator.conf NetworkManager/conf.d/wifi-backend.conf pacman.d/hooks/99-grub-install.hook pacman.d/hooks/99-grub-mkconfig.hook)
# HP OMEN 16 (board 8BCD) only, in hardware/omen-8bcd/: AMD iGPU + RTX 4050 sleep/resume fixes.
OMEN_ETC_FILES=(modprobe.d/nvidia-s0ix.conf systemd/system/greetd.service.d/gpu.conf)
# hdmi-mode + nv-run go to ~/.local/bin, greeter-gpu to /usr/local/bin.
OMEN_SCRIPTS=(.local/bin/hdmi-mode .local/bin/nv-run)
OMEN_BOARD=8BCD

# Only packages from these repos are kept; anything else installed locally is left out.
REPOS=(core extra multilib chaotic-aur)
# Gaming packages are kept out of the saved lists; scripts/steam-aio installs them (its --list, plus wine/nine leftovers here).
SKIP='^(lib32-)?(wine.*|steam|protonplus|gallium-nine.*|mangohud|mangoverlay|gamemode|game-devices-udev)$'
# GPU drivers are picked per machine by gpu_drivers(), not copied from mine.
GPU='^(lib32-)?(nvidia.*|opencl-nvidia.*|vulkan-radeon|vulkan-intel|intel-media-driver|xf86-video-.*)$'

# App catalog (packages/apps.txt). Catalog packages are pulled out of the saved lists and only installed when picked.
mapfile -t APPS < <(grep -v '^#' packages/apps.txt)
declare -A KERNELS=(
  ["CachyOS + LTS"]="linux-cachyos linux-cachyos-headers linux-cachyos-lts linux-cachyos-lts-headers"
  ["CachyOS"]="linux-cachyos linux-cachyos-headers"
  ["Stock"]=""
)
# Menu choices. Empty kernel/warp (as in `update`) means: install none of the optional packages.
declare -A CFG=([kernel]="" [gpu]=auto [parallel]=5 [warp]="" [look]=nagi)
# The look picked at install; `update` and `changed` keep to it.
LOOK_FILE=~/.config/nagi/look
if [[ -f $LOOK_FILE ]]; then CFG[look]=$(<"$LOOK_FILE"); fi
PICKED=()  # app labels

SERVICES=(NetworkManager bluetooth greetd power-profiles-daemon systemd-timesyncd
  grub-btrfsd snapper-timeline.timer snapper-cleanup.timer docker.socket warp-svc
  nvidia-suspend nvidia-resume nvidia-hibernate nvidia-powerd)

# nagi's glass styling (transparency + blur). With the "dux" look these stay as the Dux installer wrote them.
is_style() { [[ ${CFG[look]} == dux && $1 =~ ^\.config/(niri|DankMaterialShell|kitty)/ ]]; }

is_omen() { [[ "$(cat /sys/class/dmi/id/board_name 2>/dev/null)" == "$OMEN_BOARD" ]]; }

copy_group() {  # copy_group <group> <files...>
  local g=$1 f; shift
  for f in "$@"; do
    [[ -e ~/$f ]] || { echo "skip (missing): ~/$f"; continue; }
    mkdir -p "dotfiles/$g/$(dirname "$f")"; cp -a ~/"$f" "dotfiles/$g/$f"
  done
}

save() {
  local gaming; gaming=$(scripts/steam-aio --list)
  comm -12 <(pacman -Qqen | sort) <(pacman -Slq "${REPOS[@]}" | sort -u) | grep -Ev "$SKIP" | grep -vxF "$gaming" | grep -Ev "$GPU" > packages/pacman.txt
  pacman -Qqem | grep -v -- '-debug$' | grep -Ev "$SKIP" | grep -vxF "$gaming" | grep -Ev "$GPU" > packages/aur.txt
  # wallpapers/ is curated in the repo (size variants live only there), so it isn't saved from this machine.
  rm -rf dotfiles system hardware/omen-8bcd/etc
  copy_group shell "${SHELL_FILES[@]}"
  local f desktop=()
  for f in "${DESKTOP_FILES[@]}"; do is_style "$f/" || desktop+=("$f"); done
  copy_group desktop "${desktop[@]}"
  copy_group apps "${APP_FILES[@]}"
  # Store home paths as a placeholder so the configs work for any username.
  grep -rlIF "$HOME" dotfiles | xargs -r sed -i "s|$HOME|__HOME__|g" || true  # grep exits 1 when nothing matches
  for f in "${ETC_FILES[@]}"; do mkdir -p "system/$(dirname "$f")"; cp /etc/"$f" "system/$f"; done
  for f in "${OMEN_ETC_FILES[@]}"; do mkdir -p "hardware/omen-8bcd/etc/$(dirname "$f")"; cp /etc/"$f" "hardware/omen-8bcd/etc/$f"; done
  for f in "${OMEN_SCRIPTS[@]}"; do cp ~/"$f" hardware/omen-8bcd/; done
  cp /usr/local/bin/greeter-gpu hardware/omen-8bcd/
  echo "Saved. Review with: git diff"
}

pacman_tweaks() {
  local o
  for o in Color ILoveCandy VerbosePkgLists DisableDownloadTimeout; do
    grep -q "^$o" /etc/pacman.conf || sudo sed -i "/^\[options\]/a $o" /etc/pacman.conf
  done
  sudo sed -i "s/^#\?ParallelDownloads.*/ParallelDownloads = ${CFG[parallel]}/" /etc/pacman.conf
  # Build AUR packages on all cores.
  sudo sed -i "s/^#\?MAKEFLAGS=.*/MAKEFLAGS=\"-j$(nproc)\"/" /etc/makepkg.conf
}

add_repos() {
  if ! grep -q '^\[chaotic-aur\]' /etc/pacman.conf; then
    # Keyservers are flaky; try several.
    local ks
    for ks in keyserver.ubuntu.com keys.openpgp.org pgp.mit.edu; do
      timeout 30 sudo pacman-key --recv-key 3056513887B78AEB --keyserver $ks && break
    done
    sudo pacman-key --lsign-key 3056513887B78AEB
    sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
      'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
    printf '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' | sudo tee -a /etc/pacman.conf >/dev/null
  fi
  sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
  sudo pacman -Syu --noconfirm
}

# GPUs by PCI vendor: amd, intel, nvidia (open module) or nvidia-legacy (580xx driver).
detect_gpus() {
  local ids dev out=()
  ids=$(lspci -nn | grep -E 'VGA|3D|Display' | grep -oE '\[[0-9a-f]{4}:[0-9a-f]{4}\]')
  if grep -q '1002:' <<<"$ids"; then out+=(amd); fi
  if grep -q '8086:' <<<"$ids"; then out+=(intel); fi
  if grep -q '10de:' <<<"$ids"; then
    # Turing (device 0x1e00) and newer use the open kernel module; older cards need the 580xx legacy driver.
    dev=$(grep -oE '10de:[0-9a-f]{4}' <<<"$ids" | head -1 | cut -d: -f2)
    if (( 16#$dev >= 16#1e00 )); then out+=(nvidia); else out+=(nvidia-legacy); fi
  fi
  if (( ${#out[@]} == 0 )) && systemd-detect-virt -q 2>/dev/null; then out=(vm); fi
  echo "${out[*]}"
}

# Drivers for the GPUs picked in the menu (or detected).
gpu_drivers() {
  local gpus=${CFG[gpu]} g pkgs=(mesa lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader)
  sudo pacman -S --needed --noconfirm pciutils
  [[ $gpus == auto ]] && gpus=$(detect_gpus)
  for g in $gpus; do
    case $g in
      amd) pkgs+=(vulkan-radeon lib32-vulkan-radeon) ;;
      intel) pkgs+=(vulkan-intel lib32-vulkan-intel intel-media-driver) ;;
      nvidia) pkgs+=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils opencl-nvidia lib32-opencl-nvidia nvidia-settings libvdpau-va-gl) ;;
      nvidia-legacy) paru -S --needed --noconfirm nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils ;;
    esac
  done
  if [[ " $gpus" == *" nvidia"* ]]; then
    # Hybrid laptop: prime-run for the dGPU.
    if [[ $(wc -w <<<"$gpus") -gt 1 ]]; then pkgs+=(nvidia-prime); fi
    # Load NVIDIA early (initramfs) to avoid a black screen at boot; mkinitcpio -P runs later in install.
    grep -q '^MODULES=.*nvidia_drm' /etc/mkinitcpio.conf ||
      sudo sed -i -E 's/^MODULES=\((.*)\)/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/; s/^MODULES=\( /MODULES=(/' /etc/mkinitcpio.conf
    # DKMS needs headers for every installed kernel.
    local k
    for k in /usr/lib/modules/*/pkgbase; do pkgs+=("$(cat "$k")-headers"); done
  fi
  echo "GPU drivers: ${pkgs[*]}"
  sudo pacman -S --needed --noconfirm "${pkgs[@]}"
}

in_lists() { grep -qxF "$1" packages/pacman.txt packages/aur.txt; }
is_picked() { printf '%s\n' "${PICKED[@]}" | grep -qxF "$1"; }

# Menu starts from this machine's setup, as recorded by the last `save`.
menu_defaults() {
  local e cat label pkgs
  PICKED=()
  for e in "${APPS[@]}"; do
    IFS='|' read -r cat label pkgs <<<"$e"
    if in_lists "${pkgs%% *}"; then PICKED+=("$label"); fi
  done
  CFG[kernel]=Stock
  if in_lists linux-cachyos; then CFG[kernel]=CachyOS; fi
  if in_lists linux-cachyos-lts; then CFG[kernel]="CachyOS + LTS"; fi
  CFG[warp]=no
  if in_lists cloudflare-warp-bin; then CFG[warp]=yes; fi
}

gpu_label() {  # gpu_label [value], default: the current choice
  local g=${1:-${CFG[gpu]}} names=""
  if [[ $g == auto ]]; then g=$(detect_gpus); names="auto-detect: "; fi
  g=${g//nvidia-legacy/NVIDIA legacy}; g=${g//nvidia/NVIDIA}; g=${g//amd/AMD}; g=${g//intel/Intel}; g=${g//vm/Virtual machine}
  echo "${names}${g:-none}" | sed 's/ \([AIN]\)/ + \1/g; s/: + /: /'
}



pick_apps() {
  local cats cat e c label pkgs sel ticked items keep=()
  # An array, not a `while read` loop: gum would eat the loop's stdin.
  mapfile -t cats < <(printf '%s\n' "${APPS[@]}" | cut -d'|' -f1 | awk '!seen[$0]++')
  for cat in "${cats[@]}"; do
    items=() ticked=()
    for e in "${APPS[@]}"; do
      IFS='|' read -r c label pkgs <<<"$e"
      [[ $c == "$cat" ]] || continue
      items+=("$label")
      if is_picked "$label"; then ticked+=("$label"); fi
    done
    center_choose "── ${cat} ──  (x toggles, enter saves, esc skips)" "${items[@]/#/[x] }"
    # Esc keeps this category as it was.
    sel=$(gum choose --no-limit --height 10 --header "── ${cat} ──  (x toggles, enter saves, esc skips)" \
      --selected "$(IFS=,; echo "${ticked[*]}")" --selected-prefix "[x] " --unselected-prefix "[ ] " "${items[@]}") || sel=$(printf '%s\n' "${ticked[@]}")
    keep=()
    for label in "${PICKED[@]}"; do printf '%s\n' "${items[@]}" | grep -qxF "$label" || keep+=("$label"); done
    PICKED=("${keep[@]}")
    while IFS= read -r label; do [[ -n $label ]] && PICKED+=("$label"); done <<<"$sel"
  done
}

pick_one() {  # pick_one <key> <header> <options...>
  local key=$1 header=$2 sel; shift 2
  center_choose "$header" "$@"
  sel=$(gum choose --header "$header" --selected "${CFG[$key]}" "$@") || return 0
  CFG[$key]=$sel
}

# Every setup as one list, like Xero's installer: single GPU, iGPU + dGPU laptops, or a VM.
GPU_SETUPS=(
  "intel|Intel"
  "amd|AMD"
  "nvidia|NVIDIA Turing+ (RTX 20/30/40/50, GTX 16)"
  "nvidia-legacy|NVIDIA legacy (GTX 900/1000)"
  "intel amd|Intel iGPU + AMD dGPU"
  "intel nvidia|Intel iGPU + NVIDIA Turing+ dGPU (Optimus)"
  "intel nvidia-legacy|Intel iGPU + NVIDIA legacy dGPU (Optimus)"
  "amd nvidia|AMD iGPU + NVIDIA Turing+ dGPU (hybrid)"
  "amd nvidia-legacy|AMD iGPU + NVIDIA legacy dGPU (hybrid)"
  "vm|Virtual machine"
)

pick_gpu() {
  local e key label sel current="" opts=("Auto-detect: $(gpu_label auto | sed 's/^auto-detect: //')")
  [[ ${CFG[gpu]} == auto ]] && current=${opts[0]}
  for e in "${GPU_SETUPS[@]}"; do
    key=${e%%|*} label=${e#*|}
    opts+=("$label")
    if [[ ${CFG[gpu]} == "$key" ]]; then current=$label; fi
  done
  center_choose "Graphics driver (Turing+ = open module, legacy = 580xx driver)" "${opts[@]}"
  sel=$(gum choose --height 13 --header "Graphics driver (Turing+ = open module, legacy = 580xx driver)" \
    --selected "$current" "${opts[@]}") || return 0
  if [[ $sel == Auto-detect* ]]; then CFG[gpu]=auto; return; fi
  for e in "${GPU_SETUPS[@]}"; do
    if [[ ${e#*|} == "$sel" ]]; then CFG[gpu]=${e%%|*}; fi
  done
}

look_label() { if [[ ${CFG[look]} == dux ]]; then echo "Dux defaults"; else echo "nagi glass"; fi; }

pick_look() {
  local sel
  center_choose "Desktop look" "nagi glass: transparency + blur" "Dux defaults: solid, no blur"
  sel=$(gum choose --header "Desktop look" --selected "$(look_label | sed 's/^nagi glass$/nagi glass: transparency + blur/;s/^Dux defaults$/Dux defaults: solid, no blur/')" \
    "nagi glass: transparency + blur" "Dux defaults: solid, no blur") || return 0
  if [[ $sel == Dux* ]]; then CFG[look]=dux; else CFG[look]=nagi; fi
}

summary() {
  local apps; apps=$(printf '%s, ' "${PICKED[@]}"); apps=${apps%, }
  # --width makes gum wrap inside the box; wider than the terminal, the border breaks.
  gum style --border rounded --border-foreground "#88b5f0" --foreground "#d5e7ff" --padding "1 2" \
    --width "$(( $(tput cols) - 4 ))" \
    "Apps       ${apps:-none}" "Look       $(look_label)" "Kernel     ${CFG[kernel]}" "Graphics   $(gpu_label)" \
    "Downloads  ${CFG[parallel]} at a time" "WARP       ${CFG[warp]}"
}

# Xero-style main menu: each row shows its value and opens its own picker. --all skips it with the defaults.
main_menu() {
  menu_defaults
  [[ ${1:-} == --all ]] && return
  command -v gum lspci >/dev/null || sudo pacman -S --needed --noconfirm gum pciutils >/dev/null
  ui_colors
  local sel rows last=""
  while true; do
    clear
    banner
    rows=("1. Apps                │ ${#PICKED[@]} selected"
      "2. Look                │ $(look_label)"
      "3. Kernel              │ ${CFG[kernel]}"
      "4. Graphics driver     │ $(gpu_label)"
      "5. Parallel downloads  │ ${CFG[parallel]}"
      "6. Cloudflare WARP     │ ${CFG[warp]}"
      "──────────────────────────────────────"
      "7. Start installation"
      "0. Exit")
    center_choose "Set up your install. The desktop itself is always installed." "${rows[@]}"
    # Reopen on the row just used; its text changes with the value, so match by number.
    sel=$(gum choose --height 12 --header "Set up your install. The desktop itself is always installed." \
      --selected "$(printf '%s\n' "${rows[@]}" | grep -m1 "^${last:-1}\. ")" "${rows[@]}") || exit 0
    last=${sel%%.*}
    case $last in
      1) pick_apps ;;
      2) pick_look ;;
      3) pick_one kernel "Kernel (Stock = the one archinstall set up)" "CachyOS + LTS" "CachyOS" "Stock" ;;
      4) pick_gpu ;;
      5) pick_one parallel "pacman parallel downloads" 3 5 8 10 15 ;;
      6) pick_one warp "Cloudflare WARP (VPN client)" yes no ;;
      7) clear; summary; gum confirm "Install nagi with this setup?" && return ;;
      0) exit 0 ;;
    esac
  done
}

# Package list for this install: saved lists minus every optional package, plus the picked ones.
# Package lists are space-separated names (no globs), split into words on purpose.
# shellcheck disable=SC2206
packages_for_install() {
  local e cat label pkgs optional=() picked=()
  for e in "${APPS[@]}"; do
    IFS='|' read -r cat label pkgs <<<"$e"
    optional+=($pkgs)
    if is_picked "$label"; then picked+=($pkgs); fi
  done
  optional+=(${KERNELS["CachyOS + LTS"]} cloudflare-warp-bin)
  if [[ -n ${CFG[kernel]} ]]; then picked+=(${KERNELS[${CFG[kernel]}]}); fi
  if [[ ${CFG[warp]} == yes ]]; then picked+=(cloudflare-warp-bin); fi
  cat packages/pacman.txt packages/aur.txt | grep -vxF -f <(printf '%s\n' "${optional[@]}")
  printf '%s\n' "${picked[@]}" | grep . || true
}

# Dux installer: niri, Dux Shell, greetd + dms-greeter. It's an interactive TUI, so it needs the real terminal.
dux_install() {
  command -v dms >/dev/null && { echo "Dux Shell already installed, skipping its installer."; return; }
  local tmp; tmp=$(mktemp)
  curl -fsSL https://install.duxlabs.dev -o "$tmp"
  sh "$tmp" </dev/tty >/dev/tty 2>&1  # straight to the terminal, past the install log
  rm -f "$tmp"
}

# archinstall mounts a separate @.snapshots subvolume on /.snapshots, which makes
# `snapper create-config` fail. Arch wiki recipe: unmount, create config, swap its nested subvolume back for ours.
setup_snapper() {
  [[ $(findmnt -no FSTYPE /) == btrfs && ! -f /etc/snapper/configs/root ]] || return 0
  local separate=0
  if mountpoint -q /.snapshots; then separate=1; sudo umount /.snapshots; sudo rmdir /.snapshots; fi
  sudo snapper -c root create-config /
  if (( separate )); then
    sudo btrfs subvolume delete /.snapshots
    sudo mkdir /.snapshots
    sudo mount -a
  fi
  sudo chmod 750 /.snapshots
}

# Only install what the repos actually have, so one renamed package can't abort the whole list.
# Repo packages go through pacman, the rest (AUR) through paru. Installed ones are left alone, so this never upgrades.
# package_plan repo|aur: what this install still needs from that source.
package_plan() {
  local avail want
  avail=$(pacman -Slq | sort -u)
  want=$(comm -23 <(packages_for_install | sort -u) <(pacman -Qq | sort))
  if [[ $1 == repo ]]; then comm -12 <(echo "$want") <(echo "$avail"); else comm -23 <(echo "$want") <(echo "$avail"); fi | grep . || true
}

install_packages() {
  local repo aur
  repo=$(package_plan repo)
  aur=$(package_plan aur)
  [[ -z $repo ]] || sudo pacman -S --needed --noconfirm - <<<"$repo"
  [[ -z $aur ]] || paru -S --needed --noconfirm - <<<"$aur"
}

# Dotfiles, scripts, wallpapers and /etc files from the repo into place.
apply_files() {
  local f rel
  while IFS= read -r f; do
    rel=${f#dotfiles/*/}
    if is_style "$rel"; then continue; fi
    mkdir -p ~/"$(dirname "$rel")"
    cp -a "$f" ~/"$rel"
    if grep -qIF __HOME__ ~/"$rel"; then sed -i "s|__HOME__|$HOME|g" ~/"$rel"; fi
  done < <(find dotfiles -type f)
  mkdir -p "$(dirname "$LOOK_FILE")" && echo "${CFG[look]}" > "$LOOK_FILE"
  mkdir -p ~/"$WALLPAPER_DIR" ~/.local/bin && cp -r wallpapers/. ~/"$WALLPAPER_DIR"/ && cp scripts/* ~/.local/bin/
  sudo cp -r system/. /etc/
  if is_omen; then
    sudo cp -r hardware/omen-8bcd/etc/. /etc/
    cp hardware/omen-8bcd/{hdmi-mode,nv-run} ~/.local/bin/
    sudo install -m755 hardware/omen-8bcd/greeter-gpu /usr/local/bin/
    # Dux's own niri config doesn't include hdmi-mode's GPU pinning; nagi's does.
    local niri=~/.config/niri/config.kdl
    if [[ -f $niri ]] && ! grep -q 'gpu.kdl' "$niri"; then echo 'include optional=true "gpu.kdl"' >> "$niri"; fi
  fi
}

# Configs that differ from the repo and would be overwritten by apply_files (nagi-update asks first).
changed() {
  local f rel
  while IFS= read -r f; do
    rel=${f#dotfiles/*/}
    if is_style "$rel" || [[ ! -e ~/$rel ]]; then continue; fi
    # shellcheck disable=SC2088  # a literal ~ for display, not a path
    sed "s|__HOME__|$HOME|g" "$f" | cmp -s - ~/"$rel" || printf '~/%s\n' "$rel"
  done < <(git ls-files dotfiles)
}

# Dux only takes a wallpaper over IPC once it's running, so a one-shot autostart sets it on first login, then deletes itself.
# Skipped when Dux already has a session (a wallpaper was picked before).
first_login_wallpaper() {
  [[ -e ~/.local/state/DankMaterialShell/session.json ]] && return
  local run=~/.config/autostart/nagi-wallpaper
  mkdir -p ~/.config/autostart
  cat > "$run.sh" <<EOF
#!/bin/sh
for i in \$(seq 30); do dms ipc call wallpaper set "$HOME/$WALLPAPER_DIR/$DEFAULT_WALLPAPER" && break; sleep 1; done
rm -f "$run.sh" "$run.desktop"
EOF
  chmod +x "$run.sh"
  printf '[Desktop Entry]\nType=Application\nName=nagi wallpaper\nExec=%s\n' "$run.sh" > "$run.desktop"
}

# The menu, then what it would install. Changes nothing.
dry_run() {
  local repo aur
  main_menu "${1:-}"
  repo=$(package_plan repo)
  aur=$(package_plan aur)
  clear; summary
  echo "From the repos ($(grep -c . <<<"$repo")):"; echo "${repo:-  nothing new}" | column -c "$(tput cols)"
  echo; echo "Built from the AUR ($(grep -c . <<<"$aur")):"; echo "${aur:-  nothing new}" | column -c "$(tput cols)"
  echo; echo "Plus GPU drivers for: $(gpu_label). Dry run: nothing was installed."
}

update() {
  [[ $EUID -ne 0 ]] || { echo "Run as your normal user (it uses sudo)."; exit 1; }
  install_packages
  apply_files
  sudo systemctl daemon-reload
  echo "Updated. Log out and back in to pick up every change."
}

install_nagi() {
  [[ $EUID -ne 0 ]] || { echo "Run as your normal user (it uses sudo)."; exit 1; }
  # Ask for the password once and keep sudo alive until this script exits.
  sudo -v
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
  main_menu "${1:-}"
  # After the menu: gum needs the bare terminal.
  exec > >(tee -a ~/nagi-install.log) 2>&1
  pacman_tweaks
  add_repos
  # Before our package list: it contains dms-shell, which would make dux_install skip itself.
  dux_install

  sudo pacman -S --needed --noconfirm snapper snap-pac grub-btrfs inotify-tools
  install_packages
  gpu_drivers

  # oh-my-zsh + the custom plugins .zshrc expects
  [[ -d ~/.oh-my-zsh ]] || git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh ~/.oh-my-zsh
  local p
  for p in zsh-users/zsh-autosuggestions zsh-users/zsh-syntax-highlighting zsh-users/zsh-completions; do
    [[ -d ~/.oh-my-zsh/custom/plugins/${p#*/} ]] || git clone --depth 1 "https://github.com/$p" ~/.oh-my-zsh/custom/plugins/${p#*/}
  done
  [[ $SHELL == */zsh ]] || chsh -s /usr/bin/zsh

  setup_snapper
  apply_files
  first_login_wallpaper
  if is_omen; then ~/.local/bin/hdmi-mode off; fi
  # As the user, never with sudo: the greeter then links to this user's Dux settings, so the login screen
  # shows their wallpaper (Giyu once first login sets it) and, on the OMEN, copies niri's GPU pinning (gpu.kdl).
  DMS_PRIVESC=sudo dms-greeter sync || echo "warning: dms-greeter sync failed; run it (without sudo) after first login"

  # Boot the main CachyOS kernel by default, not LTS (GRUB sorts lts first).
  if [[ -e /boot/vmlinuz-linux-cachyos ]] && ! grep -q '^GRUB_TOP_LEVEL=' /etc/default/grub; then
    echo 'GRUB_TOP_LEVEL="/boot/vmlinuz-linux-cachyos"' | sudo tee -a /etc/default/grub >/dev/null
  fi
  sudo sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="Arch"/' /etc/default/grub
  # Quiet boot: hide kernel messages below errors.
  grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=.*loglevel=" /etc/default/grub ||
    sudo sed -i -E 's/^GRUB_CMDLINE_LINUX_DEFAULT="([^"]*)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 quiet loglevel=3"/' /etc/default/grub
  sudo mkdir -p /boot/grub/themes && sudo cp -r themes/grub/ArchNord /boot/grub/themes/
  local theme=/boot/grub/themes/ArchNord/theme.txt
  if grep -q '^#\?GRUB_THEME=' /etc/default/grub; then
    sudo sed -i "s|^#\?GRUB_THEME=.*|GRUB_THEME=\"$theme\"|" /etc/default/grub
  else
    echo "GRUB_THEME=\"$theme\"" | sudo tee -a /etc/default/grub >/dev/null
  fi
  # List other installed OSes (dual boot) in the GRUB menu.
  grep -q '^GRUB_DISABLE_OS_PROBER=false' /etc/default/grub ||
    echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a /etc/default/grub >/dev/null
  sudo mkinitcpio -P
  sudo grub-mkconfig -o /boot/grub/grub.cfg

  local s
  for s in "${SERVICES[@]}"; do
    systemctl cat "$s" &>/dev/null && sudo systemctl enable "$s" || echo "skip service (not installed): $s"
  done
  echo "Done. Reboot. (Log: ~/nagi-install.log)"
}

case "${1:-}" in
  ""|--all) install_nagi "${1:-}" ;;
  --dry-run) dry_run "${2:-}" ;;
  save) save ;;
  update) update ;;
  changed) changed ;;
  *) echo "usage: $0 [--all|--dry-run [--all]|save|update|changed]"; exit 1 ;;
esac
