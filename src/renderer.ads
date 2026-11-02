--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Draws one frame: the sky, the world, the cars and what flies about, the
--  sparks and smoke, then glow and tone mapping onto the screen.  The
--  camera follows the surface the car is on, so on a wall or a roof the
--  world turns round it.

with Math3D;
with Race;

package Renderer is

   type Camera_Kind is (Chase, Far_Chase, Bumper);

   type View is record
      Camera    : Camera_Kind := Chase;
      Look_Back : Boolean := False;
      Focus     : Race.Car_Index := Race.Player;
      Orbit     : Boolean := False;   --  slowly round the car (behind the menu)
      Look_X    : Float := 0.0;       --  the right stick: -1 .. 1
   end record;

   procedure Create;
   --  (GL context current) programs, buffers, models

   procedure New_Track;
   --  After Race.Setup: the world rebuilt, the camera and effects reset

   procedure Draw (Width, Height : Natural; V : View; Alpha, Dt : Float);
   --  Into the frame buffer GTK has bound; Alpha: how far between the last
   --  two physics steps

   Flash : Float := 0.0;   --  0 .. 1, the screen lights up (when hit)

   function Camera_Position return Math3D.Vec3;
   function Camera_Right return Math3D.Vec3;

end Renderer;
