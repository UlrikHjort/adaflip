#!/bin/sh
# AdaFlip: a combat racer in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
# Is everything needed to build AdaFlip here?  Says what is missing and how to
# get it; exit status 1 if something is.  `make` runs this first.
#
#   scripts/check_deps.sh          for the game
#   scripts/check_deps.sh tests    for the headless tests (the compiler only)

MISSING=""       # what to tell
DEBIAN=""        # the Debian/Ubuntu packages for it
have () { command -v "$1" > /dev/null 2>&1; }
need () { MISSING="$MISSING\n  - $1"; DEBIAN="$DEBIAN $2"; }

have gnatmake || need "GNAT, the Ada compiler" gnat
have gprbuild || need "gprbuild, the project builder" gprbuild

if [ "$1" != tests ]; then
    GTKADA=no
    if have gnatls; then
        for D in $(echo "${GPR_PROJECT_PATH:-}" | tr ':' ' ') \
                 $(gnatls -v 2> /dev/null | sed -n '/Project Search Path/,/^$/p' | tail -n +2); do
            [ -f "$D/gtkada.gpr" ] && GTKADA=yes
        done
    fi
    [ "$GTKADA" = yes ] || need "GtkAda, GTK for Ada (gtkada.gpr was not found)" libgtkada-dev

    if have pkg-config; then
        pkg-config --exists gtk+-3.0 || need "GTK 3 development files" libgtk-3-dev
        pkg-config --exists epoxy || need "libepoxy, the OpenGL loader" libepoxy-dev
        pkg-config --exists libpulse-simple || need "PulseAudio development files (for the sound)" libpulse-dev
    else
        need "pkg-config (to look for the libraries)" pkg-config
    fi
fi

[ -z "$MISSING" ] && exit 0

printf "AdaFlip cannot be built yet. Missing:$MISSING\n\n"
echo "To install them:"
echo "  Debian, Ubuntu, Mint: sudo apt install$DEBIAN"
case "$DEBIAN" in *libgtkada*)
echo "      (on some releases GtkAda is libgtkada20-dev or similar: apt search libgtkada)";;
esac
echo "  Fedora:   sudo dnf install gcc-gnat gprbuild gtkada-devel gtk3-devel libepoxy-devel pulseaudio-libs-devel pkgconf"
echo "  Arch:     sudo pacman -S gcc-ada gprbuild gtk3 libepoxy libpulse pkgconf, and gtkada from the AUR"
echo "  openSUSE: sudo zypper install gcc-ada gprbuild gtkada-devel gtk3-devel libepoxy-devel libpulse-devel pkg-config"
echo
echo "Then run make again. If GtkAda is installed somewhere of your own, add its folder"
echo "to GPR_PROJECT_PATH."
exit 1
