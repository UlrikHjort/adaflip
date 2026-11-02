--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  A car: a rigid body on four big wheels that stand out above the body as
--  far as below it, so it drives whichever way up it lands.  The wheels
--  touch the track's surface wherever it is (floor, wall or roof); at speed
--  the car clings to walls and roofs.

with Math3D; use Math3D;

package Vehicle is

   type Wheel_Id is range 1 .. 4;   --  front left, front right, rear left, rear right
   type Float4 is array (Wheel_Id) of Float;
   type Bool4 is array (Wheel_Id) of Boolean;

   Wheel_X : constant Float4 := (-1.15, 1.15, -1.15, 1.15);
   Wheel_Z : constant Float4 := (1.35, 1.35, -1.3, -1.3);   --  forward of the middle
   Wheel_R : constant := 0.62;
   Travel  : constant := 0.28;
   Mass    : constant := 1000.0;
   Gravity : constant := 9.81;

   type Controls is record
      Steer    : Float := 0.0;   --  -1 left .. 1 right
      Throttle : Float := 0.0;   --  0 .. 1
      Brake    : Float := 0.0;   --  0 .. 1, reverses when stopped
   end record;

   type Car is record
      P, V, W : Vec3 := Zero;            --  place, velocity, spin (world)
      F : Vec3 := (0.0, 0.0, -1.0);      --  forward
      U : Vec3 := Up_Y;                  --  up (the body's; it may be upside down)
      R : Vec3 := (1.0, 0.0, 0.0);       --  right
      Hint : Natural := 0;
      S : Float := 0.0;                  --  metres along the track
      Steer : Float := 0.0;
      Contact : Bool4 := (others => False);
      Drop : Float4 := (others => 0.0);  --  the wheel drawn this far along U from its hub
      Spin : Float4 := (others => 0.0);  --  turned so far, radians
      Grounded : Natural := 0;           --  wheels touching
      Ground_N : Vec3 := Up_Y;           --  the surface under the wheels
      Side : Float := 1.0;               --  1 the right way up, -1 upside down
      Speed, Fwd_Speed : Float := 0.0;
      Power : Float := 1.0;              --  for the AI's skill
      Boost_T, Shield_T, Stun_T : Float := 0.0;
      Air_T, Still_T : Float := 0.0;
      Scrape : Float := 0.0;             --  0 .. 1, along a wall on its body
      Scrape_At : Vec3 := Zero;
      Impact : Float := 0.0;             --  m/s into the surface, the hardest this step
      Slip : Float := 0.0;               --  0 .. 1, tyres sliding
      Outside : Float := 0.0;            --  through the surface (lost)
   end record;

   procedure Place (C : in out Car; S, X : Float);
   --  Standing on the floor, S metres along and X right, facing along

   procedure Step (C : in out Car; In_C : Controls; Dt : Float);

   procedure Collide (A, B : in out Car);
   --  Two cars that meet push each other apart

   procedure Blast (C : in out Car; From : Vec3; Strength : Float; Seed : Natural);
   --  Thrown by an explosion; nothing happens through a shield

   function Hub (C : Car; W : Wheel_Id) return Vec3;

end Vehicle;
