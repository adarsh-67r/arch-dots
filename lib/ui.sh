# shellcheck shell=bash
# Shared gum look for install.sh and the nagi toolkit: Dux blues plus Giyu's haori.

rgb() { printf '\e[38;2;%d;%d;%dm' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }  # rgb "#rrggbb"

ui_colors() {
  export GUM_CHOOSE_CURSOR_FOREGROUND="#a2c9fd" GUM_CHOOSE_SELECTED_FOREGROUND="#88b5f0" GUM_CHOOSE_HEADER_FOREGROUND="#d5e7ff" \
    GUM_CONFIRM_PROMPT_FOREGROUND="#d5e7ff" GUM_CONFIRM_SELECTED_BACKGROUND="#88b5f0" GUM_CONFIRM_SELECTED_FOREGROUND="#111418"
}

# gum has no centering flag, so pad the next gum choose until its widest line sits mid-screen.
center_choose() {
  local s w=0 pad
  for s in "$@"; do if (( ${#s} > w )); then w=${#s}; fi; done
  pad=$(( ($(tput cols) - w - 4) / 2 ))
  if (( pad < 0 )); then pad=0; fi
  export GUM_CHOOSE_PADDING="0 $pad"
}

LOGO="${BASH_SOURCE[0]%/*}/../assets/logo-small.png"

# banner [subtitle words...]: the 凪 box, centered. Default subtitle: Arch · niri · Dux Shell.
banner() {
  local box pad line i w stripe="" r=$'\e[0m' b=$'\e[1m' sub="" bar="━" border=rounded title
  local haori=("#c99a3b" "#4f8a62" "#b0603a")  # mustard, green, rust: the patterned half of Giyu's haori
  (( $# )) || set -- Arch niri "Dux Shell"
  title="$b$(rgb "#a2c9fd")凪  $(rgb "#d5e7ff")nagi$r"
  if [[ $TERM == linux ]]; then
    # The bare TTY's font has no 凪 and no rounded or heavy box lines.
    title="$b$(rgb "#d5e7ff")nagi$r" bar="─" border=normal
  elif [[ $TERM == xterm-kitty && -f $LOGO ]] && command -v kitten >/dev/null; then
    # kitty draws the real logo above the box, which then carries just the name.
    if kitten icat --align center --stdin=no "$LOGO" 2>/dev/null; then title="$b$(rgb "#d5e7ff")nagi$r"; fi
  fi
  for w in "$@"; do sub+="${sub:+$(rgb "#4f6584") · }$(rgb "#88b5f0")$w"; done
  stripe="$(rgb "#7a2535")"; for i in {0..10}; do stripe+=$bar; done
  for i in {0..11}; do stripe+="$(rgb "${haori[i % 3]}")$bar"; done
  # Inside $(…) gum sees no terminal and drops colors; CLICOLOR_FORCE keeps them.
  box=$(CLICOLOR_FORCE=1 gum style --border "$border" --border-foreground "#6f9fe0" --padding "1 4" --align center \
    "$title" "$stripe$r" "$sub$r")
  pad=$(( ($(tput cols) - $(head -1 <<<"$box" | sed 's/\x1b\[[0-9;]*m//g' | wc -L)) / 2 ))
  if (( pad < 0 )); then pad=0; fi
  while IFS= read -r line; do printf '%*s%s\n' "$pad" '' "$line"; done <<<"$box"
  echo
}
