--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Synthesised sound, mixed in a task of its own and played through
--  PulseAudio: the engine, the wind, scraping, the other cars, and the
--  bangs of the weapons.  Without a sound server the game is silent.

package Audio is

   type Params is record
      Speed    : Float := 0.0;   --  m/s
      Throttle : Float := 0.0;
      Boost    : Boolean := False;
      Air      : Boolean := False;   --  wheels off the ground
      Scrape   : Float := 0.0;   --  0 .. 1
      Slip     : Float := 0.0;
      Other_Speed, Other_Level, Other_Pan : Float := 0.0;   --  the nearest other car
      Master   : Float := 0.8;
   end record;

   procedure Start;
   procedure Stop;
   procedure Set (P : Params);

   type Effect is (Bang, Thud, Pickup, Launch, Drop, Zap, Whoosh, Shield, Beep_Low, Beep_High, Lap);

   procedure Play (E : Effect; Level : Float := 1.0; Pan : Float := 0.0);
   --  Level 0 .. 1, Pan -1 left .. 1 right

end Audio;
