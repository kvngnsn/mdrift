#!/bin/zsh
# Finder supplies the selected files/folders as arguments. Use the first item.
set -eu
if (( $# == 0 )); then
  print -u2 'Select a folder, or a file in the destination folder.'
  exit 1
fi
selected_item="$1"
if [[ -d "$selected_item" ]]; then
  destination_dir="$selected_item"
else
  destination_dir="${selected_item:h}"
fi
if [[ ! -d "$destination_dir" || ! -w "$destination_dir" ]]; then
  print -u2 'The selected folder is not writable.'
  exit 1
fi
# NOCLOBBER creates the file exclusively, including when two actions run
# together. Existing files, directories, and symbolic links are never replaced.
setopt NOCLOBBER
for number in {1..10000}; do
  if (( number == 1 )); then
    candidate="$destination_dir/Untitled.md"
  else
    candidate="$destination_dir/Untitled $number.md"
  fi
  if ( : > "$candidate" ) 2>/dev/null; then
    print -r -- "$candidate"
    exit 0
  fi
  if [[ ! -e "$candidate" && ! -L "$candidate" ]]; then
    print -u2 'Could not create a Markdown file in the selected folder.'
    exit 1
  fi
done
print -u2 'Too many Untitled files. Rename an existing file and try again.'
exit 1
