--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The circuits.  A track is a closed spline with a cross-section that
--  changes along it: an open road between walls, a tunnel with a roof, a
--  round pipe, a halfpipe.  Every cross-section is a rounded box, so the
--  road, the walls and the roof are one surface, and a car may drive on
--  any of it: the physics ask how far a point is inside the box and which
--  way is out of the surface.

with Math3D; use Math3D;

package Track is

   Track_Count : constant := 3;
   subtype Track_Id is Positive range 1 .. Track_Count;

   type Theme_Kind is (Desert, City, Ice);

   type Section_Kind is (Open, Wide, Halfpipe, Tunnel, Pipe);

   --  The cross-section in the track's frame: X right, Y up from the
   --  middle of the floor.  A box Width wide and Height high with its
   --  bottom corners rounded by R_Bottom and the top ones by R_Top.  On an
   --  open road the top is out of sight (and out of reach): only the walls
   --  up to Wall_Height are built.
   type Profile is record
      Width, Height, R_Bottom, R_Top, Wall_Height : Float := 0.0;
      Roof : Float := 0.0;   --  1 under a roof, 0 in the open
   end record;

   type Sample is record
      C : Vec3;          --  middle of the floor
      T, N, B : Vec3;    --  along, up, right
      P : Profile;
      Curve : Float;     --  1/m, positive turning right
      Vmax : Float;      --  m/s the AI dare
      Kind : Section_Kind;
   end record;

   procedure Load (Id : Track_Id);

   function Name (Id : Track_Id) return String;
   function Theme (Id : Track_Id) return Theme_Kind;
   function Current return Track_Id;
   function Grip return Float;   --  of the current track's surface

   function Count return Positive;
   function Step return Float;     --  metres between samples
   function Length return Float;

   function Get (I : Integer) return Sample;   --  any I, wrapped round
   function At_S (S : Float) return Sample;     --  between samples

   --  Where a point is
   type Locus is record
      I     : Natural := 0;  --  the sample just behind
      S     : Float := 0.0;  --  metres along
      X, Y  : Float := 0.0;  --  in the cross-section
      C, T, N, B : Vec3 := Zero;
      P     : Profile;
   end record;

   function Locate (P : Vec3; Hint : Natural) return Locus;
   --  Hint: the sample index the point was near last time

   procedure Surface (L : Locus; Inside : out Float; Normal : out Vec3);
   --  Inside: metres from the point to the surface, negative when through
   --  it; Normal: from the surface into the track, in the world

   function Profile_Distance (P : Profile; X, Y : Float) return Float;
   procedure Profile_Normal (P : Profile; X, Y : Float; NX, NY : out Float);
   --  The same in the cross-section alone

   function Floor_Point (S, X : Float) return Vec3;
   --  On the floor, X metres right of the middle

   function Floor_Half (S : Float) return Float;
   --  Half the width of the flat floor

   --  Where the weapon pods are
   Max_Pods : constant := 60;
   type Pod_List is array (1 .. Max_Pods) of Vec3;
   function Pod_Count return Natural;
   function Pods return Pod_List;

end Track;
