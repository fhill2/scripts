#!/usr/bin/env bash
# https://github.com/jarun/nnn/blob/master/plugins/preview-tabbed

# Description: tabbed/xembed based file previewer
#
# Dependencies:
#   - tabbed (https://tools.suckless.org/tabbed): xembed host
#   - xterm (or urxvt or st) : xembed client for text-based preview
#   - mpv (https://mpv.io): xembed client for video/audio
#   - sxiv (https://github.com/muennich/sxiv) or,
#   - nsxiv (https://codeberg.org/nsxiv/nsxiv) : xembed client for images
#   - zathura (https://pwmt.org/projects/zathura): xembed client for PDF
#   - nnn's nuke plugin for text preview and fallback
#     nuke is a fallback for 'mpv', 'sxiv'/'nsxiv', and 'zathura', but has its
#     own dependencies, see the script for more information
#   - vim (or any editor/pager really)
#   - file
#   - mktemp
#   - xdotool (optional, to keep main window focused)
#
# Usage:
#   - Install the dependencies. Then set a NNN_FIFO
#     and set a key for the plugin, then start `nnn`:
#       $ NNN_FIFO=/tmp/nnn.fifo nnn
#   - Launch the plugin with the designated key from nnn
#
# Notes:
#   1. This plugin needs a "NNN_FIFO" to work. See man.
#   2. If the same NNN_FIFO is used in multiple nnn instances, there will be one
#      common preview window. With different FIFO paths, they will be independent.
#
# How it works:
#   We use `tabbed` [1] as a xembed [2] host, to have a single window
#   owning each previewer window. So each previewer must be a xembed client.
#   For text previewers, this is not an issue, as there are a lot of
#   xembed-able terminal emulator (we default to `xterm`, but examples are
#   provided for `urxvt` and `st`). For graphic preview this can be trickier,
#   but a few popular viewers are xembed-able, we use:
#     - `mpv`: multimedia player, for video/audio preview
#     - `sxiv`/`nsxiv`: image viewer
#     - `zathura`: PDF viewer
#     - but we always fallback to `nuke` plugin
#
# [1]: https://tools.suckless.org/tabbed/
# [2]: https://specifications.freedesktop.org/xembed-spec/xembed-spec-latest.html
#
# Shell: Bash (job control is weakly specified in POSIX)
# Author: Léo Villeveygoux


# fhill2:
# to start preview_tabbed without using any file manager plugin (xplr or nnn)
# NNN_FIFO=/home/f1/tmp/nnn.fifo preview_tabbed.bash
# check if preview_tabbed is running:
# ps aux | grep preview_tabbed -> bash /home/f1/dev/bin/preview_tabbed.bash
# test 2 times and it shouldnt hang:
# echo '/home/f1/tmp/test/file.txt' >> /home/f1/tmp/nnn.fifo
# echo '/home/f1/tmp/test/file.txt' >> /home/f1/tmp/nnn.fifo


XDOTOOL_TIMEOUT=2
PAGER=${PAGER:-"vim -R"}
NUKE="${XDG_CONFIG_HOME:-$HOME/.config}/nnn/plugins/nuke"

#
# if type xterm >/dev/null 2>&1 ; then
#     TERMINAL="xterm -into"
# elif type urxvt >/dev/null 2>&1 ; then
#     TERMINAL="urxvt -embed"
# elif type st >/dev/null 2>&1 ; then
#     TERMINAL="st -w"
# else
#     notify-send "No xembed term found" >&2
# fi


term_nuke () {
    # $1 -> $XID, $2 -> $FILE
    $TERMINAL "$1" -e "$NUKE" "$2" &
}

start_tabbed () {
    notify-send "start tabbed"
    FIFO="$(mktemp -u)"
    mkfifo "$FIFO"

    tabbed > "$FIFO" &

    jobs # Get rid of the "Completed" entries

    TABBEDPID="$(jobs -p %%)"

    if [ -z "$TABBEDPID" ] ; then
        notify-send "Can't start tabbed"
        exit 1
    fi

    read -r XID < "$FIFO"

    rm "$FIFO"
}

