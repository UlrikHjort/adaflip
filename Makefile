# AdaFlip: a combat racer in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
#   make         build the game
#   make run     build and start it
#   make check   is everything needed to build it here?
#   make test    the headless race and wall-driving checks
#   make clean

all: game

check:
	@scripts/check_deps.sh

game: check
	gprbuild -p -P adaflip.gpr -j0

run: game
	./bin/adaflip

test:
	@scripts/check_deps.sh tests
	gprbuild -p -P simtest.gpr -j0
	./bin/simtest
	./bin/walltest

clean:
	gprclean -q -P adaflip.gpr
	gprclean -q -P simtest.gpr

.PHONY: all check game run test clean
