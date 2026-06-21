#!/usr/bin/env bash
# Interactive picker for running Claude sessions, grouped by project folder.
#
#   picker.sh           fzf picker; on enter, switches the parent client to the
#                       chosen session's origin window and resumes it in the popup.
#   picker.sh --list    print the rows only (used by fzf's ctrl-x reload).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

prefix="$(get_tmux_option @claude_session_prefix 'claude-')"

# Project "folder" a session belongs to. For a git repo or any of its worktrees
# this is the basename of the MAIN repo (so <repo> and every <repo>-<type>-<ts>
# worktree group together under one header). For a non-git directory it's the
# directory basename. Empty path -> a catch-all bucket.
project_of() {
  local path="$1" common base
  [ -z "$path" ] && { printf '(sin carpeta)'; return; }
  common=$(git -C "$path" rev-parse --git-common-dir 2>/dev/null)
  if [ -n "$common" ]; then
    case "$common" in /*) : ;; *) common="$path/$common" ;; esac
    base=$(cd "$common/.." 2>/dev/null && pwd)
    [ -n "$base" ] && { printf '%s' "${base##*/}"; return; }
  fi
  printf '%s' "${path##*/}"
}

# Branch label for a session's path: the git branch, "detached" on a detached
# HEAD, or empty for a non-git directory.
branch_of() {
  local path="$1" b
  [ -z "$path" ] && return
  b=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null) || return
  [ "$b" = HEAD ] && b='detached'
  printf '%s' "$b"
}

emit_rows() {
  local now s state at path icon rank agenum agestr proj branch label
  now=$(date +%s)
  # One record per session: proj \t rank \t agenum \t session \t icon \t label \t agestr
  tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^${prefix}" | while IFS= read -r s; do
    state=$(tmux show-options -qv -t "$s" @claude_state 2>/dev/null)
    at=$(tmux show-options -qv -t "$s" @claude_state_at 2>/dev/null)
    path=$(tmux display-message -p -t "$s" '#{pane_current_path}' 2>/dev/null)
    case "$state" in
    waiting) icon=$'\033[33m●\033[0m waiting' rank=0 ;; # yellow - needs input
    idle)    icon=$'\033[32m●\033[0m idle   ' rank=1 ;; # green  - done, your turn
    working) icon=$'\033[31m●\033[0m working' rank=3 ;; # red    - busy, leave it
    *)       icon=$'\033[90m●\033[0m   ?    ' rank=2 ;; # grey   - unknown (no hook yet)
    esac
    if [ -n "$at" ]; then agenum=$(((now - at) / 60)); agestr="${agenum}m"; else agenum=0; agestr='-'; fi
    proj=$(project_of "$path")
    branch=$(branch_of "$path")
    # In-group label: the branch on git, else the short session hash.
    if [ -n "$branch" ]; then label="$branch"; else label="${s#"$prefix"}"; fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$proj" "$rank" "$agenum" "$s" "$icon" "$label" "$agestr"
  # Group alphabetically by project; within a group, attention-needed (rank asc)
  # floats up, then most-recent (age asc) sits at the top of its group.
  done | sort -t$'\t' -k1,1 -k2,2n -k3,3n | awk -F'\t' '
    # Insert a bold, non-selectable header row each time the project changes,
    # then the session rows indented under it. fzf row = session \t visible;
    # header rows carry an empty session field so enter on them is a no-op.
    { if ($1 != last) { printf "\t\033[1m▸ %s\033[0m\n", $1; last = $1 }
      printf "%s\t    %s  %-24s %4s\n", $4, $5, $6, $7 }'
}

[ "${1:-}" = '--list' ] && {
  emit_rows
  exit 0
}

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "tmux-claude-session-manager: fzf is required for the picker"
  exit 0
fi

self="${BASH_SOURCE[0]}"
export FZF_DEFAULT_OPTS=''
sel=$(emit_rows | fzf --ansi --delimiter='\t' --with-nth=2 \
  --reverse --cycle --header='Claude sessions · enter: jump · ctrl-x: kill' \
  --preview="tmux capture-pane -ept {1}" --preview-window='right,62%,wrap' \
  --bind="ctrl-x:execute-silent(tmux kill-session -t {1})+reload($self --list)")

[ -z "$sel" ] && exit 0
target=$(printf '%s' "$sel" | cut -f1)
[ -z "$target" ] && exit 0   # a group header was picked — nothing to jump to

# Move the underlying parent client to the session's origin window (best-effort),
# then resume the session in THIS popup over it. Falls back to resuming over the
# current window when origin/parent are unknown.
origin=$(tmux show-options -qv -t "$target" @claude_origin 2>/dev/null)
parent=$(tmux show-options -gqv @claude_parent 2>/dev/null)
[ -n "$origin" ] && [ -n "$parent" ] &&
  tmux switch-client -c "$parent" -t "$origin" 2>/dev/null

tmux attach-session -t "$target"
