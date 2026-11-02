--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Headless checks: every track is raced by the AI alone; each car must
--  finish, without being put back on the track too often.
with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Race;
with Track;

procedure Simtest is
   use type Race.Event_Kind;
   Failed : Boolean := False;
   Laps : constant := 3;
begin
   for Id in Track.Track_Id loop
      Race.Setup (Id, 5, Laps, Race.Normal, Attract => False);
      Put_Line (Track.Name (Id) & ":" & Integer (Track.Length)'Image & " m,"
                & Track.Count'Image & " samples," & Track.Pod_Count'Image & " pods");
      declare
         Top : array (Race.Car_Index) of Float := (others => 0.0);
         Wall_T : array (Race.Car_Index) of Float := (others => 0.0);
         Steps : Natural := 0;
         Booms : Natural := 0;
         Last_Serial : Natural := 0;
      begin
         while Race.State.Clock < 420.0 loop
            Race.Step ((others => <>), Player_AI => True);
            Steps := Steps + 1;
            for I in 1 .. Race.State.Count loop
               declare
                  C : constant Race.Racer := Race.State.Racers (I);
               begin
                  Top (I) := Float'Max (Top (I), C.Car.Speed);
                  if C.Car.Grounded > 0 and then C.Car.Ground_N.Y < 0.5 then
                     Wall_T (I) := Wall_T (I) + Race.Dt;
                  end if;
               end;
            end loop;
            while Last_Serial < Race.Event_Serial loop
               if Race.Events (Last_Serial mod Race.Event_Ring).Kind = Race.Explosion then
                  Booms := Booms + 1;
               end if;
               Last_Serial := Last_Serial + 1;
            end loop;
            declare
               All_Done : Boolean := True;
            begin
               for I in 1 .. Race.State.Count loop
                  All_Done := All_Done and then Race.State.Racers (I).Finished;
               end loop;
               exit when All_Done;
            end;
         end loop;
         for I in 1 .. Race.State.Count loop
            declare
               R : constant Race.Racer := Race.State.Racers (I);
               function F1 (X : Float) return String is
                  S : constant String := Integer (X * 10.0)'Image;
               begin
                  return S (S'First .. S'Last - 1) & "." & S (S'Last);
               end F1;
            begin
               Put_Line ("  " & R.Name & " place" & R.Place'Image
                         & " laps" & R.Lap'Image
                         & (if R.Finished then " time " & F1 (R.Finish_T) else " DNF")
                         & " best " & F1 (R.Best_Lap)
                         & " top" & Integer (Top (I) * 3.6)'Image & " km/h"
                         & " walls " & F1 (Wall_T (I)) & " s"
                         & " resets" & R.Resets'Image & " hit" & R.Hits'Image);
               if not R.Finished or else R.Resets > 12 then
                  Failed := True;
               end if;
            end;
         end loop;
         Put_Line ("  explosions" & Booms'Image);
      end;
   end loop;
   if Failed then
      Put_Line ("FAILED");
      Ada.Command_Line.Set_Exit_Status (1);
   else
      Put_Line ("passed");
   end if;
end Simtest;
