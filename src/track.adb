--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions;

package body Track is

   use Ada.Numerics.Elementary_Functions;

   ---------------------------------------------------------------------------
   --  The circuits as control points: the spline runs through them, and the
   --  section from one point to the next is of the first one's kind
   ---------------------------------------------------------------------------

   type Point is record
      X, Z, Y : Float;
      K : Section_Kind;
   end record;

   type Point_List is array (Positive range <>) of Point;

   Red_Mesa : constant Point_List :=
     ((0.0, 0.0, 2.0, Open),
      (150.0, 0.0, 2.0, Open),
      (300.0, -20.0, 4.0, Open),
      (420.0, 40.0, 9.0, Halfpipe),
      (470.0, 170.0, 12.0, Halfpipe),
      (430.0, 300.0, 8.0, Open),
      (330.0, 360.0, 3.0, Tunnel),
      (190.0, 380.0, 3.0, Tunnel),
      (60.0, 360.0, 6.0, Open),
      (-40.0, 300.0, 17.0, Open),
      (-90.0, 220.0, 5.0, Wide),
      (-120.0, 120.0, 3.0, Pipe),
      (-110.0, 40.0, 3.0, Open),
      (-70.0, 5.0, 2.0, Open));

   Harbour : constant Point_List :=
     ((0.0, 0.0, 2.0, Open),
      (180.0, 0.0, 2.0, Open),
      (300.0, 30.0, 2.0, Tunnel),
      (360.0, 130.0, 2.0, Tunnel),
      (330.0, 240.0, 7.0, Open),
      (230.0, 300.0, 14.0, Wide),
      (100.0, 310.0, 14.0, Wide),
      (-20.0, 270.0, 8.0, Halfpipe),
      (-90.0, 180.0, 3.0, Halfpipe),
      (-110.0, 80.0, 3.0, Pipe),
      (-90.0, -10.0, 3.0, Pipe),
      (-50.0, -40.0, 2.0, Open));

   Frostline : constant Point_List :=
     ((0.0, 0.0, 3.0, Open),
      (170.0, 0.0, 3.0, Open),
      (290.0, -50.0, 6.0, Halfpipe),
      (380.0, -150.0, 10.0, Halfpipe),
      (480.0, -160.0, 10.0, Open),
      (560.0, -80.0, 4.0, Tunnel),
      (560.0, 40.0, 4.0, Tunnel),
      (480.0, 130.0, 4.0, Pipe),
      (360.0, 160.0, 4.0, Open),
      (240.0, 140.0, 16.0, Open),
      (130.0, 180.0, 4.0, Wide),
      (20.0, 170.0, 3.0, Open),
      (-80.0, 110.0, 3.0, Tunnel),
      (-90.0, 30.0, 3.0, Open),
      (-60.0, -10.0, 3.0, Open));

   function Name (Id : Track_Id) return String is
     (case Id is
         when 1 => "Red Mesa Run",
         when 2 => "Harbour Lights",
         when 3 => "Frostline");

   function Theme (Id : Track_Id) return Theme_Kind is
     (case Id is
         when 1 => Desert,
         when 2 => City,
         when 3 => Ice);

   function Scale_Of (Id : Track_Id) return Float is
     (case Id is
         when 1 => 1.5,
         when 2 => 1.6,
         when 3 => 1.5);

   function Shape (K : Section_Kind) return Profile is
     (case K is
         when Open     => (18.0, 18.0, 3.0, 3.0, 4.0, 0.0),
         when Wide     => (26.0, 18.0, 3.0, 3.0, 3.5, 0.0),
         when Halfpipe => (22.0, 18.0, 8.0, 3.0, 9.5, 0.0),
         when Tunnel   => (18.0, 10.0, 4.0, 4.0, 10.0, 1.0),
         when Pipe     => (17.0, 17.0, 8.5, 8.5, 17.0, 1.0));

   ---------------------------------------------------------------------------

   Max_Samples : constant := 6000;
   Samples : array (0 .. Max_Samples - 1) of Sample;
   N_Samples : Positive := 1;
   Step_Len : Float := 2.0;
   Loaded : Track_Id := 1;
   The_Pods : Pod_List := (others => Zero);
   N_Pods : Natural := 0;

   function Current return Track_Id is (Loaded);
   function Grip return Float is (if Theme (Loaded) = Ice then 0.85 else 1.0);
   function Count return Positive is (N_Samples);
   function Step return Float is (Step_Len);
   function Length return Float is (Float (N_Samples) * Step_Len);
   function Pod_Count return Natural is (N_Pods);
   function Pods return Pod_List is (The_Pods);

   function Wrap (I : Integer) return Natural is
     (Natural (((I mod N_Samples) + N_Samples) mod N_Samples));

   function Get (I : Integer) return Sample is (Samples (Wrap (I)));

   function Mix (A, B : Profile; T : Float) return Profile is
     (A.Width + T * (B.Width - A.Width),
      A.Height + T * (B.Height - A.Height),
      A.R_Bottom + T * (B.R_Bottom - A.R_Bottom),
      A.R_Top + T * (B.R_Top - A.R_Top),
      A.Wall_Height + T * (B.Wall_Height - A.Wall_Height),
      A.Roof + T * (B.Roof - A.Roof));

   function At_S (S : Float) return Sample is
      F : constant Float := S / Step_Len;
      I : constant Integer := Integer (Float'Floor (F));
      T : constant Float := F - Float (I);
      A : constant Sample := Get (I);
      B : constant Sample := Get (I + 1);
      R : Sample := A;
   begin
      R.C := Lerp (A.C, B.C, T);
      R.T := Normalize (Lerp (A.T, B.T, T));
      R.N := Normalize (Lerp (A.N, B.N, T));
      R.B := Normalize (Cross (R.T, R.N));
      R.P := Mix (A.P, B.P, T);
      R.Curve := A.Curve + T * (B.Curve - A.Curve);
      R.Vmax := A.Vmax + T * (B.Vmax - A.Vmax);
      return R;
   end At_S;

   ---------------------------------------------------------------------------
   --  The cross-section as a distance field
   ---------------------------------------------------------------------------

   procedure Corner (P : Profile; X, Y : Float; QX, QY, R : out Float) is
      CY : constant Float := P.Height / 2.0;
   begin
      R := (if Y > CY then P.R_Top else P.R_Bottom);
      QX := abs X - (P.Width / 2.0 - R);
      QY := abs (Y - CY) - (CY - R);
   end Corner;

   function Profile_Distance (P : Profile; X, Y : Float) return Float is
      QX, QY, R : Float;
   begin
      Corner (P, X, Y, QX, QY, R);
      if QX > 0.0 and then QY > 0.0 then
         return R - Sqrt (QX * QX + QY * QY);
      else
         return R - Float'Max (QX, QY);
      end if;
   end Profile_Distance;

   procedure Profile_Normal (P : Profile; X, Y : Float; NX, NY : out Float) is
      QX, QY, R : Float;
      SX : constant Float := (if X >= 0.0 then 1.0 else -1.0);
      SY : constant Float := (if Y >= P.Height / 2.0 then 1.0 else -1.0);
   begin
      Corner (P, X, Y, QX, QY, R);
      if QX > 0.0 and then QY > 0.0 then
         declare
            L : constant Float := Sqrt (QX * QX + QY * QY);
         begin
            NX := -SX * QX / L;
            NY := -SY * QY / L;
         end;
      elsif QX > QY then
         NX := -SX;
         NY := 0.0;
      else
         NX := 0.0;
         NY := -SY;
      end if;
   end Profile_Normal;

   function Walk (P : Vec3; From : Natural; Found : out Boolean) return Natural is
      I : Natural := Wrap (From);
   begin
      Found := False;
      for Tries in 1 .. 300 loop
         declare
            Nx : constant Natural := Wrap (I + 1);
         begin
            if Dot (P - Samples (Nx).C, Samples (Nx).T) > 0.0 then
               I := Nx;
            elsif Dot (P - Samples (I).C, Samples (I).T) < 0.0 then
               I := Wrap (I - 1);
            else
               Found := True;
               exit;
            end if;
         end;
      end loop;
      return I;
   end Walk;

   function Nearest (P : Vec3) return Natural is
      Best : Float := Float'Last;
      I : Natural := 0;
   begin
      for J in 0 .. N_Samples - 1 loop
         declare
            D : constant Vec3 := P - Samples (J).C;
            Q : constant Float := Dot (D, D);
         begin
            if Q < Best then
               Best := Q;
               I := J;
            end if;
         end;
      end loop;
      return I;
   end Nearest;

   function Locate (P : Vec3; Hint : Natural) return Locus is
      Found : Boolean;
      I : Natural := Walk (P, Hint, Found);
      L : Locus;
   begin
      --  Far planes can hold the point between them too: when the answer is
      --  far from the point, or none was found, start again from the nearest
      if not Found or else Length (P - Samples (I).C) > 45.0 then
         I := Walk (P, Nearest (P), Found);
      end if;
      declare
         A : Sample renames Samples (I);
         B : Sample renames Samples (Wrap (I + 1));
         T : constant Float := Clamp (Dot (P - A.C, A.T) / Step_Len, 0.0, 1.0);
         D : Vec3;
      begin
         L.I := I;
         L.S := (Float (I) + T) * Step_Len;
         L.C := Lerp (A.C, B.C, T);
         L.T := Normalize (Lerp (A.T, B.T, T));
         L.N := Normalize (Lerp (A.N, B.N, T));
         L.B := Normalize (Cross (L.T, L.N));
         L.P := Mix (A.P, B.P, T);
         D := P - L.C;
         L.X := Dot (D, L.B);
         L.Y := Dot (D, L.N);
      end;
      return L;
   end Locate;

   procedure Surface (L : Locus; Inside : out Float; Normal : out Vec3) is
      NX, NY : Float;
   begin
      Inside := Profile_Distance (L.P, L.X, L.Y);
      Profile_Normal (L.P, L.X, L.Y, NX, NY);
      Normal := NX * L.B + NY * L.N;
   end Surface;

   function Floor_Height (P : Profile; X : Float) return Float is
      Lo : Float := -1.0;
      Hi : Float := P.Height / 2.0;
   begin
      --  Down the line at X until it meets the surface
      for K in 1 .. 30 loop
         declare
            M : constant Float := (Lo + Hi) / 2.0;
         begin
            if Profile_Distance (P, X, M) > 0.0 then
               Hi := M;
            else
               Lo := M;
            end if;
         end;
      end loop;
      return Hi;
   end Floor_Height;

   function Floor_Point (S, X : Float) return Vec3 is
      A : constant Sample := At_S (S);
      XC : constant Float := Clamp (X, -A.P.Width / 2.0 + 0.5, A.P.Width / 2.0 - 0.5);
   begin
      return A.C + XC * A.B + Floor_Height (A.P, XC) * A.N;
   end Floor_Point;

   function Floor_Half (S : Float) return Float is
      A : constant Sample := At_S (S);
   begin
      return Float'Max (0.0, A.P.Width / 2.0 - A.P.R_Bottom);
   end Floor_Half;

   function Round_Point (S, Angle : Float) return Vec3 is
      A : constant Sample := At_S (S);
      CY : constant Float := A.P.Height / 2.0;
      DX : constant Float := Sin (Angle);
      DY : constant Float := -Cos (Angle);
      Lo : Float := 0.0;
      Hi : Float := A.P.Width + A.P.Height;
   begin
      for K in 1 .. 30 loop
         declare
            M : constant Float := (Lo + Hi) / 2.0;
         begin
            if Profile_Distance (A.P, M * DX, CY + M * DY) > 0.0 then
               Lo := M;
            else
               Hi := M;
            end if;
         end;
      end loop;
      return A.C + (Lo * DX) * A.B + (CY + Lo * DY) * A.N;
   end Round_Point;

   function Angle_Of (L : Locus) return Float is
     (Arctan (L.X, -(L.Y - L.P.Height / 2.0)));

   ---------------------------------------------------------------------------
   --  Building a track
   ---------------------------------------------------------------------------

   procedure Load (Id : Track_Id) is
      Src : constant Point_List :=
        (case Id is
            when 1 => Red_Mesa,
            when 2 => Harbour,
            when 3 => Frostline);
      Sc : constant Float := Scale_Of (Id);
      K : constant Positive := Src'Length;

      function CP (I : Integer) return Vec3 is
         Q : constant Point := Src (Src'First + ((I mod K) + K) mod K);
      begin
         return (Q.X * Sc, Float'Max (1.0, Q.Y), -Q.Z * Sc);
      end CP;

      function Catmull (P0, P1, P2, P3 : Vec3; T : Float) return Vec3 is
         T2 : constant Float := T * T;
         T3 : constant Float := T2 * T;
      begin
         return 0.5 * ((2.0 * P1) + T * (P2 - P0)
                       + T2 * (2.0 * P0 - 5.0 * P1 + 4.0 * P2 - P3)
                       + T3 * (3.0 * P1 - P0 - 3.0 * P2 + P3));
      end Catmull;

      Per : constant := 64;
      Dense_N : constant Positive := K * Per;
      type Dense_Array is array (0 .. Dense_N) of Vec3;
      type Seg_Array is array (0 .. Dense_N) of Natural;
      type Len_Array is array (0 .. Dense_N) of Float;
      Dense : Dense_Array;
      Seg : Seg_Array;
      Acc : Len_Array;
      Total : Float := 0.0;
      Raw : array (0 .. Max_Samples - 1) of Profile;
      Bank : array (0 .. Max_Samples - 1) of Float;
      Tmp : array (0 .. Max_Samples - 1) of Float;
   begin
      Loaded := Id;
      for S in 0 .. K - 1 loop
         for J in 0 .. Per - 1 loop
            Dense (S * Per + J) := Catmull (CP (S - 1), CP (S), CP (S + 1), CP (S + 2),
                                            Float (J) / Float (Per));
            Seg (S * Per + J) := S;
         end loop;
      end loop;
      Dense (Dense_N) := Dense (0);
      Seg (Dense_N) := 0;
      Acc (0) := 0.0;
      for I in 1 .. Dense_N loop
         Total := Total + Length (Dense (I) - Dense (I - 1));
         Acc (I) := Total;
      end loop;

      N_Samples := Positive'Min (Max_Samples, Positive (Float'Rounding (Total / 2.0)));
      Step_Len := Total / Float (N_Samples);

      --  Even steps along the curve
      declare
         D : Natural := 0;
      begin
         for I in 0 .. N_Samples - 1 loop
            declare
               S : constant Float := Float (I) * Step_Len;
            begin
               while D < Dense_N - 1 and then Acc (D + 1) < S loop
                  D := D + 1;
               end loop;
               declare
                  T : constant Float :=
                    Clamp ((S - Acc (D)) / Float'Max (1.0E-6, Acc (D + 1) - Acc (D)), 0.0, 1.0);
               begin
                  Samples (I).C := Lerp (Dense (D), Dense (D + 1), T);
                  Samples (I).Kind := Src (Src'First + Seg (D)).K;
                  Raw (I) := Shape (Samples (I).Kind);
               end;
            end;
         end loop;
      end;

      --  Frames, first without banking, to find the curves
      for I in 0 .. N_Samples - 1 loop
         declare
            T : constant Vec3 := Normalize (Get (I + 1).C - Get (I - 1).C);
            N : constant Vec3 := Normalize (Up_Y - Dot (Up_Y, T) * T);
         begin
            Samples (I).T := T;
            Samples (I).N := N;
            Samples (I).B := Normalize (Cross (T, N));
         end;
      end loop;
      for I in 0 .. N_Samples - 1 loop
         Tmp (I) := Dot (Get (I + 1).T - Get (I - 1).T, Samples (I).B) / (2.0 * Step_Len);
      end loop;
      for I in 0 .. N_Samples - 1 loop
         declare
            Sum : Float := 0.0;
         begin
            for J in -4 .. 4 loop
               Sum := Sum + Tmp (Wrap (I + J));
            end loop;
            Samples (I).Curve := Sum / 9.0;
         end;
      end loop;

      --  Banked into the bends on the open road
      for I in 0 .. N_Samples - 1 loop
         Tmp (I) := Clamp (Samples (I).Curve * 14.0, -0.28, 0.28)
           * (case Samples (I).Kind is
                 when Open | Wide => 1.0,
                 when others => 0.3);
      end loop;
      for I in 0 .. N_Samples - 1 loop
         declare
            Sum : Float := 0.0;
         begin
            for J in -12 .. 12 loop
               Sum := Sum + Tmp (Wrap (I + J));
            end loop;
            Bank (I) := Sum / 25.0;
         end;
      end loop;
      for I in 0 .. N_Samples - 1 loop
         Samples (I).N := Rotate (Samples (I).N, Samples (I).T, Bank (I));
         Samples (I).B := Normalize (Cross (Samples (I).T, Samples (I).N));
      end loop;

      --  The cross-sections blend into each other; the roof begins sharply
      for I in 0 .. N_Samples - 1 loop
         declare
            Sum : Profile := (others => 0.0);
            W : constant := 12;
         begin
            for J in -W .. W loop
               declare
                  R : constant Profile := Raw (Wrap (I + J));
               begin
                  Sum := (Sum.Width + R.Width, Sum.Height + R.Height,
                          Sum.R_Bottom + R.R_Bottom, Sum.R_Top + R.R_Top,
                          Sum.Wall_Height + R.Wall_Height, 0.0);
               end;
            end loop;
            declare
               F : constant Float := 1.0 / Float (2 * W + 1);
               P : Profile := (Sum.Width * F, Sum.Height * F, Sum.R_Bottom * F, Sum.R_Top * F,
                               Sum.Wall_Height * F, Raw (I).Roof);
               Lim : constant Float := Float'Min (P.Width, P.Height) / 2.0;
            begin
               P.R_Bottom := Float'Min (P.R_Bottom, Lim);
               P.R_Top := Float'Min (P.R_Top, Lim);
               if P.Roof > 0.5 then
                  P.Wall_Height := P.Height;
               end if;
               Samples (I).P := P;
            end;
         end;
      end loop;

      --  How fast the AI may take each bend, and braking for it ahead
      for I in 0 .. N_Samples - 1 loop
         declare
            R : constant Float := 1.0 / Float'Max (abs Samples (I).Curve, 1.0E-4);
            Bonus : constant Float :=
              (case Samples (I).Kind is
                  when Halfpipe | Pipe => 1.25,
                  when Tunnel => 1.1,
                  when others => 1.0);
         begin
            Samples (I).Vmax := Float'Min (78.0, Sqrt (Grip * 2.1 * 9.81 * R) * Bonus);
         end;
      end loop;
      for Round in 1 .. 2 loop
         for I in reverse 0 .. N_Samples - 1 loop
            declare
               Next : constant Float := Get (I + 1).Vmax;
            begin
               Samples (I).Vmax := Float'Min (Samples (I).Vmax,
                                              Sqrt (Next * Next + 2.0 * 16.0 * Grip * Step_Len));
            end;
         end loop;
      end loop;

      --  Weapon pods: three across every so often
      N_Pods := 0;
      declare
         S : Float := 140.0;
      begin
         while S < Length - 80.0 and then N_Pods + 3 <= Max_Pods loop
            for J in -1 .. 1 loop
               declare
                  X : constant Float := Float (J) * Float'Min (4.5, Floor_Half (S) + 2.0);
                  A : constant Sample := At_S (S);
               begin
                  N_Pods := N_Pods + 1;
                  The_Pods (N_Pods) := Floor_Point (S, X) + 1.3 * A.N;
               end;
            end loop;
            S := S + 210.0;
         end loop;
      end;
   end Load;

end Track;
