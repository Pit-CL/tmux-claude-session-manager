#!/usr/bin/env bash
# Open the session picker in a popup.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

prefix="$(get_tmux_option @claude_session_prefix 'claude-')"
w="$(get_tmux_option @claude_popup_width '90%')"
h="$(get_tmux_option @claude_popup_height '90%')"

# The session of a client attached to a prefixed session — i.e. the popup we are
# inside, if any. Empty when invoked from a normal (non-popup) pane.
nested_session() {
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
    awk -v p="$prefix" 'index($2, p) == 1 { print $2; exit }'
}

# A client NOT attached to a prefixed session — the outer client that should host
# the picker popup.
host_client() {
  tmux list-clients -F '#{client_name} #{session_name}' 2>/dev/null |
    awk -v p="$prefix" 'index($2, p) != 1 { print $1; exit }'
}

# If we are inside a session popup, close it (detach its client)
sess="$(nested_session)"
if [ -n "$sess" ]; then
  tmux detach-client -s "$sess"
  # Wait until the session is gone
  for _ in $(seq 1 100); do
    [ -z "$(nested_session)" ] && break
    sleep 0.05
  done
  # We just closed the popup of a claude session we were inside: the invoking client
  # was that now-detached nested client, so reopen the menu on the outer client via
  # the usual heuristic. Don't reuse $1 — it points at a client that no longer exists.
  host="$(host_client)"
else
  # Normal invocation from a non-prefixed session: host the popup on the *invoking*
  # client (passed by the binding as '#{client_name}') so that, with multiple clients
  # attached, the popup lands on the right terminal instead of whichever one
  # host_client() happens to list first.
  host="${1:-$(host_client)}"
fi
tmux set-option -g @claude_parent "$host"

# Host the picker on the outer client. -c is honored because that client has no
# popup open now; fall back to the default client if none was found.
if [ -n "$host" ]; then
  tmux display-popup -c "$host" -w "$w" -h "$h" -E "$DIR/picker.sh"
else
  tmux display-popup -w "$w" -h "$h" -E "$DIR/picker.sh"
fi
