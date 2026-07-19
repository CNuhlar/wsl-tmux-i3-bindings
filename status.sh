#!/usr/bin/env bash
set -uo pipefail

CONFIG_FILE="${WSL_TMUX_STATUS_CONFIG:-$HOME/.config/wsl-tmux-i3/status.conf}"
[[ -r "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
LOCAL_CONFIG_FILE="${WSL_TMUX_STATUS_LOCAL_CONFIG:-$HOME/.config/wsl-tmux-i3/status.local.conf}"
[[ -r "$LOCAL_CONFIG_FILE" ]] && source "$LOCAL_CONFIG_FILE"

: "${STATUS_SHOW_HOST:=1}"
: "${STATUS_SHOW_CPU:=1}"
: "${STATUS_SHOW_MEMORY:=1}"
: "${STATUS_SHOW_LOAD:=0}"
: "${STATUS_SHOW_DISK:=1}"
: "${STATUS_SHOW_IP:=1}"
: "${STATUS_SHOW_NETWORK:=1}"
: "${STATUS_SHOW_BATTERY:=1}"
: "${STATUS_DISK_PATH:=/}"
: "${STATUS_DATE_FORMAT:=%a %d %b}"
: "${STATUS_TIME_FORMAT:=%H:%M:%S}"
: "${STATUS_WIDTH_HOST:=0}"
: "${STATUS_WIDTH_CPU:=3}"
: "${STATUS_WIDTH_MEMORY:=3}"
: "${STATUS_WIDTH_LOAD:=5}"
: "${STATUS_WIDTH_DISK:=3}"
: "${STATUS_WIDTH_IP:=0}"
: "${STATUS_WIDTH_NETWORK:=0}"
: "${STATUS_WIDTH_BATTERY:=3}"
: "${STATUS_WIDTH_DATE:=0}"
: "${STATUS_WIDTH_CUSTOM:=0}"
declare -p CUSTOM_SEGMENTS &>/dev/null || CUSTOM_SEGMENTS=()

segments=()
add_segment() {
  local label=$1 value=${2//$'\n'/ } width=${3:-$STATUS_WIDTH_CUSTOM} padded
  value=${value//#/##}
  [[ -n "${value// /}" ]] || return 0
  if (( width > 0 )); then
    printf -v padded '%*s' "$width" "$value"
  else
    padded=$value
  fi
  if [[ -n "$label" ]]; then
    segments+=("#[fg=colour245,bold]${label} #[fg=colour250]${padded}")
  else
    segments+=("#[fg=colour250]${padded}")
  fi
}

human_rate() {
  local bytes=$1
  if (( bytes >= 1048576 )); then awk -v n="$bytes" 'BEGIN {printf "%.1fM/s", n/1048576}'
  elif (( bytes >= 1024 )); then awk -v n="$bytes" 'BEGIN {printf "%.0fK/s", n/1024}'
  else printf '%dB/s' "$bytes"
  fi
}

if (( STATUS_SHOW_NETWORK )) && [[ -r /proc/net/dev ]]; then
  read -r rx_bytes tx_bytes < <(awk '$1 != "lo:" && $1 ~ /:$/ {rx += $2; tx += $10} END {print rx+0, tx+0}' /proc/net/dev)
  net_cache="${XDG_CACHE_HOME:-$HOME/.cache}/wsl-tmux-i3/network"
  mkdir -p "$(dirname "$net_cache")" 2>/dev/null || true
  now=$(date +%s)
  previous=""
  [[ -r "$net_cache" ]] && read -r previous < "$net_cache"
  printf '%s %s %s\n' "$now" "$rx_bytes" "$tx_bytes" > "$net_cache" 2>/dev/null || true
  if [[ $previous =~ ^[0-9]+\ [0-9]+\ [0-9]+$ ]]; then
    read -r old_time old_rx old_tx <<< "$previous"
    elapsed=$((now - old_time))
    if (( elapsed > 0 && rx_bytes >= old_rx && tx_bytes >= old_tx )); then
      down_rate=$(((rx_bytes - old_rx) / elapsed))
      up_rate=$(((tx_bytes - old_tx) / elapsed))
      add_segment "NET" "D:$(human_rate "$down_rate") U:$(human_rate "$up_rate")" "$STATUS_WIDTH_NETWORK"
    fi
  fi
fi

if (( STATUS_SHOW_HOST )); then
  add_segment "HOST" "$(hostname -s 2>/dev/null)" "$STATUS_WIDTH_HOST"
fi

if (( STATUS_SHOW_CPU )) && [[ -r /proc/stat ]]; then
  read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
  total=$((user + nice + system + idle + iowait + irq + softirq + steal))
  busy=$((total - idle - iowait))
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/wsl-tmux-i3"
  mkdir -p "$cache" 2>/dev/null || true
  previous=""
  [[ -r "$cache/cpu" ]] && read -r previous < "$cache/cpu"
  printf '%s %s\n' "$total" "$busy" > "$cache/cpu" 2>/dev/null || true
  if [[ $previous =~ ^[0-9]+\ [0-9]+$ ]]; then
    read -r old_total old_busy <<< "$previous"
    delta_total=$((total - old_total))
    (( delta_total > 0 )) && add_segment "CPU" "$((100 * (busy - old_busy) / delta_total))%" "$STATUS_WIDTH_CPU"
  fi
fi

if (( STATUS_SHOW_MEMORY )) && [[ -r /proc/meminfo ]]; then
  total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  available_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  if [[ $total_kb =~ ^[0-9]+$ && $available_kb =~ ^[0-9]+$ && $total_kb -gt 0 ]]; then
    add_segment "MEM" "$((100 * (total_kb - available_kb) / total_kb))%" "$STATUS_WIDTH_MEMORY"
  fi
fi

if (( STATUS_SHOW_LOAD )); then
  read -r load _ < /proc/loadavg
  add_segment "LOAD" "$load" "$STATUS_WIDTH_LOAD"
fi

if (( STATUS_SHOW_DISK )); then
  disk=$(df -hP "$STATUS_DISK_PATH" 2>/dev/null | awk 'NR == 2 {print $5}')
  add_segment "DISK" "$disk" "$STATUS_WIDTH_DISK"
fi

if (( STATUS_SHOW_BATTERY )); then
  for capacity in /sys/class/power_supply/BAT*/capacity; do
    [[ -r "$capacity" ]] || continue
    add_segment "BAT" "$(<"$capacity")%" "$STATUS_WIDTH_BATTERY"
    break
  done
fi

for item in "${CUSTOM_SEGMENTS[@]}"; do
  [[ $item == *::* ]] || continue
  label=${item%%::*}
  command=${item#*::}
  value=$(timeout 2s bash -lc "$command" 2>/dev/null || true)
  add_segment "$label" "$value"
done

if (( STATUS_SHOW_IP )); then
  ip_address=$(hostname -I 2>/dev/null | awk '{print $1}')
  add_segment "IP" "$ip_address" "$STATUS_WIDTH_IP"
fi

add_segment "" "$(date "+$STATUS_DATE_FORMAT $STATUS_TIME_FORMAT")" "$STATUS_WIDTH_DATE"
for ((index = 0; index < ${#segments[@]}; index++)); do
  (( index > 0 )) && printf ' #[fg=colour238]| '
  printf '%s' "${segments[index]}"
done
