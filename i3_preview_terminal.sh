#!/usr/bin/env sh

# this is an preview_tui.sh replacement
# this has partial functionality of preview_tabbed - it only handles terminal preview 
# this displays the file received at the pipe in the terminal
# partner script to i3_preview_daemon.sh

# ========== SETUP ==========
TMPDIR="$HOME/tmp"

create_fifo() {
if [ -p $1 ]; then
  rm -f "$1"
fi
mkfifo $1
}

fifo="$TMPDIR/preview_terminal.fifo"
pfifo="$TMPDIR/preview_terminal_pager.fifo"
trap "rm -f $fifo" EXIT

create_fifo $fifo
create_fifo $pfifo

PAGER="${PAGER:-less -P?n -R}"

handle_ext() {
ext="${1##*.}"
[ -n "$ext" ] && ext="$(printf "%s" "${ext}" | tr '[:upper:]' '[:lower:]')"
case "$ext" in
gz|bz2) tar -tvf "$1" > "$pfifo" ;;
md) glow -s dark "$1" ;;
7z|a|ace|alz|arc|arj|bz|cab|cpio|deb|jar|lha|lz|lzh|lzma|lzo\
        |rar|rpm|rz|t7z|tar|tbz|tbz2|tgz|tlz|txz|tZ|tzo|war|xpi|xz|Z)
  bsdtar -tvf "$1" > "$pfifo" ;;
htm|html|xhtml) notify-send "html not setup" ;;
*) bat --paging=always "$1" ;; # text
esac
}

pidkill() { [ -f "$1" ] && kill "$(cat "$1")" >/dev/null 2>&1 ;}
# killalljobs() { for pid in $( jobs -p ); do kill -9 $pid ; done ; }

handle_mime() {
  clear
$PAGER < "$pfifo" &
printf "%s" "$!" > "$PREVIEWPID"
# exec > "$pfifo"
case "$2" in
  inode/directory) 
    tree --filelimit "$(find . -maxdepth 1 | wc -l)" -L 3 -C -F --dirsfirst --noreport "$1" > "$pfifo" ;;
  application/octet-stream) mediainfo "$1" > "$pfifo" ;; # binary
  application/zip) unzip -l "$1" > "$pfifo" ;;
  application/font*|application/*opentype|font/*) fontpreview "$1" ;;
  *) handle_ext "$1" ;;
esac
}



preview_fifo() {
while read -r line <"$fifo"; do
  pidkill "$PREVIEWPID"
  # to debug if child processes get closed properly
  notify-send "$(jobs -p)"
  if [ -n "$line" ]; then 
    handle_mime $line & 
  fi
done
}

# preview_file "$1"
preview_fifo


# ========= 2=======
# handle_line < "$pipe"


# ========= 3=======
# while read LINE; do
#    echo ${LINE}    # do something with it here
# done
#
# exit 0
