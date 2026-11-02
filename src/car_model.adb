--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;

package body Car_Model is

   use Ada.Numerics.Elementary_Functions;
   use Math3D;
   use Mesh;

   Pi : constant := Ada.Numerics.Pi;

   White  : constant Color := (1.0, 1.0, 1.0);
   Dark   : constant Color := (0.16, 0.16, 0.18);
   Steel  : constant Color := (0.55, 0.56, 0.6);
   Black  : constant Color := (0.04, 0.04, 0.045);

   procedure Prism (B : in out Builder; Base : Vec3; R0, R1, H : Float;
                    Sides : Positive; Col : Color; Mat : Float; Turn : Float := 0.0) is
      function P (K : Natural; R, Y : Float) return Vec3 is
         A : constant Float := Turn + 2.0 * Pi * Float (K) / Float (Sides);
      begin
         return Base + Vec3'(R * Cos (A), Y, R * Sin (A));
      end P;
   begin
      for K in 0 .. Sides - 1 loop
         if R1 > 0.0 then
            Quad (B, P (K, R0, 0.0), P (K + 1, R0, 0.0), P (K + 1, R1, H), P (K, R1, H), Col, Mat);
            Tri (B, Base + Vec3'(0.0, H, 0.0), P (K, R1, H), P (K + 1, R1, H), Col, Mat);
         else
            Tri (B, P (K, R0, 0.0), P (K + 1, R0, 0.0), Base + Vec3'(0.0, H, 0.0), Col, Mat);
         end if;
      end loop;
   end Prism;

   --  A body of octagonal sections along Z: each station a half width and
   --  a half height, the same above as below
   type Station is record
      Z, HW, HH : Float;
   end record;
   type Station_List is array (Positive range <>) of Station;

   procedure Loft (B : in out Builder; S : Station_List; Col : Color; Mat : Float;
                   Y0 : Float := 0.0; Cap_Front, Cap_Back : Float := -1.0) is
      type Ring is array (0 .. 7) of Vec3;
      function R (St : Station) return Ring is
        ((St.HW, Y0 + 0.45 * St.HH, St.Z), (0.65 * St.HW, Y0 + St.HH, St.Z),
         (-0.65 * St.HW, Y0 + St.HH, St.Z), (-St.HW, Y0 + 0.45 * St.HH, St.Z),
         (-St.HW, Y0 - 0.45 * St.HH, St.Z), (-0.65 * St.HW, Y0 - St.HH, St.Z),
         (0.65 * St.HW, Y0 - St.HH, St.Z), (St.HW, Y0 - 0.45 * St.HH, St.Z));
   begin
      for J in S'First .. S'Last - 1 loop
         declare
            A : constant Ring := R (S (J));
            C : constant Ring := R (S (J + 1));
         begin
            for K in 0 .. 7 loop
               Quad (B, A (K), A ((K + 1) mod 8), C ((K + 1) mod 8), C (K), Col, Mat);
            end loop;
         end;
      end loop;
      if Cap_Front >= 0.0 then
         declare
            A : constant Ring := R (S (S'First));
         begin
            for K in 1 .. 6 loop
               Tri (B, A (0), A (K), A (K + 1), Col, Cap_Front);
            end loop;
         end;
      end if;
      if Cap_Back >= 0.0 then
         declare
            A : constant Ring := R (S (S'Last));
         begin
            for K in 1 .. 6 loop
               Tri (B, A (0), A (K), A (K + 1), (if Cap_Back = Glow then (2.0, 0.5, 0.2) else Col),
                    Cap_Back);
            end loop;
         end;
      end if;
   end Loft;

   procedure Build_Body is
      B : Builder;
      Hull : constant Station_List :=
        ((-2.15, 0.5, 0.09), (-1.75, 0.78, 0.2), (-1.0, 0.86, 0.3), (0.3, 0.88, 0.34),
         (1.4, 0.84, 0.32), (1.95, 0.72, 0.24));
      Canopy : constant Station_List :=
        ((-1.0, 0.25, 0.30), (-0.6, 0.48, 0.5), (0.1, 0.52, 0.56), (0.7, 0.42, 0.46),
         (1.1, 0.25, 0.32));
   begin
      Loft (B, Hull, White, Paint, Cap_Front => Paint, Cap_Back => Metal);
      Loft (B, Canopy, Black, Glass);
      --  The black band round the middle and the lit stripe in it
      Box (B, (-0.9, -0.05, -1.6), (0.9, 0.05, 1.8), Dark, Metal);
      Box (B, (-0.915, -0.025, -1.4), (0.915, 0.025, 1.5), (1.4, 1.4, 1.4), Glow);
      --  Side pods between the wheels
      Box (B, (-1.02, -0.2, -0.65), (1.02, 0.2, 0.6), White, Paint);
      Box (B, (-1.04, -0.08, -0.55), (1.04, 0.08, 0.5), Dark, Metal);
      --  Arms to the wheels
      Box (B, (-1.0, -0.06, -1.42), (1.0, 0.06, -1.28), Steel, Metal);
      Box (B, (-1.0, -0.06, 1.24), (1.0, 0.06, 1.36), Steel, Metal);
      --  Wings above and below at the back
      for S in -1 .. 1 loop
         if S /= 0 then
            declare
               Y : constant Float := Float (S);
            begin
               Box (B, (-0.98, Y * 0.5 - 0.03, 1.7), (0.98, Y * 0.5 + 0.03, 2.15), White, Paint);
               Box (B, (-0.5, Y * 0.25, 1.85), (-0.42, Y * 0.5, 2.0), Dark, Metal);
               Box (B, (0.42, Y * 0.25, 1.85), (0.5, Y * 0.5, 2.0), Dark, Metal);
               Box (B, (-1.0, Y * 0.5 - 0.12, 1.65), (-0.94, Y * 0.5 + 0.12, 2.18), Dark, Metal);
               Box (B, (0.94, Y * 0.5 - 0.12, 1.65), (1.0, Y * 0.5 + 0.12, 2.18), Dark, Metal);
               --  intakes
               Box (B, (-0.3, Y * 0.33 - 0.04, -1.3), (0.3, Y * 0.33 + 0.04, -1.0), Black, Metal);
            end;
         end if;
      end loop;
      --  Exhausts, lit
      Box (B, (-0.55, -0.1, 1.94), (-0.25, 0.1, 2.0), (3.0, 0.9, 0.3), Glow);
      Box (B, (0.25, -0.1, 1.94), (0.55, 0.1, 2.0), (3.0, 0.9, 0.3), Glow);
      --  Headlamps
      Box (B, (-0.6, -0.05, -2.0), (-0.3, 0.05, -1.85), (2.5, 2.5, 2.2), Glow);
      Box (B, (0.3, -0.05, -2.0), (0.6, 0.05, -1.85), (2.5, 2.5, 2.2), Glow);
      Body_Mesh := Upload (B);
   end Build_Body;

   procedure Build_Wheel is
      B : Builder;
      N : constant := 20;
      R : constant Float := 0.62;
      W : constant Float := 0.27;
      Hub_R : constant Float := 0.36;
      function P (K : Integer; Rad, X : Float) return Vec3 is
         A : constant Float := 2.0 * Pi * Float (K) / Float (N);
      begin
         return (X, Rad * Cos (A), Rad * Sin (A));
      end P;
   begin
      for K in 0 .. N - 1 loop
         declare
            A0 : constant Float := 2.0 * Pi * Float (K) / Float (N);
            A1 : constant Float := 2.0 * Pi * Float (K + 1) / Float (N);
            N0 : constant Vec3 := (0.0, Cos (A0), Sin (A0));
            N1 : constant Vec3 := (0.0, Cos (A1), Sin (A1));
         begin
            --  The tread, smooth shaded, U round it
            Add (B, (P (K, R, -W), N0, 0.05, 0.05, 0.05, Tyre, A0, 0.0));
            Add (B, (P (K + 1, R, -W), N1, 0.05, 0.05, 0.05, Tyre, A1, 0.0));
            Add (B, (P (K + 1, R, W), N1, 0.05, 0.05, 0.05, Tyre, A1, 1.0));
            Add (B, (P (K, R, -W), N0, 0.05, 0.05, 0.05, Tyre, A0, 0.0));
            Add (B, (P (K + 1, R, W), N1, 0.05, 0.05, 0.05, Tyre, A1, 1.0));
            Add (B, (P (K, R, W), N0, 0.05, 0.05, 0.05, Tyre, A0, 1.0));
         end;
         for S in -1 .. 1 loop
            if S /= 0 then
               declare
                  X : constant Float := Float (S) * W;
               begin
                  --  sidewall, then the rim a little inside it
                  Quad (B, P (K, R, X), P (K + 1, R, X), P (K + 1, Hub_R, X * 0.92),
                        P (K, Hub_R, X * 0.92), Black);
                  Tri (B, (X * 1.05, 0.0, 0.0), P (K, Hub_R, X * 0.92), P (K + 1, Hub_R, X * 0.92),
                       Steel, Metal);
               end;
            end if;
         end loop;
      end loop;
      --  spokes, so the turning shows
      for K in 0 .. 4 loop
         declare
            A : constant Float := 2.0 * Pi * Float (K) / 5.0;
            D : constant Vec3 := (0.0, Cos (A), Sin (A));
            Q : constant Vec3 := (0.0, -Sin (A), Cos (A));
         begin
            for S in -1 .. 1 loop
               if S /= 0 then
                  declare
                     X : constant Vec3 := (Float (S) * W * 1.02, 0.0, 0.0);
                  begin
                     Quad (B, X + 0.08 * Q, X + 0.08 * Q + 0.5 * D, X - 0.08 * Q + 0.5 * D,
                           X - 0.08 * Q, Dark, Metal);
                  end;
               end if;
            end loop;
         end;
      end loop;
      Wheel_Mesh := Upload (B);
   end Build_Wheel;

   procedure Build_Small is
      B : Builder;
      S : constant Float := 0.85;
      Top : constant Vec3 := (0.0, S, 0.0);
      Bot : constant Vec3 := (0.0, -S, 0.0);
      Ring : constant array (0 .. 3) of Vec3 := ((S, 0.0, 0.0), (0.0, 0.0, S), (-S, 0.0, 0.0), (0.0, 0.0, -S));
      Gold : constant Color := (2.2, 1.6, 0.35);
   begin
      --  The pod: a lit diamond in a frame
      for K in 0 .. 3 loop
         Tri (B, Top, Ring (K), Ring ((K + 1) mod 4), Gold, Glow);
         Tri (B, Bot, Ring ((K + 1) mod 4), Ring (K), (1.4, 0.9, 0.2), Glow);
      end loop;
      Prism (B, (0.0, -1.25, 0.0), 1.05, 1.05, 0.12, 12, (0.2, 0.2, 0.22), Metal);
      Prism (B, (0.0, 1.13, 0.0), 1.05, 1.05, 0.12, 12, (0.2, 0.2, 0.22), Metal);
      Pod_Mesh := Upload (B);

      --  The rocket, nose to -Z
      Box (B, (-0.14, -0.14, -0.5), (0.14, 0.14, 0.5), Steel, Metal);
      Box (B, (-0.1, -0.1, -0.75), (0.1, 0.1, -0.5), (3.0, 0.4, 0.2), Glow);
      Box (B, (-0.35, -0.02, 0.3), (0.35, 0.02, 0.5), Dark, Metal);
      Box (B, (-0.02, -0.35, 0.3), (0.02, 0.35, 0.5), Dark, Metal);
      Rocket_Mesh := Upload (B);

      --  The mine, lying on its surface (Y up from it)
      Prism (B, (0.0, 0.0, 0.0), 0.7, 0.55, 0.18, 10, (0.12, 0.12, 0.13), Metal);
      Prism (B, (0.0, 0.18, 0.0), 0.2, 0.15, 0.08, 8, (3.0, 0.3, 0.2), Glow);
      for K in 0 .. 5 loop
         declare
            A : constant Float := 2.0 * Pi * Float (K) / 6.0;
         begin
            Prism (B, (0.62 * Cos (A), 0.0, 0.62 * Sin (A)), 0.08, 0.0, 0.32, 4, Steel, Metal);
         end;
      end loop;
      Mine_Mesh := Upload (B);

      --  The shield: a sphere, drawn adding light
      declare
         NA : constant := 16;
         NB : constant := 10;
         R : constant Float := 2.7;
         function SP (I, J : Integer) return Vec3 is
            Th : constant Float := Pi * Float (J) / Float (NB);
            Ph : constant Float := 2.0 * Pi * Float (I) / Float (NA);
         begin
            return (R * Sin (Th) * Cos (Ph), 0.75 * R * Cos (Th), 1.25 * R * Sin (Th) * Sin (Ph));
         end SP;
      begin
         for I in 0 .. NA - 1 loop
            for J in 0 .. NB - 1 loop
               Quad (B, SP (I, J), SP (I + 1, J), SP (I + 1, J + 1), SP (I, J + 1),
                     (0.15, 0.45, 0.6), Glow);
            end loop;
         end loop;
      end;
      Shield_Mesh := Upload (B);
   end Build_Small;

   procedure Build is
   begin
      Build_Body;
      Build_Wheel;
      Build_Small;
   end Build;

end Car_Model;
