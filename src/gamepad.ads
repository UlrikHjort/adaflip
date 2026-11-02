--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  A game controller (an Xbox pad and its like), read straight from the
--  Linux event device: the left stick steers, the triggers are throttle
--  and brake, and it rumbles.  An Xbox pad is preferred when several are
--  plugged in.

package Gamepad is

   type Button is
     (A, B, X, Y, LB, RB, Back, Start, Guide, L3, R3,
      Pad_Up, Pad_Down, Pad_Left, Pad_Right);

   type Input is record
      Steer    : Float := 0.0;   --  -1 left .. 1 right
      Stick_Y  : Float := 0.0;   --  -1 up .. 1 down
      Look_X, Look_Y : Float := 0.0;   --  the right stick
      Throttle : Float := 0.0;   --  0 .. 1
      Brake    : Float := 0.0;
   end record;

   procedure Open;
   --  Look for a controller under /dev/input/by-id; quietly nothing if none

   procedure Close;

   procedure Poll;
   --  What it sent since the last call; one plugged in later is found too

   function Present return Boolean;
   function State return Input;
   function Name return String;

   function Next_Press (B : out Button) return Boolean;
   --  Buttons pressed since the last Poll, one at a time

   function Held (B : Button) return Boolean;

   procedure Rumble (Strong, Weak : Float);
   --  0 .. 1, the heavy motor and the light one

   function Shape (Raw, Low, High : Float) return Float;
   --  A stick's raw reading: a dead zone, then finer near the middle

end Gamepad;
