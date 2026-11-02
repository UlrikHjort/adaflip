--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Car_Model;
with Math3D; use Math3D;

package body Scenery is

   use Ada.Numerics.Elementary_Functions;
   use Mesh;

   Pi : constant := Ada.Numerics.Pi;

   function Look_Of (T : Track.Theme_Kind) return Look is
   begin
      case T is
         when Track.Desert =>
            return (Wall => (0.62, 0.6, 0.58), Concrete => (0.55, 0.5, 0.45),
                    Road => (0.11, 0.105, 0.1), Stripe => (2.0, 0.7, 0.15),
                    Ground_1 => (0.72, 0.42, 0.24), Ground_2 => (0.55, 0.3, 0.16),
                    Sun_Dir => (0.45, 0.55, 0.3), Sun => (2.1, 1.9, 1.6),
                    Sky_Amb => (0.28, 0.33, 0.45), Ground_Amb => (0.22, 0.15, 0.1),
                    Zenith => (0.18, 0.36, 0.72), Horizon => (0.85, 0.72, 0.58),
                    Fog => (0.8, 0.7, 0.58), Fog_Density => 0.00045, Night => 0.0);
         when Track.City =>
            return (Wall => (0.22, 0.24, 0.3), Concrete => (0.2, 0.2, 0.24),
                    Road => (0.06, 0.06, 0.07), Stripe => (0.2, 1.4, 2.4),
                    Ground_1 => (0.06, 0.06, 0.07), Ground_2 => (0.1, 0.09, 0.1),
                    Sun_Dir => (-0.3, 0.5, 0.4), Sun => (0.35, 0.4, 0.6),
                    Sky_Amb => (0.08, 0.09, 0.16), Ground_Amb => (0.06, 0.04, 0.06),
                    Zenith => (0.01, 0.012, 0.035), Horizon => (0.12, 0.07, 0.16),
                    Fog => (0.07, 0.05, 0.1), Fog_Density => 0.0011, Night => 1.0);
         when Track.Ice =>
            return (Wall => (0.55, 0.62, 0.7), Concrete => (0.5, 0.55, 0.6),
                    Road => (0.12, 0.13, 0.15), Stripe => (0.4, 2.2, 0.9),
                    Ground_1 => (0.85, 0.88, 0.95), Ground_2 => (0.65, 0.72, 0.85),
                    Sun_Dir => (-0.7, 0.18, 0.45), Sun => (1.9, 1.15, 0.8),
                    Sky_Amb => (0.3, 0.35, 0.55), Ground_Amb => (0.35, 0.35, 0.45),
                    Zenith => (0.12, 0.16, 0.4), Horizon => (0.95, 0.62, 0.5),
                    Fog => (0.75, 0.62, 0.62), Fog_Density => 0.0006, Night => 0.3);
      end case;
   end Look_Of;

   type UV is record
      U, V : Float;
   end record;

   procedure Quad_UV (B : in out Builder; P1, P2, P3, P4 : Vec3; T1, T2, T3, T4 : UV;
                      Col : Color; Mat : Float) is
      N : Vec3 := Cross (P2 - P1, P3 - P1);
   begin
      if Length (N) < 1.0E-9 then
         N := Cross (P3 - P1, P4 - P1);
         if Length (N) < 1.0E-9 then
            return;
         end if;
      end if;
      N := Normalize (N);
      Add (B, (P1, N, Col.R, Col.G, Col.B, Mat, T1.U, T1.V));
      Add (B, (P2, N, Col.R, Col.G, Col.B, Mat, T2.U, T2.V));
      Add (B, (P3, N, Col.R, Col.G, Col.B, Mat, T3.U, T3.V));
      Add (B, (P1, N, Col.R, Col.G, Col.B, Mat, T1.U, T1.V));
      Add (B, (P3, N, Col.R, Col.G, Col.B, Mat, T3.U, T3.V));
      Add (B, (P4, N, Col.R, Col.G, Col.B, Mat, T4.U, T4.V));
   end Quad_UV;

   ---------------------------------------------------------------------------
   --  The cross-section as a ring of points
   ---------------------------------------------------------------------------

   Ring_Last : constant := 60;
   type Ring_Point is record
      X, Y, Perim : Float;
   end record;
   type Ring is array (0 .. Ring_Last) of Ring_Point;

   function Hidden_Open (K : Natural) return Boolean is (K in 18 .. 41);
   --  The segments of the roof, not built in the open

   function Make_Ring (P : Track.Profile; Closed : Boolean; Grow : Float := 0.0) return Ring is
      W2 : constant Float := P.Width / 2.0 + Grow;
      H  : constant Float := P.Height + 2.0 * Grow;
      RB : constant Float := P.R_Bottom + Grow;
      RT : constant Float := P.R_Top + Grow;
      FX : constant Float := W2 - RB;
      Top : constant Float := (if Closed then H - RT else Float'Max (P.Wall_Height + Grow, RB));
      R : Ring;
      N : Natural := 0;
      procedure Put (X, Y : Float) is
      begin
         R (N) := (X, Y - Grow, 0.0);
         N := N + 1;
      end Put;
   begin
      for K in 0 .. 3 loop
         Put (FX * Float (K) / 4.0, 0.0);
      end loop;
      for K in 0 .. 7 loop
         declare
            A : constant Float := -Pi / 2.0 + Pi / 2.0 * Float (K) / 8.0;
         begin
            Put (FX + RB * Cos (A), RB + RB * Sin (A));
         end;
      end loop;
      for K in 0 .. 5 loop
         Put (W2, RB + (Top - RB) * Float (K) / 6.0);
      end loop;
      for K in 0 .. 7 loop
         declare
            A : constant Float := Pi / 2.0 * Float (K) / 8.0;
         begin
            if Closed then
               Put (W2 - RT + RT * Cos (A), H - RT + RT * Sin (A));
            else
               Put (W2, Top);
            end if;
         end;
      end loop;
      for K in 0 .. 7 loop
         if Closed then
            Put ((W2 - RT) - 2.0 * (W2 - RT) * Float (K) / 8.0, H);
         else
            Put (W2 - 2.0 * W2 * Float (K) / 8.0, Top);
         end if;
      end loop;
      for K in 0 .. 7 loop
         declare
            A : constant Float := Pi / 2.0 + Pi / 2.0 * Float (K) / 8.0;
         begin
            if Closed then
               Put (-(W2 - RT) + RT * Cos (A), H - RT + RT * Sin (A));
            else
               Put (-W2, Top);
            end if;
         end;
      end loop;
      for K in 0 .. 5 loop
         Put (-W2, Top - (Top - RB) * Float (K) / 6.0);
      end loop;
      for K in 0 .. 7 loop
         declare
            A : constant Float := Pi + Pi / 2.0 * Float (K) / 8.0;
         begin
            Put (-FX + RB * Cos (A), RB + RB * Sin (A));
         end;
      end loop;
      for K in 0 .. 3 loop
         Put (-FX + FX * Float (K) / 4.0, 0.0);
      end loop;
      Put (0.0, 0.0);
      for K in 1 .. Ring_Last loop
         R (K).Perim := R (K - 1).Perim
           + Sqrt ((R (K).X - R (K - 1).X) ** 2 + (R (K).Y - R (K - 1).Y) ** 2);
      end loop;
      return R;
   end Make_Ring;

   function World_Of (S : Track.Sample; X, Y : Float) return Vec3 is
     (S.C + X * S.B + Y * S.N);

   ---------------------------------------------------------------------------

   type Seed_Type is mod 2**32;
   Seed : Seed_Type := 1;

   function Rand return Float is
   begin
      Seed := Seed * 1664525 + 1013904223;
      return Float (Seed / 256) / Float (2**24);
   end Rand;

   function Between (A, B : Float) return Float is (A + (B - A) * Rand);

   procedure Build_Track (B : in out Builder; L : Look) is
      N : constant Positive := Track.Count;
      St : constant Float := Track.Step;
      Glow_Col : constant Color := (L.Stripe.R * 1.6, L.Stripe.G * 1.6, L.Stripe.B * 1.6);
   begin
      for I in 0 .. N - 1 loop
         declare
            SA : constant Track.Sample := Track.Get (I);
            SB : constant Track.Sample := Track.Get (I + 1);
            Closed : constant Boolean := SA.P.Roof > 0.5 and then SB.P.Roof > 0.5;
            RA : constant Ring := Make_Ring (SA.P, Closed);
            RB : constant Ring := Make_Ring (SB.P, Closed);
            UA : constant Float := Float (I) * St;
            UB : constant Float := Float (I + 1) * St;
            In_Mat : constant Float := (if Closed then Indoor else 0.0);
         begin
            --  The inside: the road and the walls (and the roof)
            for K in 0 .. Ring_Last - 1 loop
               if Closed or else not Hidden_Open (K) then
                  declare
                     DX : constant Float := RA (K + 1).X - RA (K).X;
                     DY : constant Float := RA (K + 1).Y - RA (K).Y;
                     Len : constant Float := Float'Max (1.0E-6, Sqrt (DX * DX + DY * DY));
                     Up_Facing : constant Boolean := DX / Len > 0.8;   --  inward normal (-DY, DX)
                     P1 : constant Vec3 := World_Of (SA, RA (K).X, RA (K).Y);
                     P2 : constant Vec3 := World_Of (SA, RA (K + 1).X, RA (K + 1).Y);
                     P3 : constant Vec3 := World_Of (SB, RB (K + 1).X, RB (K + 1).Y);
                     P4 : constant Vec3 := World_Of (SB, RB (K).X, RB (K).Y);
                  begin
                     if Len > 1.0E-4 or else RB (K + 1).X /= RB (K).X then
                        if Up_Facing then
                           declare
                              Half : constant Float := Float'Max (0.0, SA.P.Width / 2.0 - SA.P.R_Bottom);
                           begin
                              Quad_UV (B, P1, P2, P3, P4,
                                       (UA, RA (K).X), (UA, RA (K + 1).X), (UB, RB (K + 1).X), (UB, RB (K).X),
                                       (Half, 0.0, 0.0), Road + In_Mat);
                           end;
                        else
                           Quad_UV (B, P1, P2, P3, P4,
                                    (UA, RA (K).Perim), (UA, RA (K + 1).Perim),
                                    (UB, RB (K + 1).Perim), (UB, RB (K).Perim),
                                    L.Wall, Wall + In_Mat);
                        end if;
                     end if;
                  end;
               end if;
            end loop;

            --  The outside
            if Closed then
               declare
                  OA : constant Ring := Make_Ring (SA.P, True, 0.8);
                  OB : constant Ring := Make_Ring (SB.P, True, 0.8);
               begin
                  for K in 0 .. Ring_Last - 1 loop
                     Quad_UV (B, World_Of (SA, OA (K).X, OA (K).Y), World_Of (SA, OA (K + 1).X, OA (K + 1).Y),
                              World_Of (SB, OB (K + 1).X, OB (K + 1).Y), World_Of (SB, OB (K).X, OB (K).Y),
                              (UA, OA (K).Perim), (UA, OA (K + 1).Perim),
                              (UB, OB (K + 1).Perim), (UB, OB (K).Perim), L.Concrete, Concrete);
                  end loop;
               end;
            else
               declare
                  type Line is array (0 .. 5) of UV;
                  function Outline (S : Track.Sample) return Line is
                     W2 : constant Float := S.P.Width / 2.0;
                     Top : constant Float := Float'Max (S.P.Wall_Height, S.P.R_Bottom);
                  begin
                     return ((W2, Top), (W2 + 0.6, Top), (W2 + 0.6, -0.8),
                             (-W2 - 0.6, -0.8), (-W2 - 0.6, Top), (-W2, Top));
                  end Outline;
                  OA : constant Line := Outline (SA);
                  OB : constant Line := Outline (SB);
               begin
                  for K in 0 .. 4 loop
                     Quad_UV (B, World_Of (SA, OA (K).U, OA (K).V), World_Of (SA, OA (K + 1).U, OA (K + 1).V),
                              World_Of (SB, OB (K + 1).U, OB (K + 1).V), World_Of (SB, OB (K).U, OB (K).V),
                              (UA, 0.0), (UA, 3.0), (UB, 3.0), (UB, 0.0), L.Concrete, Concrete);
                  end loop;
                  --  A lit line along the top of each wall
                  for Sgn in -1 .. 1 loop
                     if Sgn /= 0 then
                        declare
                           XA : constant Float := Float (Sgn) * (SA.P.Width / 2.0 - 0.03);
                           XB : constant Float := Float (Sgn) * (SB.P.Width / 2.0 - 0.03);
                           TA : constant Float := OA (0).V;
                           TB : constant Float := OB (0).V;
                        begin
                           Quad_UV (B, World_Of (SA, XA, TA - 0.28), World_Of (SA, XA, TA - 0.12),
                                    World_Of (SB, XB, TB - 0.12), World_Of (SB, XB, TB - 0.28),
                                    (0.0, 0.0), (0.0, 0.0), (0.0, 0.0), (0.0, 0.0), Glow_Col, Glow);
                        end;
                     end if;
                  end loop;
                  --  Arrows on the outside of a tight bend
                  if abs SA.Curve > 1.0 / 110.0 and then I mod 3 = 0 then
                     declare
                        Sgn : constant Float := (if SA.Curve > 0.0 then -1.0 else 1.0);
                        SC : constant Track.Sample := Track.Get (I + 2);
                        XA : constant Float := Sgn * (SA.P.Width / 2.0 - 0.05);
                        XC : constant Float := Sgn * (SC.P.Width / 2.0 - 0.05);
                        TA : constant Float := OA (0).V;
                        TC : constant Float := Float'Max (SC.P.Wall_Height, SC.P.R_Bottom);
                     begin
                        Quad_UV (B, World_Of (SA, XA, TA), World_Of (SC, XC, TC),
                                 World_Of (SC, XC, TC + 1.5), World_Of (SA, XA, TA + 1.5),
                                 (0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0),
                                 (-Sgn * 1.2, 0.0, 0.0), Chevron);
                     end;
                  end if;
               end;
            end if;

            --  Lights in the tunnels: lamps in the roof, a lit line along each wall
            if Closed then
               if I mod 5 = 0 then
                  Oriented_Box (B, SA.C + (SA.P.Height - 0.05) * SA.N, SA.T, SA.N, 1.6, 0.06, 0.5,
                                (3.0, 2.8, 2.4), Glow);
               end if;
               for Sgn in -1 .. 1 loop
                  if Sgn /= 0 then
                     declare
                        XA : constant Float := Float (Sgn) * (SA.P.Width / 2.0 - 0.02);
                        XB : constant Float := Float (Sgn) * (SB.P.Width / 2.0 - 0.02);
                        YA : constant Float := Float'Max (SA.P.R_Bottom, 1.2) + 0.4;
                        YB : constant Float := Float'Max (SB.P.R_Bottom, 1.2) + 0.4;
                     begin
                        if SA.P.R_Bottom + SA.P.R_Top < SA.P.Height - 0.5 then
                           Quad_UV (B, World_Of (SA, XA, YA), World_Of (SA, XA, YA + 0.18),
                                    World_Of (SB, XB, YB + 0.18), World_Of (SB, XB, YB),
                                    (0.0, 0.0), (0.0, 0.0), (0.0, 0.0), (0.0, 0.0), Glow_Col, Glow);
                        end if;
                     end;
                  end if;
               end loop;
            end if;

            --  The face of a tunnel where its roof begins or ends
            if (SA.P.Roof > 0.5) /= (SB.P.Roof > 0.5) then
               declare
                  S : constant Track.Sample := (if SA.P.Roof > 0.5 then SA else SB);
                  R : constant Ring := Make_Ring (S.P, True);
                  CY : constant Float := S.P.Height / 2.0;
                  EX : constant Float := S.P.Width / 2.0 + 2.5;
                  Top : constant Float := S.P.Height + 2.0;
                  type Pts is array (0 .. Ring_Last) of UV;
                  O, G : Pts;
               begin
                  for K in 0 .. Ring_Last loop
                     declare
                        DX : constant Float := R (K).X;
                        DY : constant Float := R (K).Y - CY;
                        T : Float := Float'Last;
                     begin
                        if abs DX > 1.0E-4 then
                           T := Float'Min (T, EX / abs DX);
                        end if;
                        if DY > 1.0E-4 then
                           T := Float'Min (T, (Top - CY) / DY);
                        elsif DY < -1.0E-4 then
                           T := Float'Min (T, (-0.8 - CY) / DY);
                        end if;
                        O (K) := (DX * T, CY + DY * T);
                        declare
                           LX : constant Float := O (K).U - R (K).X;
                           LY : constant Float := O (K).V - R (K).Y;
                           LL : constant Float := Float'Max (1.0E-4, Sqrt (LX * LX + LY * LY));
                        begin
                           G (K) := (R (K).X + 0.4 * LX / LL, R (K).Y + 0.4 * LY / LL);
                        end;
                     end;
                  end loop;
                  for K in 0 .. Ring_Last - 1 loop
                     Quad_UV (B, World_Of (S, G (K).U, G (K).V), World_Of (S, G (K + 1).U, G (K + 1).V),
                              World_Of (S, O (K + 1).U, O (K + 1).V), World_Of (S, O (K).U, O (K).V),
                              (0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), L.Concrete, Concrete);
                     Quad_UV (B, World_Of (S, R (K).X, R (K).Y), World_Of (S, R (K + 1).X, R (K + 1).Y),
                              World_Of (S, G (K + 1).U, G (K + 1).V), World_Of (S, G (K).U, G (K).V),
                              (0.0, 0.0), (0.0, 0.0), (0.0, 0.0), (0.0, 0.0), Glow_Col, Glow);
                  end loop;
               end;
            end if;

            --  Pillars under the high parts
            if I mod 20 = 0 and then SA.C.Y > 2.6 then
               for Sgn in -1 .. 1 loop
                  if Sgn /= 0 then
                     declare
                        P : constant Vec3 := SA.C + (Float (Sgn) * SA.P.Width / 4.0) * SA.B;
                     begin
                        Car_Model.Prism (B, (P.X, 0.0, P.Z), 1.0, 0.8, P.Y - 0.6, 6, L.Concrete, Concrete);
                     end;
                  end if;
               end loop;
            end if;
         end;
      end loop;

      --  The start: squares across the road and a gantry over it
      declare
         S : constant Track.Sample := Track.Get (0);
         Half : constant Float := S.P.Width / 2.0 - S.P.R_Bottom;
         W2 : constant Float := S.P.Width / 2.0;
      begin
         Quad_UV (B, S.C + (-Half) * S.B + 0.03 * S.N, S.C + Half * S.B + 0.03 * S.N,
                  S.C + Half * S.B + 0.03 * S.N + 3.0 * S.T, S.C + (-Half) * S.B + 0.03 * S.N + 3.0 * S.T,
                  (0.0, 0.0), (2.0 * Half, 0.0), (2.0 * Half, 3.0), (0.0, 3.0), (1.0, 1.0, 1.0), Checker);
         for Sgn in -1 .. 1 loop
            if Sgn /= 0 then
               Oriented_Box (B, S.C + (Float (Sgn) * (W2 + 1.2)) * S.B + 5.0 * S.N, S.T, S.N,
                             0.5, 5.8, 0.5, (0.3, 0.3, 0.33), Metal);
            end if;
         end loop;
         Oriented_Box (B, S.C + 10.0 * S.N, S.T, S.N, 0.6, 0.8, W2 + 1.7, (0.3, 0.3, 0.33), Metal);
         Oriented_Box (B, S.C + 10.0 * S.N - 0.62 * S.T, S.T, S.N, 0.02, 0.35, W2 + 1.5, Glow_Col, Glow);
         Oriented_Box (B, S.C + 10.0 * S.N + 0.62 * S.T, S.T, S.N, 0.02, 0.35, W2 + 1.5, Glow_Col, Glow);
      end;
   end Build_Track;

   ---------------------------------------------------------------------------
   --  Round the track
   ---------------------------------------------------------------------------

   Min_X, Max_X, Min_Z, Max_Z : Float := 0.0;

   function Clear (X, Z, R : Float) return Boolean is
   begin
      for I in 0 .. Track.Count - 1 loop
         if I mod 2 = 0 then
            declare
               S : constant Track.Sample := Track.Get (I);
               DX : constant Float := S.C.X - X;
               DZ : constant Float := S.C.Z - Z;
               Need : constant Float := S.P.Width / 2.0 + R + 12.0;
            begin
               if DX * DX + DZ * DZ < Need * Need then
                  return False;
               end if;
            end;
         end if;
      end loop;
      return True;
   end Clear;

   procedure Tower (B : in out Builder; X, Z, W, D, H : Float; Col, Roof : Color) is
      P : constant array (0 .. 4) of Vec3 :=
        ((X - W, 0.0, Z - D), (X + W, 0.0, Z - D), (X + W, 0.0, Z + D), (X - W, 0.0, Z + D),
         (X - W, 0.0, Z - D));
      Up : constant Vec3 := (0.0, H, 0.0);
   begin
      for K in 0 .. 3 loop
         declare
            Len : constant Float := Length (P (K + 1) - P (K));
         begin
            Quad_UV (B, P (K), P (K + 1), P (K + 1) + Up, P (K) + Up,
                     (0.0, 0.0), (Len, 0.0), (Len, H), (0.0, H), Col, Building);
         end;
      end loop;
      Quad_UV (B, P (0) + Up, P (1) + Up, P (2) + Up, P (3) + Up,
               (0.0, 0.0), (2.0 * W, 0.0), (2.0 * W, 2.0 * D), (0.0, 2.0 * D), Roof, Concrete);
   end Tower;

   procedure Build_Surroundings (B : in out Builder; L : Look) is
      Th : constant Track.Theme_Kind := Track.Theme (Track.Current);
      CX : constant Float := (Min_X + Max_X) / 2.0;
      CZ : constant Float := (Min_Z + Max_Z) / 2.0;
      Margin : constant := 450.0;

      procedure Spot (R : Float; X, Z : out Float; Ok : out Boolean) is
      begin
         Ok := False;
         X := 0.0;
         Z := 0.0;
         for Tries in 1 .. 12 loop
            X := Between (Min_X - Margin, Max_X + Margin);
            Z := Between (Min_Z - Margin, Max_Z + Margin);
            if Clear (X, Z, R) then
               Ok := True;
               return;
            end if;
         end loop;
      end Spot;
   begin
      --  The ground, far and wide
      declare
         E : constant Float := 4000.0;
      begin
         Quad_UV (B, (CX - E, 0.0, CZ - E), (CX + E, 0.0, CZ - E), (CX + E, 0.0, CZ + E), (CX - E, 0.0, CZ + E),
                  (0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0), L.Ground_1, Ground);
      end;

      case Th is
         when Track.Desert =>
            for K in 1 .. 45 loop
               declare
                  R : constant Float := Between (14.0, 45.0);
                  H : constant Float := Between (25.0, 85.0);
                  X, Z : Float;
                  Ok : Boolean;
               begin
                  Spot (R, X, Z, Ok);
                  if Ok then
                     Car_Model.Prism (B, (X, -1.0, Z), R, R * 0.8, H, 9, (0.62, 0.3, 0.17), Rock, Rand * 3.0);
                     Car_Model.Prism (B, (X, H - 1.0, Z), R * 0.8, R * 0.7, 4.0, 9, (0.7, 0.42, 0.25), Rock);
                  end if;
               end;
            end loop;
            for K in 1 .. 260 loop
               declare
                  R : constant Float := Between (0.8, 5.0);
                  X, Z : Float;
                  Ok : Boolean;
               begin
                  Spot (R, X, Z, Ok);
                  if Ok then
                     Car_Model.Prism (B, (X, -0.3, Z), R, R * 0.55, R * Between (0.7, 1.5), 6,
                                      (0.55, 0.3, 0.18), Rock, Rand * 3.0);
                  end if;
               end;
            end loop;
         when Track.City =>
            for K in 1 .. 220 loop
               declare
                  W : constant Float := Between (7.0, 20.0);
                  D : constant Float := Between (7.0, 20.0);
                  H : constant Float := Between (15.0, 30.0) * (if Rand < 0.25 then 4.0 else 1.5);
                  X, Z : Float;
                  Ok : Boolean;
                  Shade : constant Float := Between (0.12, 0.3);
               begin
                  Spot (Float'Max (W, D) * 1.42, X, Z, Ok);
                  if Ok then
                     Tower (B, X, Z, W, D, H, (Shade, Shade * 1.05, Shade * 1.2), (0.15, 0.15, 0.17));
                     if H > 60.0 then
                        Box (B, (X - 0.4, H, Z - 0.4), (X + 0.4, H + 6.0, Z + 0.4), (0.3, 0.3, 0.3), Metal);
                        Box (B, (X - 0.5, H + 6.0, Z - 0.5), (X + 0.5, H + 7.0, Z + 0.5), (4.0, 0.3, 0.2), Glow);
                     end if;
                  end if;
               end;
            end loop;
            --  Light along the roads between them
            for K in 1 .. 160 loop
               declare
                  X, Z : Float;
                  Ok : Boolean;
               begin
                  Spot (2.0, X, Z, Ok);
                  if Ok then
                     Box (B, (X - 0.15, 0.0, Z - 0.15), (X + 0.15, 8.0, Z + 0.15), (0.2, 0.2, 0.2), Metal);
                     Box (B, (X - 0.5, 8.0, Z - 0.3), (X + 0.5, 8.3, Z + 0.3), (3.0, 2.0, 1.1), Glow);
                  end if;
               end;
            end loop;
         when Track.Ice =>
            for K in 1 .. 70 loop
               declare
                  R : constant Float := Between (6.0, 22.0);
                  H : constant Float := Between (30.0, 110.0);
                  X, Z : Float;
                  Ok : Boolean;
               begin
                  Spot (R, X, Z, Ok);
                  if Ok then
                     Car_Model.Prism (B, (X, -1.0, Z), R, 0.0, H, 6, (0.6, 0.75, 0.92), Rock, Rand * 3.0);
                  end if;
               end;
            end loop;
            for K in 1 .. 180 loop
               declare
                  R : constant Float := Between (1.0, 6.0);
                  X, Z : Float;
                  Ok : Boolean;
               begin
                  Spot (R, X, Z, Ok);
                  if Ok then
                     Car_Model.Prism (B, (X, -0.5, Z), R, R * 0.5, R * Between (0.6, 1.4), 5,
                                      (0.78, 0.85, 0.95), Rock, Rand * 3.0);
                  end if;
               end;
            end loop;
      end case;

      --  Mountains (or towers) on the horizon
      for K in 0 .. 39 loop
         declare
            A : constant Float := 2.0 * Pi * (Float (K) + Rand * 0.6) / 40.0;
            D : constant Float := Between (2300.0, 3000.0);
            X : constant Float := CX + D * Cos (A);
            Z : constant Float := CZ + D * Sin (A);
         begin
            case Th is
               when Track.Desert =>
                  Car_Model.Prism (B, (X, -5.0, Z), Between (250.0, 550.0), Between (20.0, 80.0),
                                   Between (150.0, 380.0), 7, (0.55, 0.32, 0.22), Rock, Rand * 3.0);
               when Track.Ice =>
                  Car_Model.Prism (B, (X, -5.0, Z), Between (250.0, 550.0), 0.0,
                                   Between (250.0, 600.0), 7, (0.8, 0.85, 0.95), Rock, Rand * 3.0);
               when Track.City =>
                  Tower (B, X, Z, Between (20.0, 50.0), Between (20.0, 50.0), Between (80.0, 320.0),
                         (0.08, 0.08, 0.1), (0.1, 0.1, 0.1));
            end case;
         end;
      end loop;
   end Build_Surroundings;

   procedure Build (World : out Mesh.GPU) is
      B : Builder;
      L : constant Look := Look_Of (Track.Theme (Track.Current));
   begin
      Seed := Seed_Type (Track.Current) * 7919 + 17;
      Min_X := Float'Last;
      Max_X := Float'First;
      Min_Z := Float'Last;
      Max_Z := Float'First;
      for I in 0 .. Track.Count - 1 loop
         declare
            C : constant Vec3 := Track.Get (I).C;
         begin
            Min_X := Float'Min (Min_X, C.X);
            Max_X := Float'Max (Max_X, C.X);
            Min_Z := Float'Min (Min_Z, C.Z);
            Max_Z := Float'Max (Max_Z, C.Z);
         end;
      end loop;
      Build_Track (B, L);
      Build_Surroundings (B, L);
      World := Upload (B);
   end Build;

end Scenery;
