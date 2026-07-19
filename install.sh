#!/usr/bin/env bash
set -Eeuo pipefail

readonly MARK_START='# >>> wsl-tmux-i3 >>>'
readonly MARK_END='# <<< wsl-tmux-i3 <<<'
readonly BASH_MARK_START='# >>> wsl-tmux-i3 auto-attach >>>'
readonly BASH_MARK_END='# <<< wsl-tmux-i3 auto-attach <<<'
DRY_RUN=0
INSTALL_PACKAGES=1
CONFIGURE_TERMINAL=1
AUTO_ATTACH=1

usage() {
  cat <<'EOF'
Usage: ./install.sh [--dry-run] [--no-packages] [--no-terminal] [--no-auto-attach] [--uninstall]
EOF
}

run() { if (( DRY_RUN )); then printf '+ '; printf '%q ' "$@"; printf '\n'; else "$@"; fi; }

remove_block() {
  local target=$1 start=${2:-$MARK_START} end=${3:-$MARK_END} tmp
  [[ -f "$target" ]] || return 0
  tmp=$(mktemp)
  awk -v start="$start" -v end="$end" '
    $0 == start { skip=1; next }
    $0 == end { skip=0; next }
    !skip { print }
  ' "$target" > "$tmp"
  if (( DRY_RUN )); then rm -f "$tmp"; printf '+ tmux block will be removed from: %s\n' "$target"
  else mv "$tmp" "$target"; fi
}

UNINSTALL=0
while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --no-packages) INSTALL_PACKAGES=0 ;;
    --no-terminal) CONFIGURE_TERMINAL=0 ;;
    --no-auto-attach) AUTO_ATTACH=0 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TMUX_SOURCE="$SCRIPT_DIR/tmux.conf"
TMUX_TARGET="$HOME/.tmux.conf"
BASH_TARGET="$HOME/.bashrc"
STATUS_SOURCE="$SCRIPT_DIR/status.sh"
STATUS_CONFIG_SOURCE="$SCRIPT_DIR/status.conf"
STATUS_DIR="$HOME/.config/wsl-tmux-i3"

if (( UNINSTALL )); then
  remove_block "$TMUX_TARGET"
  remove_block "$BASH_TARGET" "$BASH_MARK_START" "$BASH_MARK_END"
  if (( DRY_RUN )); then
    printf '+ managed status script will be removed from: %s\n' "$STATUS_DIR/status.sh"
  else
    rm -f -- "$STATUS_DIR/status.sh"
    rm -f -- "$STATUS_DIR/status.conf"
    rmdir "$STATUS_DIR" 2>/dev/null || true
  fi
  if (( CONFIGURE_TERMINAL )) && command -v powershell.exe >/dev/null && [[ -f "$SCRIPT_DIR/windows-terminal.ps1" ]]; then
    run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$SCRIPT_DIR/windows-terminal.ps1")" -Restore
  fi
  printf 'wsl-tmux-i3 has been removed.\n'
  exit 0
fi

for required in "$TMUX_SOURCE" "$STATUS_SOURCE" "$STATUS_CONFIG_SOURCE"; do
  [[ -f "$required" ]] || { printf 'Missing file: %s\n' "$required" >&2; exit 1; }
done
if (( INSTALL_PACKAGES )) && ! command -v tmux >/dev/null; then
  command -v apt-get >/dev/null || { printf 'tmux is missing and apt-get was not found.\n' >&2; exit 1; }
  run sudo apt-get update
  run sudo apt-get install -y tmux
fi

remove_block "$TMUX_TARGET"
if (( DRY_RUN )); then
  printf '+ status script will be installed in: %s\n' "$STATUS_DIR"
else
  mkdir -p "$STATUS_DIR"
  install -m 755 "$STATUS_SOURCE" "$STATUS_DIR/status.sh"
  install -m 644 "$STATUS_CONFIG_SOURCE" "$STATUS_DIR/status.conf"
fi

if (( AUTO_ATTACH )); then
  remove_block "$BASH_TARGET" "$BASH_MARK_START" "$BASH_MARK_END"
  if (( DRY_RUN )); then
    printf '+ tmux auto-attach block will be added to: %s\n' "$BASH_TARGET"
  else
    {
      [[ ! -s "$BASH_TARGET" ]] || printf '\n'
      printf '%s\n' "$BASH_MARK_START"
      cat <<'EOF'
# Attach every new interactive terminal to the shared tmux session.
# Start Bash with WSL_TMUX_AUTO_ATTACH=0 to bypass this once.
if [[ $- == *i* ]] && [[ -z ${TMUX-} ]] && [[ ${WSL_TMUX_AUTO_ATTACH:-1} != 0 ]] \
  && [[ ${TERM-} != dumb ]] && command -v tmux >/dev/null 2>&1; then
  exec tmux new-session -A -s main
fi
EOF
      printf '%s\n' "$BASH_MARK_END"
    } >> "$BASH_TARGET"
  fi
fi
if (( DRY_RUN )); then
  printf '+ tmux settings will be added to: %s\n' "$TMUX_TARGET"
else
  {
    [[ ! -s "$TMUX_TARGET" ]] || printf '\n'
    printf '%s\n' "$MARK_START"
    cat "$TMUX_SOURCE"
    printf '%s\n' "$MARK_END"
  } >> "$TMUX_TARGET"
fi

if (( CONFIGURE_TERMINAL )); then
  if command -v powershell.exe >/dev/null; then
    run powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$SCRIPT_DIR/windows-terminal.ps1")"
  else
    printf 'Warning: powershell.exe was not found; Windows Terminal configuration was skipped.\n' >&2
  fi
fi

if command -v tmux >/dev/null && tmux has-session 2>/dev/null; then
  run tmux source-file "$TMUX_TARGET"
fi
printf 'Installation complete. Start with: tmux new -A -s main\n'
