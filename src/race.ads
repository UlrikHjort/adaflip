--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  A race: the cars on the grid, the laps and places, the AI drivers, the
--  weapon pods and what is fired from them.  No graphics here; what
--  happens is told as events for the sound, the effects and the panels.

with Math3D; use Math3D;
with Track;
with Vehicle;

package Race is

   Max_Cars : constant := 8;
   subtype Car_Index is Positive range 1 .. Max_Cars;
   Player : constant Car_Index := 1;

   type Weapon is (None, Turbo, Rocket, Mine, Pulse, Shield);

   function Weapon_Name (W : Weapon) return String;

   type Difficulty is (Easy, Normal, Hard);

   type Racer is record
      Car       : Vehicle.Car;
      Prev_P, Prev_F, Prev_U : Vec3 := Zero;   --  at the step before, for drawing in between
      AI        : Boolean := True;
      Name      : String (1 .. 8) := (others => ' ');
      Color     : Natural := 0;
      Lap       : Integer := -1;      --  laps done; -1 behind the line at the start
      Progress  : Float := 0.0;       --  metres raced
      Last_S    : Float := 0.0;
      Lap_Start : Float := 0.0;
      Last_Lap, Best_Lap : Float := 0.0;
      Finished  : Boolean := False;
      Finish_T  : Float := 0.0;
      Place     : Positive := 1;
      Held      : Weapon := None;
      Lane      : Float := 0.0;       --  where across the road the AI likes to be
      Skill     : Float := 1.0;
      Fire_Wait : Float := 0.0;
      Resets    : Natural := 0;
      Wrong_Way : Float := 0.0;       --  seconds of it
      Hits      : Natural := 0;
   end record;

   type Racer_Array is array (Car_Index) of Racer;

   type Phase_Kind is (Countdown, Running, Over);

   type State_Type is record
      Racers    : Racer_Array;
      Count     : Car_Index := 6;
      Laps      : Positive := 3;
      Phase     : Phase_Kind := Countdown;
      Clock     : Float := 0.0;   --  race time; negative during the countdown
      Attract   : Boolean := False;  --  everyone is the AI (behind the menu)
      Over_T    : Float := 0.0;
   end record;

   State : State_Type;

   --  Things flying and lying about
   type Shot is record
      Active : Boolean := False;
      P, V   : Vec3 := Zero;
      Owner, Target : Natural := 0;
      Life   : Float := 0.0;
      Hint   : Natural := 0;
   end record;
   type Shot_Array is array (1 .. 24) of Shot;
   Shots : Shot_Array;

   type Mine_Rec is record
      Active : Boolean := False;
      P, N   : Vec3 := Zero;
      Owner  : Natural := 0;
      Age    : Float := 0.0;
   end record;
   type Mine_Array is array (1 .. 24) of Mine_Rec;
   Mines : Mine_Array;

   type Pod is record
      P : Vec3 := Zero;
      Wait : Float := 0.0;   --  back when 0
   end record;
   type Pod_Array is array (1 .. Track.Max_Pods) of Pod;
   Pods : Pod_Array;
   Pod_Count : Natural := 0;

   --  What happened, for the sound, the effects and the panels
   type Event_Kind is
     (Explosion, Picked, Fired_Rocket, Dropped_Mine, Pulsed, Boost_On, Shield_On,
      Bump, Scrape, Lap_Done, Final_Lap, Finished, Beep, Go, Hit_Player, Reset_Car);
   --  Hit_Player: Car was hit by Other, one of them the player

   type Event is record
      Kind  : Event_Kind := Bump;
      P     : Vec3 := Zero;
      Car   : Natural := 0;
      Other : Natural := 0;
      Size  : Float := 0.0;
      W     : Weapon := None;
   end record;

   Event_Ring : constant := 256;
   type Event_Array is array (0 .. Event_Ring - 1) of Event;
   Events : Event_Array;
   Event_Serial : Natural := 0;   --  how many so far; the newest at (Serial - 1) mod Ring

   type Player_Input is record
      Drive : Vehicle.Controls;
      Fire  : Boolean := False;   --  pressed since the last step
      Reset : Boolean := False;
   end record;

   procedure Setup (Id : Track.Track_Id; Opponents : Natural; Laps : Positive;
                    Level : Difficulty; Attract : Boolean);
   --  Track.Load first is done here too

   Dt : constant := 1.0 / 360.0;

   procedure Step (Input : Player_Input; Player_AI : Boolean := False);
   --  One physics step of Dt

   Stunt_Player : Boolean := False;
   --  The player's car driven by the AI rides the walls and roofs (videos)

   procedure Reset_Racer (I : Car_Index);
   --  Back on the floor where it left the track

   function Place_Of (I : Car_Index) return Positive;
   function Lap_Shown (I : Car_Index) return Positive;   --  the lap being raced, 1 ..

   Car_Names : constant array (1 .. Max_Cars) of String (1 .. 8) :=
     ("YOU     ", "VOLTA   ", "KESTREL ", "MAGPIE  ", "DYNAMO  ", "FURY    ", "ORBIT   ", "TANGO   ");

end Race;
