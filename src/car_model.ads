--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The shapes that move: the car (the same seen from above as from below,
--  since it drives either way up), its wheel, the weapon pod, the rocket,
--  the mine and the shield.  In their own frame: X right, Y up, the nose
--  towards -Z.

with Mesh;
with Math3D;

package Car_Model is

   Body_Mesh, Wheel_Mesh, Pod_Mesh, Rocket_Mesh, Mine_Mesh, Shield_Mesh : Mesh.GPU;

   procedure Build;
   --  (GL context current)

   procedure Prism (B : in out Mesh.Builder; Base : Math3D.Vec3; R0, R1, H : Float;
                    Sides : Positive; Col : Mesh.Color; Mat : Float; Turn : Float := 0.0);
   --  A tapering column standing on Base, with a lid (none when R1 is 0)

   type Paint_List is array (Natural range <>) of Mesh.Color;
   Paints : constant Paint_List :=
     ((0.95, 0.2, 0.02),     --  orange
      (0.1, 0.45, 0.95),     --  blue
      (0.9, 0.1, 0.15),      --  red
      (0.15, 0.8, 0.3),      --  green
      (0.95, 0.8, 0.1),      --  yellow
      (0.7, 0.2, 0.9),       --  violet
      (0.1, 0.85, 0.85),     --  cyan
      (0.92, 0.92, 0.95));   --  white

end Car_Model;
