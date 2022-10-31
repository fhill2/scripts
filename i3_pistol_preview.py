#!/usr/bin/env python

# this previewer is inspired by preview_tabbed from nnn plugins
# I recreated this as I wanted a sway i3 agnostic previewer (that did not rely on tabbed)
# it is recreated in python using ipc python library specifically as I can wait for windows to be ready subscribing to i3 events
# it is meant to keep 1 terminal constantly open to show any terminal previews, 
# and to keep only 1 GUI previewer open at a time

# https://pypi.org/project/python-magic/
# python-magic use libmagic library
# pistol uses libmagic C library
import magic, json, subprocess, multiprocessing, os, shlex
# from f.util import run_sh, dump

import time

from i3ipc import Connection, Event


class Previewer():
    def __init__(self):
        self.i3 = Connection()
        # self.update_state()
        self.pwins = False
        self.term_exists = False

    def update_state(self):
        try:
            self.pwins = self.i3.get_tree().find_marked("preview_container")[0].nodes
        except:
            pass
        else:
            all_window_classes = [win.window_class for win in self.pwins]
            self.term_exists = True if "kitty" in all_window_classes else False

        if not self.pwins:
            self.mwin = self.i3.get_tree().find_focused()
            self.mwin.command("splith")


    def find_hidden_preview_windows(self):
        """find the visible windows underneath container passed in"""
        """TODO: this will not work on sway - however sway includes visible property in the json returned from get_tree, and can be easily edited to do so"""
        visible_windows = []
        for w in self.pwins:

            try:
                xprop = subprocess.check_output(['xprop', '-id', str(w.window)]).decode()
            except FileNotFoundError:
                raise SystemExit("The `xprop` utility is not found!" " Please install it and retry.")

            if '_NET_WM_STATE_HIDDEN' in xprop:
                visible_windows.append(w)

        return visible_windows

    def open_wait_window(self, cmd):
        """opens a previewer window in the preview container"""
        def on_window_new(_, e):
            self.i3.main_quit()
            global WINDOW_DATA
            WINDOW_DATA = e
        self.i3.on(Event.WINDOW_NEW, on_window_new)
        def open_window():
            subprocess.run(shlex.split(cmd))
            # i3.command(f"exec {cmd}")
        proc = multiprocessing.Process(target=open_window)
        if self.pwins:
            self.pwins[0].command("focus")
        proc.start()
        self.i3.main()
        con = WINDOW_DATA.container
        if not self.pwins:
            con.command("splith; layout tabbed; focus parent; mark preview_container")
        return con


    def preview(self, cmd):
        """opens a non terminal previwer window and kills all other non terminal previewer windows"""
        self.update_state()

        con = self.open_wait_window(cmd)

        # kill all windows that arent terminal windows (excluding the window just launched)
        if self.pwins:
            for win in self.pwins:
                if win.window_class != "kitty":
                    if win != con: 
                        win.command("kill")

        self.mwin.command("focus")




    def preview_terminal(self, abs, mime):
        """previews in the terminal window"""
        self.update_state()
        if not self.term_exists:
            con = self.open_wait_window(f"kitty sh -c 'i3_preview_terminal.sh \"{abs}\"'")
            # TODO: if the writer sends to pipe before reader opens, i3_preview_terminal.sh receives spammed input
            # sleep fixes this
            time.sleep(0.1)
            self.term_fifo_write = open('/home/f1/tmp/preview_terminal.fifo', 'w')
        self.term_fifo_write.write(f"{abs} {mime}\n")
        self.term_fifo_write.flush()
            
        # as no window is opened (if self.term_exists is True | on second invocation)
        # terminal window has to be refocused to be the visible tab in the tabbed preview container
        # checks for the prescense of "con" first, as if con exists, a window was spawned, and i3 implicitly focused new windows byt default
        if "con" not in locals():
            # hidden_window_classes = [win.window_class for win in find_hidden_preview_windows()]
            for win in self.find_hidden_preview_windows():
                if win.window_class == "kitty":
                    win.command("focus")


        self.mwin.command("focus")

# deps:
# viu - image viewer
# zathura - pdf
# mpv - video audio
P = Previewer()

def handle_mime(abs):
    abs = os.path.realpath(abs.strip())
    if not os.path.isabs(abs):
        subprocess.run("notify-send 'pass in an absolute path'")
        return

    if os.path.isdir(abs):
        mime = "inode/directory"
    else:
        mime = magic.from_file(abs, mime=True)
    print(mime)

    mimes = [
        (["video/", "audio/", "image/"], f'mpv "{abs}"'),
        (["office", "document", "application/pdf"], f'zathura "{abs}"'),
        (["text/", "inode/directory", "application/", "font/"], False) # terminal
    ]
    for m in mimes:
        queries = m[0]
        cmd = m[1]
        for query in queries:
            if query in mime:
                if cmd:
                    P.preview(cmd)
                else:
                    P.preview_terminal(abs, mime)

FIFO="/home/f1/tmp/preview.fifo"
while True:
    with open(FIFO, 'r') as pipe:
        handle_mime(pipe.read())


# mpv dont exit on file
# go through all preview_tui deps and mime types, set it up to act like that
