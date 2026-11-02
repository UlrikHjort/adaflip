--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics.Elementary_Functions;

package body Race is

   use Ada.Numerics.Elementary_Functions;
   use type Vehicle.Wheel_Id;

   function Weapon_Name (W : Weapon) return String is
     (case W is
         when None   => "",
         when Turbo  => "TURBO",
         when Rocket => "ROCKET",
         when Mine   => "MINE",
         when Pulse  => "SHOCKWAVE",
         when Shield => "SHIELD");

   type Seed_Type is mod 2**32;
   Seed : Seed_Type := 12345;

   function Random return Float is
   begin
      Seed := Seed * 1103515245 + 12345;
      return Float ((Seed / 65536) mod 100_000) / 100_000.0;
   end Random;

   type Float_Cars is array (Car_Index) of Float;
   Bump_Wait, Scrape_Wait, Reset_Wait : Float_Cars := (others => 0.0);
   Pod_S, Pod_X : array (1 .. Track.Max_Pods) of Float := (others => 0.0);
   Level_Now : Difficulty := Normal;
   Last_Beep : Integer := -10;

   procedure Tell (E : Event) is
   begin
      Events (Event_Serial mod Event_Ring) := E;
      Event_Serial := Event_Serial + 1;
   end Tell;

   function Place_Of (I : Car_Index) return Positive is (State.Racers (I).Place);

   function Lap_Shown (I : Car_Index) return Positive is
     (Positive (Integer'Max (1, Integer'Min (State.Laps, State.Racers (I).Lap + 1))));

   ---------------------------------------------------------------------------

   procedure Setup (Id : Track.Track_Id; Opponents : Natural; Laps : Positive;
                    Level : Difficulty; Attract : Boolean) is
      L : Float;
   begin
      Track.Load (Id);
      L := Track.Length;
      Level_Now := Level;
      State := (others => <>);
      State.Count := Car_Index (Integer'Min (Max_Cars, 1 + Opponents));
      State.Laps := (if Attract then 999 else Laps);
      State.Attract := Attract;
      State.Phase := (if Attract then Running else Countdown);
      State.Clock := (if Attract then 0.0 else -4.0);
      Last_Beep := -10;
      Seed := 12345 + Seed_Type (Id) * 77;
      for I in 1 .. State.Count loop
         declare
            R : Racer renames State.Racers (I);
            Slot : constant Natural := (if I = Player then Natural (State.Count) - 1 else I - 2);
            Row : constant Natural := Slot / 2;
            Col : constant Natural := Slot mod 2;
            S : constant Float := L - 16.0 - Float (Row) * 11.0 - Float (Col) * 4.0;
            X : constant Float := (if Col = 0 then -3.2 else 3.2);
            Base : constant Float :=
              (case Level is
                  when Easy => 0.84,
                  when Normal => 0.92,
                  when Hard => 0.99);
         begin
            Vehicle.Place (R.Car, S, X);
            R.Prev_P := R.Car.P;
            R.Prev_F := R.Car.F;
            R.Prev_U := R.Car.U;
            R.AI := Attract or else I /= Player;
            R.Name := Car_Names (I);
            R.Color := I - 1;
            R.Last_S := R.Car.S;
            R.Lane := (Random - 0.5) * 6.0;
            R.Skill := Base + 0.05 * Float ((I * 3) mod 5) / 4.0;
            if I = Player and then not Attract then
               R.Skill := 1.0;
            end if;
            R.Car.Power := (if R.AI then 0.9 + 0.1 * R.Skill else 1.0);
            R.Fire_Wait := 2.0 + Random * 3.0;
         end;
      end loop;
      Shots := (others => <>);
      Mines := (others => <>);
      Pod_Count := Track.Pod_Count;
      declare
         P : constant Track.Pod_List := Track.Pods;
      begin
         for K in 1 .. Pod_Count loop
            Pods (K) := (P => P (K), Wait => 0.0);
            declare
               LK : constant Track.Locus := Track.Locate (P (K), 0);
            begin
               Pod_S (K) := LK.S;
               Pod_X (K) := LK.X;
            end;
         end loop;
      end;
      Bump_Wait := (others => 0.0);
      Scrape_Wait := (others => 0.0);
      Reset_Wait := (others => 0.0);
   end Setup;

   procedure Reset_Racer (I : Car_Index) is
      R : Racer renames State.Racers (I);
      S : constant Float := R.Car.S - 4.0;
      Half : constant Float := Float'Max (0.0, Track.Floor_Half (S) - 1.0);
      X : constant Float := Clamp (R.Lane, -Half, Half);
      Power : constant Float := R.Car.Power;
   begin
      Vehicle.Place (R.Car, (if S < 0.0 then S + Track.Length else S), X);
      R.Car.Power := Power;
      R.Car.Shield_T := 2.0;   --  a moment to get going again
      R.Prev_P := R.Car.P;
      R.Prev_F := R.Car.F;
      R.Prev_U := R.Car.U;
      R.Resets := R.Resets + 1;
      --  The line may not be crossed by being put back over it
      if abs (R.Car.S - R.Last_S) > Track.Length / 2.0 then
         R.Last_S := R.Car.S;
         R.Lap := R.Lap - 1;
      end if;
      Tell ((Kind => Reset_Car, P => R.Car.P, Car => I, others => <>));
   end Reset_Racer;

   ---------------------------------------------------------------------------
   --  Weapons
   ---------------------------------------------------------------------------

   procedure Explode (Where : Vec3; Owner : Natural; Big : Float) is
   begin
      Tell ((Kind => Explosion, P => Where, Car => Owner, Size => Big, others => <>));
      for I in 1 .. State.Count loop
         declare
            C : Vehicle.Car renames State.Racers (I).Car;
            D : constant Float := Length (C.P - Where);
            Reach : constant Float := 7.0 * Big;
         begin
            if D < Reach and then C.Shield_T <= 0.0 then
               Vehicle.Blast (C, Where, 4.0 + 11.0 * Big * (1.0 - D / Reach), Natural (Seed mod 9973) + I);
               State.Racers (I).Hits := State.Racers (I).Hits + 1;
               if I = Player or else Owner = Player then
                  Tell ((Kind => Hit_Player, P => Where, Car => I, Other => Owner, others => <>));
               end if;
            end if;
         end;
      end loop;
   end Explode;

   function Target_Ahead (I : Car_Index; Reach : Float) return Natural is
      C : Vehicle.Car renames State.Racers (I).Car;
      Best : Natural := 0;
      Best_D : Float := Reach;
   begin
      for J in 1 .. State.Count loop
         if J /= I then
            declare
               D : constant Vec3 := State.Racers (J).Car.P - C.P;
               L : constant Float := Length (D);
            begin
               if L < Best_D and then L > 1.0 and then Dot (D, C.F) / L > 0.82 then
                  Best := J;
                  Best_D := L;
               end if;
            end;
         end if;
      end loop;
      return Best;
   end Target_Ahead;

   procedure Use_Weapon (I : Car_Index) is
      R : Racer renames State.Racers (I);
      C : Vehicle.Car renames R.Car;
      W : constant Weapon := R.Held;
   begin
      R.Held := None;
      case W is
         when None => return;
         when Turbo =>
            C.Boost_T := 3.0;
            Tell ((Kind => Boost_On, P => C.P, Car => I, others => <>));
         when Shield =>
            C.Shield_T := 6.0;
            Tell ((Kind => Shield_On, P => C.P, Car => I, others => <>));
         when Rocket =>
            for K in Shots'Range loop
               if not Shots (K).Active then
                  Shots (K) := (Active => True,
                                P => C.P + 2.8 * C.F + (0.2 * C.Side) * C.U,
                                V => (Float'Max (0.0, C.Fwd_Speed) + 60.0) * C.F,
                                Owner => I, Target => Target_Ahead (I, 170.0),
                                Life => 4.0, Hint => C.Hint);
                  Tell ((Kind => Fired_Rocket, P => C.P, Car => I, Other => Shots (K).Target,
                         others => <>));
                  exit;
               end if;
            end loop;
         when Mine =>
            for K in Mines'Range loop
               if not Mines (K).Active then
                  declare
                     Where : constant Vec3 := C.P - 3.2 * C.F;
                     L : constant Track.Locus := Track.Locate (Where, C.Hint);
                     D : Float;
                     N : Vec3;
                  begin
                     Track.Surface (L, D, N);
                     Mines (K) := (Active => True, P => Where - (D - 0.15) * N, N => N,
                                   Owner => I, Age => 0.0);
                  end;
                  Tell ((Kind => Dropped_Mine, P => C.P, Car => I, others => <>));
                  exit;
               end if;
            end loop;
         when Pulse =>
            Tell ((Kind => Pulsed, P => C.P, Car => I, others => <>));
            for J in 1 .. State.Count loop
               if J /= I then
                  declare
                     O : Vehicle.Car renames State.Racers (J).Car;
                     D : constant Float := Length (O.P - C.P);
                  begin
                     if D < 28.0 and then O.Shield_T <= 0.0 then
                        Vehicle.Blast (O, C.P, 6.0 + 4.0 * (1.0 - D / 28.0), J * 31 + Natural (Seed mod 997));
                        O.V := 0.6 * O.V;
                        State.Racers (J).Hits := State.Racers (J).Hits + 1;
                        if J = Player or else I = Player then
                           Tell ((Kind => Hit_Player, P => C.P, Car => J, Other => I, others => <>));
                        end if;
                     end if;
                  end;
               end if;
            end loop;
      end case;
   end Use_Weapon;

   function Pick_Weapon return Weapon is
      X : constant Float := Random;
   begin
      return (if X < 0.24 then Turbo
              elsif X < 0.50 then Rocket
              elsif X < 0.68 then Mine
              elsif X < 0.84 then Pulse
              else Shield);
   end Pick_Weapon;

   procedure Move_Shots is
   begin
      for K in Shots'Range loop
         declare
            S : Shot renames Shots (K);
         begin
            if S.Active then
               S.Life := S.Life - Dt;
               if S.Target /= 0 then
                  declare
                     To : constant Vec3 := State.Racers (S.Target).Car.P - S.P;
                     Sp : constant Float := Float'Max (70.0, Length (S.V));
                     Want : constant Vec3 := Normalize (To);
                     Dir : constant Vec3 := Normalize (S.V);
                  begin
                     S.V := Sp * Normalize (Dir + (3.2 * Dt) * Want);
                  end;
               end if;
               S.P := S.P + Dt * S.V;
               declare
                  L : constant Track.Locus := Track.Locate (S.P, S.Hint);
                  D : Float;
                  N : Vec3;
                  Hit : Boolean := False;
               begin
                  S.Hint := L.I;
                  Track.Surface (L, D, N);
                  --  Along the surface it hugs it, but straight into it, it bursts
                  if D < 0.6 and then Dot (Normalize (S.V), N) > -0.35 then
                     S.P := S.P + (0.6 - D) * N;
                     S.V := S.V - Float'Min (0.0, Dot (S.V, N)) * N;
                  elsif D < 0.25 then
                     Hit := True;
                  end if;
                  for J in 1 .. State.Count loop
                     if (J /= S.Owner or else S.Life < 3.4)
                       and then Length (State.Racers (J).Car.P - S.P) < 2.3
                     then
                        Hit := True;
                     end if;
                  end loop;
                  if Hit or else S.Life <= 0.0 then
                     S.Active := False;
                     Explode (S.P, S.Owner, 1.0);
                  end if;
               end;
            end if;
         end;
      end loop;
      for K in Mines'Range loop
         declare
            M : Mine_Rec renames Mines (K);
         begin
            if M.Active then
               M.Age := M.Age + Dt;
               if M.Age > 45.0 then
                  M.Active := False;
               elsif M.Age > 0.5 then
                  for J in 1 .. State.Count loop
                     if (J /= M.Owner or else M.Age > 2.5)
                       and then Length (State.Racers (J).Car.P - M.P) < 2.7
                     then
                        M.Active := False;
                        Explode (M.P, M.Owner, 1.1);
                        exit;
                     end if;
                  end loop;
               end if;
            end if;
         end;
      end loop;
   end Move_Shots;

   ---------------------------------------------------------------------------
   --  The AI
   ---------------------------------------------------------------------------

   function AI_Drive (I : Car_Index) return Vehicle.Controls is
      R : Racer renames State.Racers (I);
      C : Vehicle.Car renames R.Car;
      L : constant Float := Track.Length;
      Look : constant Float := Clamp (C.Speed * 0.55, 10.0, 38.0);
      Aim_S : constant Float := C.S + Look;
      Lane : Float := R.Lane;
      Out_C : Vehicle.Controls;
   begin
      --  A pod ahead when the hands are empty
      if R.Held = None then
         declare
            Best : Float := 90.0;
         begin
            for K in 1 .. Pod_Count loop
               if Pods (K).Wait <= 0.0 then
                  declare
                     Ahead : Float := Pod_S (K) - C.S;
                  begin
                     if Ahead < -L / 2.0 then
                        Ahead := Ahead + L;
                     end if;
                     if Ahead > 12.0 and then Ahead < Best then
                        Best := Ahead;
                        Lane := Pod_X (K);
                     end if;
                  end;
               end if;
            end loop;
         end;
      end if;
      --  Round a car close ahead
      for J in 1 .. State.Count loop
         if J /= I then
            declare
               O : Racer renames State.Racers (J);
               Gap : constant Float := O.Progress - R.Progress;
            begin
               if Gap > 0.0 and then Gap < 22.0 then
                  declare
                     LO : constant Track.Locus := Track.Locate (O.Car.P, O.Car.Hint);
                  begin
                     if abs (LO.X - Lane) < 3.2 then
                        Lane := (if LO.X > 0.0 then LO.X - 4.0 else LO.X + 4.0);
                     end if;
                  end;
               end if;
            end;
         end if;
      end loop;
      declare
         use type Track.Section_Kind;
         Half : constant Float := Float'Max (0.0, Track.Floor_Half (Aim_S) - 1.2);
         A : constant Track.Sample := Track.At_S (Aim_S);
         Kind : constant Track.Section_Kind := Track.At_S (C.S + 20.0).Kind;
         Stunt : constant Boolean :=
           I = Player and then Stunt_Player and then Kind /= Track.Open and then Kind /= Track.Wide
           and then Track.At_S (C.S + 10.0).Kind = Kind and then C.Speed > 22.0;
         Tgt : Vec3 := Track.Floor_Point (Aim_S, Clamp (Lane, -Half, Half)) + 0.9 * A.N;
         Dir : Vec3;
         N : constant Vec3 := (if C.Grounded > 0 then C.Ground_N else C.Side * C.U);
         F : constant Vec3 := Normalize (C.F - Dot (C.F, N) * N);
         Rt : constant Vec3 := Cross (F, N);
         Ang : Float;
         V1 : constant Float := Track.At_S (C.S + 6.0).Vmax;
         V2 : constant Float := Track.At_S (C.S + C.Speed * 0.6).Vmax;
         Vt : constant Float := Float'Min (V1, V2) * R.Skill;
      begin
         --  Up the wall, round towards the roof, a little at a time
         if Stunt then
            declare
               Now_A : constant Float := Track.Angle_Of (Track.Locate (C.P, C.Hint));
               Side : constant Float := (if Now_A >= 0.0 then 1.0 else -1.0);
               Want : constant Float :=
                 (if Kind = Track.Halfpipe then 1.25 else 3.1416) * Side;
               Next : constant Float := Now_A + Clamp (Want - Now_A, -0.7, 0.7);
               S2 : constant Track.Sample := Track.At_S (Aim_S);
               P2 : constant Vec3 := Track.Round_Point (Aim_S, Next);
               NX, NY : Float;
               LL : constant Track.Locus := Track.Locate (P2, C.Hint);
            begin
               Track.Profile_Normal (LL.P, LL.X, LL.Y, NX, NY);
               Tgt := P2 + 0.9 * (NX * S2.B + NY * S2.N);
            end;
         end if;
         Dir := Tgt - C.P;
         Ang := Arctan (Dot (Dir, Rt), Dot (Dir, F));
         Out_C.Steer := Clamp (Ang * 2.6, -1.0, 1.0);
         if C.Speed < Vt then
            Out_C.Throttle := (if abs Ang > 1.0 then 0.5 else 1.0);
         elsif C.Speed > Vt + 4.0 then
            Out_C.Brake := 0.7;
         else
            Out_C.Throttle := 0.3;
         end if;
         --  Facing back the way it came: turn round in reverse
         if Dot (C.F, A.T) < -0.3 and then C.Speed < 8.0 then
            Out_C.Throttle := 0.0;
            Out_C.Brake := 1.0;
            Out_C.Steer := -Out_C.Steer;
         end if;
      end;
      return Out_C;
   end AI_Drive;

   procedure AI_Weapons (I : Car_Index) is
      R : Racer renames State.Racers (I);
      C : Vehicle.Car renames R.Car;
      Go : Boolean := False;
   begin
      R.Fire_Wait := R.Fire_Wait - Dt;
      if R.Held = None or else R.Fire_Wait > 0.0 or else State.Phase /= Running then
         return;
      end if;
      R.Fire_Wait := (case Level_Now is
                         when Easy => 1.5, when Normal => 0.6, when Hard => 0.25);
      case R.Held is
         when None => null;
         when Turbo =>
            Go := C.Speed > 20.0 and then Track.At_S (C.S + 70.0).Vmax > C.Speed + 12.0
              and then C.Grounded >= 2;
         when Rocket =>
            Go := Target_Ahead (I, 140.0) /= 0;
         when Mine =>
            for J in 1 .. State.Count loop
               declare
                  Gap : constant Float := R.Progress - State.Racers (J).Progress;
               begin
                  if J /= I and then Gap > 5.0 and then Gap < 45.0 then
                     Go := True;
                  end if;
               end;
            end loop;
         when Pulse =>
            for J in 1 .. State.Count loop
               if J /= I and then Length (State.Racers (J).Car.P - C.P) < 20.0 then
                  Go := True;
               end if;
            end loop;
         when Shield =>
            for K in Shots'Range loop
               if Shots (K).Active and then Shots (K).Target = I then
                  Go := True;
               end if;
            end loop;
            Go := Go or else Random < 0.05;
      end case;
      if Go then
         Use_Weapon (I);
      end if;
   end AI_Weapons;

   ---------------------------------------------------------------------------

   procedure Count_Laps (I : Car_Index) is
      R : Racer renames State.Racers (I);
      L : constant Float := Track.Length;
      D : constant Float := R.Car.S - R.Last_S;
   begin
      if D < -L / 2.0 then
         R.Lap := R.Lap + 1;
         if R.Lap >= 1 and then not R.Finished then
            R.Last_Lap := State.Clock - R.Lap_Start;
            R.Lap_Start := State.Clock;
            if R.Best_Lap = 0.0 or else R.Last_Lap < R.Best_Lap then
               R.Best_Lap := R.Last_Lap;
            end if;
            if R.Lap >= State.Laps then
               R.Finished := True;
               R.Finish_T := State.Clock;
               Tell ((Kind => Finished, P => R.Car.P, Car => I, others => <>));
            else
               Tell ((Kind => Lap_Done, P => R.Car.P, Car => I, others => <>));
               if R.Lap = State.Laps - 1 then
                  Tell ((Kind => Final_Lap, P => R.Car.P, Car => I, others => <>));
               end if;
            end if;
         end if;
      elsif D > L / 2.0 then
         R.Lap := R.Lap - 1;
      end if;
      R.Last_S := R.Car.S;
      R.Progress := Float (R.Lap) * L + R.Car.S;
   end Count_Laps;

   procedure Order is
   begin
      for I in 1 .. State.Count loop
         declare
            P : Positive := 1;
            A : Racer renames State.Racers (I);
         begin
            for J in 1 .. State.Count loop
               if J /= I then
                  declare
                     B : Racer renames State.Racers (J);
                     Ahead : constant Boolean :=
                       (if B.Finished and then A.Finished then
                           B.Finish_T < A.Finish_T or else (B.Finish_T = A.Finish_T and then J < I)
                        elsif B.Finished then True
                        elsif A.Finished then False
                        else B.Progress > A.Progress
                          or else (B.Progress = A.Progress and then J < I));
                  begin
                     if Ahead then
                        P := P + 1;
                     end if;
                  end;
               end if;
            end loop;
            A.Place := P;
         end;
      end loop;
   end Order;

   procedure Step (Input : Player_Input; Player_AI : Boolean := False) is
   begin
      State.Clock := State.Clock + Dt;
      if State.Phase = Countdown then
         declare
            Sec : constant Integer := Integer (Float'Floor (State.Clock));
         begin
            if Sec >= -3 and then Sec < 0 and then Sec /= Last_Beep then
               Last_Beep := Sec;
               Tell ((Kind => Beep, Size => Float (-Sec), others => <>));
            end if;
         end;
         if State.Clock >= 0.0 then
            State.Phase := Running;
            Tell ((Kind => Go, others => <>));
            for I in 1 .. State.Count loop
               State.Racers (I).Lap_Start := 0.0;
            end loop;
         end if;
      end if;

      for I in 1 .. State.Count loop
         declare
            R : Racer renames State.Racers (I);
            Ctl : Vehicle.Controls;
         begin
            R.Prev_P := R.Car.P;
            R.Prev_F := R.Car.F;
            R.Prev_U := R.Car.U;
            if R.AI or else Player_AI or else R.Finished then
               Ctl := AI_Drive (I);
            else
               Ctl := Input.Drive;
            end if;
            if State.Phase = Countdown then
               Ctl.Throttle := 0.0;
               Ctl.Brake := 0.0;
            end if;
            Vehicle.Step (R.Car, Ctl, Dt);
         end;
      end loop;

      for I in 1 .. State.Count loop
         for J in I + 1 .. State.Count loop
            Vehicle.Collide (State.Racers (I).Car, State.Racers (J).Car);
         end loop;
      end loop;

      for I in 1 .. State.Count loop
         declare
            R : Racer renames State.Racers (I);
            C : Vehicle.Car renames R.Car;
         begin
            Count_Laps (I);
            Bump_Wait (I) := Float'Max (0.0, Bump_Wait (I) - Dt);
            Scrape_Wait (I) := Float'Max (0.0, Scrape_Wait (I) - Dt);
            Reset_Wait (I) := Float'Max (0.0, Reset_Wait (I) - Dt);
            if C.Impact > 7.0 and then Bump_Wait (I) <= 0.0 then
               Bump_Wait (I) := 0.25;
               Tell ((Kind => Bump, P => C.P, Car => I, Size => C.Impact, others => <>));
            end if;
            if C.Scrape > 0.15 and then Scrape_Wait (I) <= 0.0 then
               Scrape_Wait (I) := 0.03;
               Tell ((Kind => Scrape, P => C.Scrape_At, Car => I, Size => C.Scrape, others => <>));
            end if;
            --  Lost: out of the track, on its side, or flying for ever
            if C.Outside > 0.3 or else C.Still_T > 2.5 or else C.Air_T > 5.0
              or else (I = Player and then Input.Reset and then Reset_Wait (I) <= 0.0
                       and then State.Phase /= Countdown)
            then
               Reset_Wait (I) := 1.5;
               Reset_Racer (I);
            end if;
            --  Going the wrong way
            if Dot (C.V, Track.At_S (C.S).T) < -4.0 then
               R.Wrong_Way := R.Wrong_Way + Dt;
            else
               R.Wrong_Way := 0.0;
            end if;
            --  Pods
            if R.Held = None then
               for K in 1 .. Pod_Count loop
                  if Pods (K).Wait <= 0.0 and then Length (Pods (K).P - C.P) < 3.0 then
                     Pods (K).Wait := 6.0;
                     R.Held := Pick_Weapon;
                     Tell ((Kind => Picked, P => Pods (K).P, Car => I, W => R.Held, others => <>));
                     exit;
                  end if;
               end loop;
            end if;
            if State.Phase = Running then
               if R.AI or else Player_AI then
                  AI_Weapons (I);
               elsif Input.Fire and then R.Held /= None then
                  Use_Weapon (I);
               end if;
            end if;
         end;
      end loop;
      for K in 1 .. Pod_Count loop
         Pods (K).Wait := Float'Max (0.0, Pods (K).Wait - Dt);
      end loop;
      Move_Shots;
      Order;

      if State.Phase = Running and then not State.Attract
        and then State.Racers (Player).Finished
      then
         State.Phase := Over;
      end if;
      if State.Phase = Over then
         State.Over_T := State.Over_T + Dt;
      end if;
   end Step;

end Race;
