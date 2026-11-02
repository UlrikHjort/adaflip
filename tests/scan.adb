--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Finds the lively moments of the race the game runs with
--  ADAFLIP_AUTOSTART and ADAFLIP_AUTOPILOT (5 opponents, 3 laps, normal),
--  for scripts/make_media.sh: second by second, how fast the player's car
--  goes, how long on walls or roofs, the nearest car, explosions near it.
--
--    scan TRACK [stunt]
with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Math3D; use Math3D;
with Race;
with Track;

procedure Scan is
   use type Race.Event_Kind;
   Id : constant Track.Track_Id := Track.Track_Id'Value (Ada.Command_Line.Argument (1));
   Read : Natural := 0;
   Per_Second : constant Natural := Natural (1.0 / Race.Dt);
   Wall, Roof, Near, Speed : Float := 0.0;
   Booms : Natural := 0;
begin
   Race.Stunt_Player := Ada.Command_Line.Argument_Count > 1;
   Race.Setup (Id, 5, 3, Race.Normal, Attract => False);
   Put_Line ("clock  km/h  wall  roof  near  booms");
   for K in 1 .. 200 * Per_Second loop
      Race.Step ((others => <>), Player_AI => True);
      declare
         C : constant Race.Racer := Race.State.Racers (Race.Player);
         Up : constant Float := Dot (C.Car.Ground_N, Track.Get (C.Car.Hint).N);
         D : Float := 999.0;
      begin
         Speed := Speed + C.Car.Speed * 3.6;
         if C.Car.Grounded > 0 and then Up < 0.6 then
            Wall := Wall + Race.Dt;
         end if;
         if C.Car.Grounded > 0 and then Up < -0.5 then
            Roof := Roof + Race.Dt;
         end if;
         for J in 2 .. Race.State.Count loop
            D := Float'Min (D, Length (Race.State.Racers (J).Car.P - C.Car.P));
         end loop;
         Near := Near + D;
         while Read < Race.Event_Serial loop
            declare
               E : constant Race.Event := Race.Events (Read mod Race.Event_Ring);
            begin
               if E.Kind = Race.Explosion and then Length (E.P - C.Car.P) < 60.0 then
                  Booms := Booms + 1;
               end if;
            end;
            Read := Read + 1;
         end loop;
      end;
      if K mod Per_Second = 0 then
         declare
            function I (X : Float) return String is (Integer (X)'Image);
         begin
            Put_Line (I (Race.State.Clock) & "  " & I (Speed / Float (Per_Second)) & "  "
                      & I (Wall * 10.0) & "  " & I (Roof * 10.0) & "  "
                      & I (Near / Float (Per_Second)) & "  " & Booms'Image);
         end;
         Wall := 0.0;
         Roof := 0.0;
         Near := 0.0;
         Speed := 0.0;
         Booms := 0;
      end if;
   end loop;
end Scan;
