#!/usr/bin/env bash
# arch-dots: Arch Linux + KDE Plasma setup.
#   ./install.sh        restore everything on a fresh archinstall system (run as your user, not root)
#   ./install.sh save   copy this machine's setup into the repo
set -euo pipefail
cd "$(dirname "$0")"

# Dotfiles, relative to $HOME, saved under dotfiles/<group>/. Never add anything holding tokens/keys.
SHELL_FILES=(.zshrc .config/fastfetch .config/ohmyposh .config/bat)
KDE_FILES=(
  .config/kdeglobals .config/kdedefaults .config/kwinrc .config/kwinrulesrc .config/plasmarc .config/plasmashellrc
  .config/plasma-org.kde.plasma.desktop-appletsrc .config/kglobalshortcutsrc .config/kcminputrc .config/ksplashrc
  .config/kscreenlockerrc .config/krunnerrc .config/plasmanotifyrc .config/breezerc .config/Kvantum .config/panel-colorizer
  .config/gtk-3.0 .config/gtk-4.0 .config/xsettingsd .config/konsolerc .config/yakuakerc .config/dolphinrc
  .local/share/plasma .local/share/aurorae .local/share/color-schemes .local/share/konsole
  # Fonts, power, session, Dolphin/KIO behaviour, toolbar layouts, update widget settings (not its cache)
  .config/fontconfig .config/powerdevilrc .config/powermanagementprofilesrc .config/ksmserverrc
  .config/kservicemenurc .config/kiorc .config/trashrc .local/share/dolphin .local/share/kxmlgui5
  .config/apdatifier/config.conf .config/apdatifier/rules.json
)
APP_FILES=(.config/btop .config/cava .config/htop .config/topgrade.toml .config/mimeapps.list .config/spotify-flags.conf)
WALLPAPER_DIR=Pictures/wallpaper
# Generic /etc files.
ETC_FILES=(X11/xorg.conf.d/00-keyboard.conf snapper/configs/root systemd/zram-generator.conf NetworkManager/conf.d/wifi-backend.conf)
# HP OMEN 16 (board 8BCD) only, in hardware/omen-8bcd/: AMD iGPU + RTX 4050 sleep/resume fixes.
OMEN_ETC_FILES=(modprobe.d/nvidia-s0ix.conf udev/rules.d/61-amd-igpu.rules X11/xorg.conf.d/10-amd-only.conf)
OMEN_BOARD=8BCD

# Only packages from these repos are kept; anything else installed locally is left out.
REPOS=(core extra multilib chaotic-aur)
AUR_EXTRA=(kwin-zones kwin-scripts-kzones)
# Personal gaming setup, not part of the dots.
SKIP='^(lib32-)?(wine.*|steam|protonplus|gallium-nine.*|mangohud|mangoverlay|gamemode|game-devices-udev)$'
# GPU drivers are picked per machine by gpu_drivers(), not copied from mine.
GPU='^(lib32-)?(nvidia.*|opencl-nvidia.*|vulkan-radeon|vulkan-intel|intel-media-driver|xf86-video-.*)$'

SERVICES=(NetworkManager bluetooth sddm power-profiles-daemon switcheroo-control systemd-timesyncd
  grub-btrfsd snapper-timeline.timer snapper-cleanup.timer docker.socket warp-svc
  nvidia-suspend nvidia-resume nvidia-hibernate nvidia-powerd)

is_omen() { [[ "$(cat /sys/class/dmi/id/board_name 2>/dev/null)" == "$OMEN_BOARD" ]]; }

copy_group() {  # copy_group <group> <files...>
  local g=$1 f; shift
  for f in "$@"; do
    [[ -e ~/$f ]] || { echo "skip (missing): ~/$f"; continue; }
    mkdir -p "dotfiles/$g/$(dirname "$f")"; cp -a ~/"$f" "dotfiles/$g/$f"
  done
}

save() {
  comm -12 <(pacman -Qqen | sort) <(pacman -Slq "${REPOS[@]}" | sort -u) | grep -Ev "$SKIP" | grep -Ev "$GPU" > packages/pacman.txt
  { pacman -Qqem; printf '%s\n' "${AUR_EXTRA[@]}"; } | sort -u | grep -Ev "$SKIP" | grep -Ev "$GPU" > packages/aur.txt
  rm -rf dotfiles system hardware/omen-8bcd/etc wallpapers
  copy_group shell "${SHELL_FILES[@]}"
  copy_group kde "${KDE_FILES[@]}"
  copy_group apps "${APP_FILES[@]}"
  cp -r ~/"$WALLPAPER_DIR" wallpapers
  # Store home paths as a placeholder so the configs work for any username.
  grep -rlIF "$HOME" dotfiles | xargs -r sed -i "s|$HOME|__HOME__|g"
  # Weather widget station reveals my location; publish a placeholder (set yours in the widget settings).
  sed -i -E 's/"stationID":"[^"]*"/"stationID":"YOUR_STATION_ID"/g; s/"address":"[^"]*"/"address":"Your City"/g; s/^stationID=.*/stationID=YOUR_STATION_ID/; s/^stationName=.*/stationName=Your City/' \
    dotfiles/kde/.config/plasma-org.kde.plasma.desktop-appletsrc
  for f in "${ETC_FILES[@]}"; do mkdir -p "system/$(dirname "$f")"; cp /etc/"$f" "system/$f"; done
  for f in "${OMEN_ETC_FILES[@]}"; do mkdir -p "hardware/omen-8bcd/etc/$(dirname "$f")"; cp /etc/"$f" "hardware/omen-8bcd/etc/$f"; done
  cp ~/.local/bin/hdmi-mode hardware/omen-8bcd/
  echo "Saved. Review with: git diff"
}

