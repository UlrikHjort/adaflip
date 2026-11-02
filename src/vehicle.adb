--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions;
with Track;

package body Vehicle is

   use Ada.Numerics.Elementary_Functions;

   K_Spring : constant := 55_000.0;   --  N/m a wheel
   C_Damp   : constant := 4_500.0;
   K_Bump   : constant := 300_000.0;  --  the tyre squashed past its travel
   P_Max    : constant := 520_000.0;  --  W
   F_Max    : constant := 13_000.0;   --  N at the wheels
   B_Max    : constant := 17_000.0;
   Drag     : constant := 2.2;        --  N/(m/s)^2: about 220 km/h flat out
   I_Pitch  : constant := 1_500.0;
   I_Yaw    : constant := 1_800.0;
   I_Roll   : constant := 800.0;

   --  Points on the body that meet the walls when the wheels do not
   type Body_Point is record
      X, Y, Z : Float;
   end record;
   Body_Points : constant array (1 .. 12) of Body_Point :=
     ((-0.95, 0.36, 2.05), (0.95, 0.36, 2.05), (-0.95, -0.36, 2.05), (0.95, -0.36, 2.05),
      (-0.95, 0.36, -2.05), (0.95, 0.36, -2.05), (-0.95, -0.36, -2.05), (0.95, -0.36, -2.05),
      (-1.45, 0.0, 1.35), (1.45, 0.0, 1.35), (-1.45, 0.0, -1.3), (1.45, 0.0, -1.3));
   Body_R : constant := 0.12;

   function Hub (C : Car; W : Wheel_Id) return Vec3 is
     (C.P + Wheel_X (W) * C.R + Wheel_Z (W) * C.F);

   procedure Place (C : in out Car; S, X : Float) is
      A : constant Track.Sample := Track.At_S (S);
      L : Track.Locus;
   begin
      C := (others => <>);
      C.F := A.T;
      C.U := A.N;
      C.R := Normalize (Cross (C.F, C.U));
      C.P := Track.Floor_Point (S, X) + (Wheel_R + Travel - 0.06) * A.N;
      L := Track.Locate (C.P, Natural (Float'Floor (S / Track.Step)) mod Track.Count);
      C.Hint := L.I;
      C.S := L.S;
      C.Ground_N := A.N;
   end Place;

   procedure Step (C : in out Car; In_C : Controls; Dt : Float) is
      Force  : Vec3 := (0.0, -Gravity * Mass, 0.0);
      Torque : Vec3 := Zero;

      procedure Push (F, Where : Vec3) is
      begin
         Force := Force + F;
         Torque := Torque + Cross (Where - C.P, F);
      end Push;

      L : constant Track.Locus := Track.Locate (C.P, C.Hint);
      Speed : constant Float := Length (C.V);
      Fwd : constant Float := Dot (C.V, C.F);
      Mu : constant Float := 1.8 * Track.Grip;
      Boosting : constant Boolean := C.Boost_T > 0.0;

      Hubs : array (Wheel_Id) of Vec3;
      Dist : Float4;
      Norm : array (Wheel_Id) of Vec3;
      Touch : Bool4 := (others => False);
      Touching : Natural := 0;
      N_Sum : Vec3 := Zero;
      Thr : Float := In_C.Throttle;
      Brk : Float := In_C.Brake;
      Drive : Float;
      Delta_A : Float;
      Slip_Sum : Float := 0.0;
   begin
      C.Hint := L.I;
      C.S := L.S;
      C.Impact := 0.0;
      C.Steer := C.Steer + Clamp (In_C.Steer - C.Steer, -Dt * 5.0, Dt * 5.0);
      Delta_A := C.Steer * 0.55 / (1.0 + Speed / 18.0);
      if C.Stun_T > 0.0 then
         Thr := Thr * 0.2;
      end if;

      --  Where the wheels are against the surface
      for W in Wheel_Id loop
         Hubs (W) := Hub (C, W);
         declare
            LW : constant Track.Locus := Track.Locate (Hubs (W), C.Hint);
         begin
            Track.Surface (LW, Dist (W), Norm (W));
         end;
         if Dist (W) < Wheel_R + Travel and then abs Dot (C.U, Norm (W)) > 0.3 then
            Touch (W) := True;
            Touching := Touching + 1;
            N_Sum := N_Sum + Norm (W);
         end if;
      end loop;

      --  The engine: full force from a standstill, then the power runs out
      if Brk > 0.2 and then Fwd < 1.0 and then Thr < 0.1 then
         Drive := (if Fwd > -14.0 then -0.5 * F_Max * Brk else 0.0);
         Brk := 0.0;
      else
         Drive := Thr * Float'Min (F_Max * (if Boosting then 1.5 else 1.0),
                                   P_Max * (if Boosting then 1.7 else 1.0)
                                   / Float'Max (abs Fwd, 4.0)) * C.Power;
      end if;
      if Boosting then
         Drive := Drive + 7_000.0;
      end if;

      for W in Wheel_Id loop
         if Touch (W) then
            declare
               N : constant Vec3 := Norm (W);
               X : constant Float := Wheel_R + Travel - Dist (W);
               VC : constant Vec3 := C.V + Cross (C.W, Hubs (W) - C.P);
               VN : constant Float := Dot (VC, N);
               FS : Float := K_Spring * X - C_Damp * VN;
               F_Dir : Vec3 := C.F - Dot (C.F, N) * N;
               R_Dir : Vec3;
               VT : Vec3;
               VL, VS, FX, FY, Load, Lim, H : Float;
            begin
               if Dist (W) < Wheel_R then
                  FS := FS + K_Bump * (Wheel_R - Dist (W));
               end if;
               FS := Float'Max (0.0, FS);
               Push (FS * N, Hubs (W));

               if Length (F_Dir) < 0.05 then
                  F_Dir := Cross (N, C.R);
               end if;
               F_Dir := Normalize (F_Dir);
               if W <= 2 then
                  F_Dir := Rotate (F_Dir, N, -Delta_A);
               end if;
               R_Dir := Cross (F_Dir, N);
               VT := VC - VN * N;
               VL := Dot (VT, F_Dir);
               VS := Dot (VT, R_Dir);
               Load := Float'Min (FS, Mass * Gravity);

               FY := -Mu * Load * Tanh (6.0 * Arctan (VS, abs VL + 3.0))
                 * (if W <= 2 then 1.0 else 1.08);
               FX := Drive / Float (Touching) - 15.0 * VL;
               if Brk > 0.0 then
                  FX := FX - (if VL > 0.0 then 1.0 else -1.0)
                    * Float'Min (Brk * B_Max / 4.0, 250.0 * abs VL / Dt * 0.3);
               end if;
               Lim := Mu * Load * 1.05;
               H := Sqrt (FX * FX + FY * FY);
               if H > Lim and then H > 0.0 then
                  Slip_Sum := Slip_Sum + (H - Lim) / H;
                  FX := FX * Lim / H;
                  FY := FY * Lim / H;
               end if;
               Slip_Sum := Slip_Sum + Float'Min (1.0, abs VS / 8.0) * 0.5;
               Push (FX * F_Dir + FY * R_Dir, Hubs (W) - 0.25 * N);

               C.Spin (W) := C.Spin (W) + VL / Wheel_R * Dt;
               C.Drop (W) := -Clamp (Dist (W) - Wheel_R, 0.0, Travel)
                 * (if Dot (N, C.U) > 0.0 then 1.0 else -1.0);
               if -VN > 6.0 then
                  C.Impact := Float'Max (C.Impact, -VN);
               end if;
            end;
         else
            C.Drop (W) := C.Drop (W) * (1.0 - Dt * 8.0);
            C.Spin (W) := C.Spin (W) + Thr * 40.0 * Dt;
         end if;
      end loop;
      C.Contact := Touch;
      C.Grounded := Touching;
      C.Slip := Clamp (Slip_Sum / 2.0, 0.0, 1.0);

      if Touching > 0 then
         C.Ground_N := Normalize (N_Sum);
         C.Side := (if Dot (C.U, C.Ground_N) >= 0.0 then 1.0 else -1.0);
         C.Air_T := 0.0;
         --  Clinging to walls and roofs at speed
         if Touching >= 2 then
            declare
               Wall : constant Float := Clamp (1.0 - C.Ground_N.Y, 0.0, 1.0);
               Fast : constant Float := Clamp ((Speed - 10.0) / 20.0, 0.0, 1.0);
            begin
               Push ((-2.2 * Mass * Gravity * Wall * Fast) * C.Ground_N, C.P);
            end;
         end if;
      else
         C.Air_T := C.Air_T + Dt;
      end if;

      --  The body against the walls: it slides and throws sparks
      C.Scrape := 0.0;
      for B of Body_Points loop
         declare
            Where : constant Vec3 := C.P + B.X * C.R + B.Y * C.U + B.Z * C.F;
            LB : constant Track.Locus := Track.Locate (Where, C.Hint);
            D : Float;
            N : Vec3;
         begin
            Track.Surface (LB, D, N);
            if D < Body_R then
               declare
                  VC : constant Vec3 := C.V + Cross (C.W, Where - C.P);
                  VN : constant Float := Dot (VC, N);
                  FN : constant Float := Float'Max (0.0, 250_000.0 * (Body_R - D) - 6_000.0 * VN);
                  VT : constant Vec3 := VC - VN * N;
                  LT : constant Float := Length (VT);
               begin
                  Push (FN * N, Where);
                  if LT > 0.1 then
                     Push ((-0.35 * FN / LT) * VT, Where);
                     if LT > 4.0 then
                        C.Scrape := Float'Max (C.Scrape, Float'Min (1.0, LT / 30.0));
                        C.Scrape_At := Where;
                     end if;
                  end if;
                  if -VN > 5.0 then
                     C.Impact := Float'Max (C.Impact, -VN);
                  end if;
               end;
            end if;
         end;
      end loop;

      Force := Force - (Drag * Speed) * C.V;

      --  Moving on
      C.V := C.V + (Dt / Mass) * Force;
      C.P := C.P + Dt * C.V;
      declare
         TR : constant Float := Dot (Torque, C.R) / I_Pitch;
         TU : constant Float := Dot (Torque, C.U) / I_Yaw;
         TF : constant Float := Dot (Torque, C.F) / I_Roll;
         Ang : Float;
         Ax : Vec3;
      begin
         C.W := C.W + Dt * (TR * C.R + TU * C.U + TF * C.F);
         C.W := (1.0 - Dt * (if Touching > 0 then 1.2 else 0.3)) * C.W;
         Ang := Length (C.W) * Dt;
         if Ang > 1.0E-7 then
            Ax := Normalize (C.W);
            C.F := Rotate (C.F, Ax, Ang);
            C.U := Rotate (C.U, Ax, Ang);
         end if;
         C.F := Normalize (C.F);
         C.U := Normalize (C.U - Dot (C.U, C.F) * C.F);
         C.R := Cross (C.F, C.U);
      end;

      C.Speed := Length (C.V);
      C.Fwd_Speed := Dot (C.V, C.F);
      C.Boost_T := Float'Max (0.0, C.Boost_T - Dt);
      C.Shield_T := Float'Max (0.0, C.Shield_T - Dt);
      C.Stun_T := Float'Max (0.0, C.Stun_T - Dt);
      if C.Speed < 2.0 and then Touching < 3 then
         C.Still_T := C.Still_T + Dt;
      else
         C.Still_T := 0.0;
      end if;
      declare
         D : Float;
         N : Vec3;
      begin
         Track.Surface (L, D, N);
         C.Outside := (if D < -0.6 then C.Outside + Dt else 0.0);
      end;
   end Step;

   procedure Collide (A, B : in out Car) is
      Rad : constant := 1.2;
   begin
      if Length (A.P - B.P) > 7.0 then
         return;
      end if;
      for I in -1 .. 1 loop
         for J in -1 .. 1 loop
            if I /= 0 and then J /= 0 then
               declare
                  PA : constant Vec3 := A.P + (0.95 * Float (I)) * A.F;
                  PB : constant Vec3 := B.P + (0.95 * Float (J)) * B.F;
                  D : constant Vec3 := PB - PA;
                  L : constant Float := Length (D);
               begin
                  if L < 2.0 * Rad and then L > 1.0E-3 then
                     declare
                        N : constant Vec3 := (1.0 / L) * D;
                        Pen : constant Float := 2.0 * Rad - L;
                        VR : constant Float := Dot (B.V - A.V, N);
                        Imp : Float;
                     begin
                        A.P := A.P - (Pen * 0.5) * N;
                        B.P := B.P + (Pen * 0.5) * N;
                        if VR < 0.0 then
                           Imp := -(1.3) * VR / 2.0;
                           A.V := A.V - Imp * N;
                           B.V := B.V + Imp * N;
                           A.W := A.W + 0.35 * Cross (PA - A.P, (-Imp) * N);
                           B.W := B.W + 0.35 * Cross (PB - B.P, Imp * N);
                           A.Impact := Float'Max (A.Impact, -VR);
                           B.Impact := Float'Max (B.Impact, -VR);
                        end if;
                     end;
                  end if;
               end;
            end if;
         end loop;
      end loop;
   end Collide;

   procedure Blast (C : in out Car; From : Vec3; Strength : Float; Seed : Natural) is
      Away : Vec3 := C.P - From;
      function H (K : Natural) return Float is
        (Float ((Seed * 7919 + K * 104_729) mod 2001) / 1000.0 - 1.0);
   begin
      if C.Shield_T > 0.0 then
         return;
      end if;
      if Length (Away) < 0.1 then
         Away := C.F;
      end if;
      Away := Normalize (Normalize (Away) + 1.4 * C.Ground_N);
      C.V := 0.55 * C.V + Strength * Away;
      C.W := C.W + (Strength * 0.45) * Vec3'(H (1), H (2), H (3));
      C.Stun_T := 1.1;
      C.Boost_T := 0.0;
   end Blast;

end Vehicle;
