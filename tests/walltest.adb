--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  A car put on the wall of a pipe, or on a tunnel's roof, at speed: it
--  must stay there, driving, for as long as the section lasts.
with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Math3D; use Math3D;
with Track;
with Vehicle;

procedure Walltest is
   use type Track.Section_Kind;
   Failed : Boolean := False;

   procedure Try (Id : Track.Track_Id; Kind : Track.Section_Kind; Angle_Name : String;
                  Speed : Float; Want_Y_Below : Float) is
      Start : Integer := -1;
      C : Vehicle.Car;
      Stuck_T, Run_T : Float := 0.0;
      Dt : constant := 1.0 / 360.0;
   begin
      Track.Load (Id);
      --  The middle of a long stretch of that kind
      declare
         Run : Natural := 0;
      begin
         for I in 0 .. Track.Count - 1 loop
            if Track.Get (I).Kind = Kind then
               Run := Run + 1;
               if Run = 25 then
                  Start := I;
                  exit;
               end if;
            else
               Run := 0;
            end if;
         end loop;
      end;
      if Start < 0 then
         Put_Line ("  no " & Kind'Image & " on " & Track.Name (Id));
         return;
      end if;
      declare
         S : constant Track.Sample := Track.Get (Start);
         P : constant Track.Profile := S.P;
         X, Y, NX, NY : Float;
      begin
         if Angle_Name = "wall" then
            X := P.Width / 2.0 - 0.01;
            Y := P.Height / 2.0;
         else
            X := 0.0;
            Y := P.Height - 0.01;
         end if;
         Track.Profile_Normal (P, X, Y, NX, NY);
         C.U := Normalize (NX * S.B + NY * S.N);
         C.F := S.T;
         C.R := Cross (C.F, C.U);
         C.P := S.C + X * S.B + Y * S.N + (Vehicle.Wheel_R + Vehicle.Travel - 0.06) * C.U;
         C.V := Speed * S.T;
         C.Hint := Start;
      end;
      for K in 1 .. Natural (4.0 / Dt) loop
         Vehicle.Step (C, (Steer => 0.0, Throttle => 1.0, Brake => 0.0), Dt);
         Run_T := Run_T + Dt;
         if C.Grounded >= 1 and then Dot (C.Ground_N, Track.Get (C.Hint).N) < Want_Y_Below then
            Stuck_T := Stuck_T + Dt;
         end if;
         --  back on the floor
         exit when C.Grounded >= 2 and then Dot (C.Ground_N, Track.Get (C.Hint).N) > 0.9;
         exit when Track.Get (C.Hint).Kind /= Kind;
      end loop;
      Put_Line ("  " & Track.Name (Id) & " " & Kind'Image & " " & Angle_Name & " at"
                & Integer (Speed * 3.6)'Image & " km/h: held" & Integer (100.0 * Stuck_T / Run_T)'Image
                & "% of" & Integer (Run_T * 10.0)'Image & " tenths before the floor, now" & Integer (C.Speed * 3.6)'Image & " km/h");
      if Run_T < 1.5 then
         Failed := True;
      end if;
   end Try;
begin
   Try (1, Track.Pipe, "wall", 40.0, 0.5);
   Try (1, Track.Pipe, "roof", 40.0, 0.5);
   Try (1, Track.Tunnel, "wall", 40.0, 0.5);
   Try (1, Track.Tunnel, "roof", 45.0, 0.5);
   Try (2, Track.Pipe, "roof", 45.0, 0.5);
   Try (3, Track.Tunnel, "roof", 45.0, 0.5);
   Try (3, Track.Tunnel, "wall", 30.0, 0.5);
   if Failed then
      Put_Line ("FAILED");
      Ada.Command_Line.Set_Exit_Status (1);
   else
      Put_Line ("passed");
   end if;
end Walltest;