get_viewer_pid () {
        VIEWERPID="$(jobs -p %%)"
}

kill_viewer () {
        if [ -n "$VIEWERPID" ] && jobs -p | grep "$VIEWERPID" ; then
            notify-send "killed viewer pid"
            kill "$VIEWERPID"
        fi
}

sigint_kill () {
  notify-send "sigint kill"
	kill_viewer
	kill "$TABBEDPID"
	exit 0
}

previewer_loop () {
  echo "got here 1"
    unset -v NNN_FIFO
    # mute from now
    # exec >/dev/null 2>&1

    MAINWINDOW="$(xdotool getactivewindow)"

    start_tabbed
    echo "got here 2"
    trap sigint_kill SIGINT

    xdotool windowactivate "$MAINWINDOW"

    # Bruteforce focus stealing prevention method,
    # works well in floating window managers like XFCE
    # but make interaction with the preview window harder
    # (uncomment to use):
    #xdotool behave "$XID" focus windowactivate "$MAINWINDOW" &

    while read -r FILE ; do
        jobs # Get rid of the "Completed" entries

        if ! jobs | grep tabbed ; then
            break
        fi

        if [ ! -e "$FILE" ] ; then
            continue
        fi

        kill_viewer

        MIME="$(file -bL --mime-type "$FILE")"

        case "$MIME" in
            video/*)
                if type mpv >/dev/null 2>&1 ; then
                    mpv --force-window=immediate --loop-file --wid="$XID" "$FILE" &
                else
                    term_nuke "$XID" "$FILE"
                fi
                ;;
            audio/*)
                if type mpv >/dev/null 2>&1 ; then
                    mpv --force-window=immediate --loop-file --wid="$XID" "$FILE" &
                else
                    term_nuke "$XID" "$FILE"
                fi
                ;;
            image/*)
                if type sxiv >/dev/null 2>&1 ; then
                    sxiv -ae "$XID" "$FILE" &
                elif type nsxiv >/dev/null 2>&1 ; then
                    nsxiv -ae "$XID" "$FILE" &
                else
                    term_nuke "$XID" "$FILE"
                fi
                ;;
            application/pdf)
                if type zathura >/dev/null 2>&1 ; then
                    zathura -e "$XID" "$FILE" &
                else
                    term_nuke "$XID" "$FILE"
                fi
                ;;
            inode/directory)
                $TERMINAL "$XID" -e nnn "$FILE" &
                ;;
            text/*)
                if [ -x "$NUKE" ] ; then
                    term_nuke "$XID" "$FILE"
                else
                    # shellcheck disable=SC2086
                    $TERMINAL "$XID" -e $PAGER "$FILE" &
                fi
                ;;
            *)
                if [ -x "$NUKE" ] ; then
                    term_nuke "$XID" "$FILE"
                else
                    $TERMINAL "$XID" -e sh -c "file '$FILE' | $PAGER -" &
                fi
                ;;
        esac
        get_viewer_pid

        # following lines are not needed with the bruteforce xdotool method
        ACTIVE_XID="$(xdotool getactivewindow)"
        if [ $((ACTIVE_XID == XID)) -ne 0 ] ; then
            xdotool windowactivate "$MAINWINDOW"
        else
            timeout "$XDOTOOL_TIMEOUT" xdotool behave "$XID" focus windowactivate "$MAINWINDOW" &
        fi
    done
    kill "$TABBEDPID"
    kill_viewer
    echo "end previewer loop"
}

if [ ! -r "$NNN_FIFO" ] ; then
    notify-send "Can't read \$NNN_FIFO ('$NNN_FIFO')"
    exit 1
fi

previewer_loop < "$NNN_FIFO" &
disown
# NNN_FIFO=~/tmp/nnn.fifo
# previewer_loop < "$NNN_FIFO"
# while read -r line <$NNN_FIFO; do
       # if [ -n "$line" ]; then previewer_loop $line; fi
# done
