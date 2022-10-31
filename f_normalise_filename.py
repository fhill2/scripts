#!/usr/bin/env python
import sys, os
from f.string import normalise_filename

SHOULD_RENAME= True if len(sys.argv) > 1 and "rename" in sys.argv[1] else False

def stdin_normalise(lines):
    if SHOULD_RENAME:
        user_input = input(f'WARNING: you are about to rename {len(lines)} files. proceed Y/n? ')
        if not "Y" or not "y" in user_input:
            exit()

    for abs in lines:
        # TODO: support relative filepaths
        abs = abs.strip()
        if not os.path.isabs(abs):
            print("not an absolute filepath - exiting")
            exit()

        normalised_filename = normalise_filename(abs)
        if SHOULD_RENAME:
            print(f"RENAMED: {abs} --> {normalised_filename}")
            os.rename(abs, normalised_filename)
        else:
            print(normalised_filename)


# https://stackoverflow.com/questions/19172563/how-do-i-accept-piped-input-and-then-user-prompted-input-in-a-python-script
lines = sys.stdin.readlines()
sys.stdin = open("/dev/tty", "r")
stdin_normalise(lines)

