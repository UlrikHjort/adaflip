# AdaFlip: a combat racer in Ada
# Copyright (c) 2026 Ulrik Hørlyk Hjort
# SPDX-License-Identifier: MIT
#
#   make         build the game
#   make run     build and start it
#   make test    the headless race and wall-driving checks
#   make clean

all: game

game:
	gprbuild -p -P adaflip.gpr -j0

run: game
	./bin/adaflip

test:
	gprbuild -p -P simtest.gpr -j0
	./bin/simtest
	./bin/walltest

clean:
	gprclean -q -P adaflip.gpr
	gprclean -q -P simtest.gpr

.PHONY: all game run test clean
