#!/usr/bin/env bash
# Live preview of a Claude session's pane for the fzf picker.
#
# fzf only re-runs --preview when the highlighted row changes, so a one-shot
# `tmux capture-pane` freezes the right pane while the selected session keeps
# working. This loops instead: re-capture every INTERVAL seconds and repaint
# only when the content actually changed, so an idle session never flickers
# and a working one tracks Claude's output live.
set -uo pipefail

target="${1:-}"
[ -z "$target" ] && exit 0          # a group header was highlighted — nothing to show

INTERVAL=0.5
prev=''
while :; do
  cur=$(tmux capture-pane -ept "$target" 2>/dev/null) || break   # session gone -> freeze last frame
  if [ "$cur" != "$prev" ]; then
    printf '\033[2J\033[H%s' "$cur"  # clear + home, then repaint (full clear is wrap-safe)
    prev=$cur
  fi
  sleep "$INTERVAL"
done
