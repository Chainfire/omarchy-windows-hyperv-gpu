#!/usr/bin/env bash
# Install qemu-display-autoresize.
#
# Runnable from anywhere: it resolves its own directory rather than assuming the
# working directory.
#
#   ./install.sh                      install   (no root, nothing outside $HOME)
#   ./install.sh --uninstall          remove
set -euo pipefail

SRC_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

NAME=qemu-display-autoresize
RESET="$NAME-reset"                  # ExecStop helper: clears a pinned mode
UNIT="$NAME.service"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m warning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m error:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Install qemu-display-autoresize.

Runnable from anywhere: it resolves its own directory rather than assuming the
working directory.

  ./install.sh              install   (no root, nothing outside $HOME)
  ./install.sh --uninstall  remove
USAGE
}

DO_UNINSTALL=false
for arg in "$@"; do
  case "$arg" in
    --uninstall) DO_UNINSTALL=true ;;
    -h|--help)   usage; exit 0 ;;
    *)           usage >&2; die "unknown argument: $arg" ;;
  esac
done

# ---------------------------------------------------------------- user part
user_uninstall() {
  say "Removing $NAME"
  systemctl --user disable --now "$UNIT" 2>/dev/null || true
  rm -f "$UNIT_DIR/$UNIT" "$BIN_DIR/$NAME" "$BIN_DIR/$RESET"
  systemctl --user daemon-reload 2>/dev/null || true
  say "Removed."
  if [[ -f $HYPR_DIR/monitors.lua ]] &&
     grep -qE '^hl\.monitor\(\{ output = "", mode = "[0-9]+x[0-9]+"' "$HYPR_DIR/monitors.lua"; then
    warn "monitors.lua still has a pinned resolution and nothing updates it now."
    warn "Set  mode = \"preferred\"  by hand, or a small QEMU window at the next"
    warn "boot will make Hyprland modeset the wrong size."
  fi
}

user_install() {
  [[ $EUID -eq 0 ]] && die "run the user part as your normal user, not root"

  local missing=()
  for c in hyprctl jq socat udevadm logger stdbuf sed grep; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  ((${#missing[@]} == 0)) || die "missing required commands: ${missing[*]}
  Arch: sudo pacman -S --needed jq socat systemd util-linux coreutils"

  for f in "$NAME" "$RESET" "$UNIT"; do
    [[ -r $SRC_DIR/$f ]] || die "cannot find $f next to install.sh (looked in $SRC_DIR)"
  done

  # Preflight: warn, never block. None of these make installing harmful.
  systemd-detect-virt -q --vm 2>/dev/null ||
    warn "not running in a VM -- the unit sets ConditionVirtualization=vm, so it installs but never starts here"

  local virtio_found=false d
  for d in /sys/class/drm/card*/device/driver; do
    [[ -e $d ]] || continue
    [[ $(basename "$(readlink -f "$d")") == virtio* ]] && virtio_found=true
  done
  $virtio_found || warn "no virtio-gpu DRM device found -- the service only acts on virtio* connectors"

  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] ||
    warn "Hyprland does not appear to be running in this shell; the unit starts with graphical-session.target"

  if [[ ! -f $HYPR_DIR/monitors.lua ]]; then
    warn "no $HYPR_DIR/monitors.lua -- resolution will not survive a config reload"
  elif ! grep -qE '^hl\.monitor\(\{ output = "", mode = "[^"]*", position = "auto", scale = ' "$HYPR_DIR/monitors.lua"; then
    warn "monitors.lua has no Omarchy-style catch-all monitor line; mode pinning will be skipped."
    warn "The display will still follow resizes, but a config reload will revert it."
  fi

  say "Installing $NAME, $RESET -> $BIN_DIR"
  install -Dm755 "$SRC_DIR/$NAME"  "$BIN_DIR/$NAME"
  # The unit's ExecStop points at this; installing the unit without it would
  # make every session exit fail.
  install -Dm755 "$SRC_DIR/$RESET" "$BIN_DIR/$RESET"

  say "Installing $UNIT -> $UNIT_DIR"
  mkdir -p "$UNIT_DIR"
  local EXEC
  if [[ $BIN_DIR == "$HOME"/* ]]; then EXEC="%h/${BIN_DIR#"$HOME"/}/$NAME"; else EXEC="$BIN_DIR/$NAME"; fi
  sed -E -e "s|^ExecStart=.*|ExecStart=$EXEC|" \
         -e "s|^ExecStop=.*|ExecStop=$EXEC-reset|" "$SRC_DIR/$UNIT" >"$UNIT_DIR/$UNIT"

  # Earlier installs launched this from Hyprland's autostart.lua. Both at once
  # would run two copies fighting over the same config file.
  if [[ -f $HYPR_DIR/autostart.lua ]] && grep -q "$NAME" "$HYPR_DIR/autostart.lua"; then
    warn "$HYPR_DIR/autostart.lua still launches $NAME."
    warn "Remove that o.launch_on_start line, or you will run two copies."
  fi

  systemctl --user daemon-reload
  systemctl --user enable "$UNIT" >/dev/null

  if systemctl --user is-active --quiet graphical-session.target; then
    systemctl --user restart "$UNIT"   # restart, so re-running upgrades a live install
    sleep 1
    if systemctl --user is-active --quiet "$UNIT"; then
      say "Running. Logs: journalctl --user -b -t $NAME"
    else
      warn "Unit did not start. Check: systemctl --user status $UNIT"
    fi
  else
    say "Enabled. graphical-session.target is not active, so it starts at next login."
  fi
}

if $DO_UNINSTALL; then user_uninstall; else user_install; fi
