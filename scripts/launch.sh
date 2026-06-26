#!/usr/bin/env bash
# Launch (or re-attach to) a Claude session for a directory, shown in a popup.
# Args: <dir> [origin-window-id]   (both expanded by run-shell in the binding)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

path="${1:-$PWD}"
window="${2:-}"

prefix="$(get_tmux_option @claude_session_prefix 'claude-')"
cmd="$(get_tmux_option @claude_command 'claude')"
w="$(get_tmux_option @claude_popup_width '90%')"
h="$(get_tmux_option @claude_popup_height '90%')"

session="${prefix}$(session_hash "$path")"

if [[ "$(tmux display-message -p '#S')" == "$prefix"* ]]; then
  tmux display-message '🫪 Popup window already open'
  exit 0
fi

# Crear la sesión si no existe. Un mensaje claro vale más que la vista opaca de
# tmux ("command failed") cuando algo revienta.
if ! tmux has-session -t "$session" 2>/dev/null; then
  if ! tmux new-session -d -s "$session" -c "$path" "$cmd"; then
    tmux display-message "claude: no pude crear la sesión $session"
    exit 0
  fi
  # Verificar que claude realmente arrancó. Un server tmux con PATH mínimo mataba
  # la sesión al instante (claude no encontrado) y mostraba la caja beige opaca.
  sleep 0.2
  if ! tmux has-session -t "$session" 2>/dev/null; then
    tmux display-message "claude no arrancó (revisa que 'claude' esté en el PATH del server) — cmd: $cmd"
    exit 0
  fi
fi

# Record which window launched it, so the picker can jump back here later.
[ -n "$window" ] && tmux set-option -t "$session" @claude_origin "$window"

# '|| true' + 'exit 0': nunca dejar que run-shell muestre la vista opaca con el
# comando cuando el popup se cierra con código ≠ 0.
tmux display-popup -w "$w" -h "$h" -E "tmux attach-session -t $session" || true
exit 0
