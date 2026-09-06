#!/usr/bin/env bash
# Gathers "places" for the Bookmark Everything Places picker.
# Output lines: kind <TAB> source <TAB> path <TAB> label
# Sources (each optional, skipped when absent):
#   sidebar  ~/.config/gtk-3.0/bookmarks         (Files sidebar bookmarks)
#   frequent zoxide query -l                     (most-visited folders)
#   recent   ~/.local/share/recently-used.xbel   (GTK recent files)
# Only paths that still exist are printed, deduplicated, first source wins.

urldecode() { local u="${1//+/ }"; printf '%b' "${u//%/\\x}"; }

{
  b="$HOME/.config/gtk-3.0/bookmarks"
  if [[ -f $b ]]; then
    while read -r uri label; do
      case "$uri" in file://*) printf 'sidebar\t%s\t%s\n' "$(urldecode "${uri#file://}")" "$label" ;; esac
    done < "$b"
  fi
  if command -v zoxide >/dev/null 2>&1; then
    zoxide query -l 2>/dev/null | head -n 200 | while read -r p; do printf 'frequent\t%s\t\n' "$p"; done
  fi
  r="$HOME/.local/share/recently-used.xbel"
  if [[ -f $r ]]; then
    grep -o 'href="file://[^"]*"' "$r" | tail -n 150 | tac | sed 's/^href="file:\/\///; s/"$//' \
      | while read -r p; do printf 'recent\t%s\t\n' "$(urldecode "$p")"; done
  fi
} | awk -F'\t' '$2 != "" && !seen[$2]++' | while IFS=$'\t' read -r src p label; do
  if [[ -d $p ]]; then k=folder; elif [[ -e $p ]]; then k=file; else continue; fi
  printf '%s\t%s\t%s\t%s\n' "$k" "$src" "$p" "$label"
done
