#!/usr/bin/env bash
# list-claude-sessions.sh
# List all Claude Code sessions with name, id, and update date,
# sorted by update date (most recent first).

set -euo pipefail

PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

List Claude Code sessions sorted by update date (descending).

Options:
  -n, --name-width N   Truncate session name to N chars (default: 80)
  -h, --help           Show this help

Environment:
  CLAUDE_PROJECTS_DIR  Override projects dir (default: \$HOME/.claude/projects)
EOF
}

NAME_WIDTH=80
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--name-width) NAME_WIDTH="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ ! -d "$PROJECTS_DIR" ]]; then
    echo "Error: Claude projects directory not found: $PROJECTS_DIR" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: 'jq' is required but not installed." >&2
    exit 1
fi

file_mtime() {
    stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1"
}

format_date() {
    date -d "@$1" '+%Y-%m-%d %H:%M:%S' 2>/dev/null \
        || date -r "$1" '+%Y-%m-%d %H:%M:%S'
}

# Extract a session "name": prefer the first non-empty user prompt in the
# JSONL transcript; fall back to the project directory name.
session_name() {
    local file="$1" name
    name=$(jq -r '
        select(.type == "user" and .message?.content != null)
        | ( .message.content
            | if type == "string" then .
              elif type == "array" then
                ( map(select(.type == "text") | .text) | join(" ") )
              else "" end )
        | select(length > 0)
    ' "$file" 2>/dev/null | head -n 1 | tr '\n\t' '  ')
    if [[ -z "$name" ]]; then
        name="($(basename "$(dirname "$file")"))"
    fi
    printf '%s' "$name"
}

truncate_str() {
    local s="$1" n="$2"
    if (( ${#s} > n )); then
        printf '%s...' "${s:0:n-3}"
    else
        printf '%s' "$s"
    fi
}

rows=()
while IFS= read -r -d '' file; do
    session_id="$(basename "$file" .jsonl)"
    mtime="$(file_mtime "$file")"
    name="$(session_name "$file")"
    rows+=("${mtime}"$'\t'"${session_id}"$'\t'"${name}")
done < <(find "$PROJECTS_DIR" -type f -name '*.jsonl' -print0)

if (( ${#rows[@]} == 0 )); then
    echo "No Claude Code sessions found in $PROJECTS_DIR" >&2
    exit 0
fi

printf '%-19s  %-36s  %s\n' 'UPDATED' 'SESSION ID' 'NAME'
printf '%s\n' "${rows[@]}" \
    | sort -t $'\t' -k1,1nr \
    | while IFS=$'\t' read -r mtime session_id name; do
        date_str="$(format_date "$mtime")"
        name="$(truncate_str "$name" "$NAME_WIDTH")"
        printf '%-19s  %-36s  %s\n' "$date_str" "$session_id" "$name"
    done