pacman_tweaks() {
  local o
  for o in Color ILoveCandy VerbosePkgLists DisableDownloadTimeout; do
    grep -q "^$o" /etc/pacman.conf || sudo sed -i "/^\[options\]/a $o" /etc/pacman.conf
  done
  sudo sed -i 's/^#\?ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
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

# Detect GPUs by PCI vendor and install matching drivers.
gpu_drivers() {
  local ids pkgs=(mesa lib32-mesa vulkan-icd-loader lib32-vulkan-icd-loader) count=0
  sudo pacman -S --needed --noconfirm pciutils
  ids=$(lspci -nn | grep -E 'VGA|3D|Display' | grep -oE '\[[0-9a-f]{4}:[0-9a-f]{4}\]')
  if grep -q '1002:' <<<"$ids"; then pkgs+=(vulkan-radeon lib32-vulkan-radeon); ((++count)); fi
  if grep -q '8086:' <<<"$ids"; then pkgs+=(vulkan-intel lib32-vulkan-intel intel-media-driver); ((++count)); fi
  if grep -q '10de:' <<<"$ids"; then
    ((++count))
    # Turing (device 0x1e00) and newer use the open kernel module; older cards need the 580xx legacy driver.
    local dev=$(grep -oE '10de:[0-9a-f]{4}' <<<"$ids" | head -1 | cut -d: -f2)
    if (( 16#$dev >= 16#1e00 )); then
      pkgs+=(nvidia-open-dkms nvidia-utils lib32-nvidia-utils opencl-nvidia lib32-opencl-nvidia nvidia-settings libvdpau-va-gl)
    else
      paru -S --needed --noconfirm nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils
    fi
    (( count > 1 )) && pkgs+=(nvidia-prime)
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

install() {
  [[ $EUID -ne 0 ]] || { echo "Run as your normal user (it uses sudo)."; exit 1; }
  # Ask for the password once and keep sudo alive until this script exits.
  sudo -v
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
  pacman_tweaks
  add_repos

  # Only install what the repos actually have, so one renamed package can't abort the whole list.
  local avail missing
  avail=$(pacman -Slq | sort -u)
  missing=$(comm -23 <(sort -u packages/pacman.txt) <(echo "$avail"))
  [[ -z $missing ]] || echo "Not in any repo, skipped: $(echo $missing)"
  sudo pacman -S --needed --noconfirm snapper snap-pac grub-btrfs inotify-tools
  comm -12 <(sort -u packages/pacman.txt) <(echo "$avail") | sudo pacman -S --needed --noconfirm -
  [[ -s packages/aur.txt ]] && paru -S --needed --noconfirm - < packages/aur.txt
  gpu_drivers

  # oh-my-zsh + the custom plugins .zshrc expects
  [[ -d ~/.oh-my-zsh ]] || git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh ~/.oh-my-zsh
  local p
  for p in zsh-users/zsh-autosuggestions zsh-users/zsh-syntax-highlighting zsh-users/zsh-completions; do
    [[ -d ~/.oh-my-zsh/custom/plugins/${p#*/} ]] || git clone --depth 1 "https://github.com/$p" ~/.oh-my-zsh/custom/plugins/${p#*/}
  done
  [[ $SHELL == */zsh ]] || chsh -s /usr/bin/zsh

  setup_snapper
  local g f
  for g in dotfiles/*/; do
    cp -a "$g". ~/
    while IFS= read -r f; do sed -i "s|__HOME__|$HOME|g" ~/"${f#"$g"}"; done < <(grep -rlIF __HOME__ "$g")
  done
  mkdir -p ~/"$WALLPAPER_DIR" ~/.local/bin && cp -r wallpapers/. ~/"$WALLPAPER_DIR"/ && cp scripts/* ~/.local/bin/
  sudo cp -r system/. /etc/
  sudo cp -r themes/sddm/ArchDark /usr/share/sddm/themes/
  sudo mkdir -p /etc/sddm.conf.d && printf '[Theme]\nCurrent=ArchDark\n' | sudo tee /etc/sddm.conf.d/theme.conf >/dev/null
  if is_omen; then
    sudo cp -r hardware/omen-8bcd/etc/. /etc/
    cp hardware/omen-8bcd/hdmi-mode ~/.local/bin/
    sudo udevadm control --reload
    ~/.local/bin/hdmi-mode off
  fi

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
  grep -q '^#\?GRUB_THEME=' /etc/default/grub \
    && sudo sed -i "s|^#\?GRUB_THEME=.*|GRUB_THEME=\"$theme\"|" /etc/default/grub \
    || echo "GRUB_THEME=\"$theme\"" | sudo tee -a /etc/default/grub >/dev/null
  # List other installed OSes (dual boot) in the GRUB menu.
  grep -q '^GRUB_DISABLE_OS_PROBER=false' /etc/default/grub ||
    echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a /etc/default/grub >/dev/null
  sudo mkinitcpio -P
  sudo grub-mkconfig -o /boot/grub/grub.cfg

  local s
  for s in "${SERVICES[@]}"; do
    systemctl cat "$s" &>/dev/null && sudo systemctl enable "$s" || echo "skip service (not installed): $s"
  done
  echo "Done. Reboot."
}

case "${1:-}" in
  "") install ;;
  save) save ;;
  *) echo "usage: $0 [save]"; exit 1 ;;
esac
