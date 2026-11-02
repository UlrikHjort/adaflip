--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Cairo; use Cairo;
with Cairo.Image_Surface;
with Cairo.Surface;
with Glib; use Glib;
with Gtkada.Types;
with Car_Model;
with Hud_Layer;
with Math3D; use Math3D;
with Mesh;
with Race;
with Track;

package body Hud is

   use type Race.Weapon;
   use type Race.Phase_Kind;

   Pi : constant := Ada.Numerics.Pi;

   Surface : Cairo_Surface := Null_Surface;
   Cr : Cairo_Context := Null_Context;
   Surf_W, Surf_H : Natural := 0;
   Scale : Float := 1.0;   --  of the panels: 1 at 1080 lines

   function D (X : Float) return Gdouble is (Gdouble (X * Scale));

   ---------------------------------------------------------------------------
   --  Small helpers
   ---------------------------------------------------------------------------

   procedure Color (R, G, B : Float; A : Float := 1.0) is
   begin
      Set_Source_Rgba (Cr, Gdouble (R), Gdouble (G), Gdouble (B), Gdouble (A));
   end Color;

   procedure Font (Size : Float; Italic : Boolean := True; Bold : Boolean := True) is
   begin
      Select_Font_Face (Cr, "DejaVu Sans",
                        (if Italic then Cairo_Font_Slant_Oblique else Cairo_Font_Slant_Normal),
                        (if Bold then Cairo_Font_Weight_Bold else Cairo_Font_Weight_Normal));
      Set_Font_Size (Cr, D (Size));
   end Font;

   function Width_Of (S : String) return Float is
      P : Gtkada.Types.Chars_Ptr := Gtkada.Types.New_String (S);
      E : aliased Cairo_Text_Extents;
   begin
      Text_Extents (Cr, P, E'Access);
      Gtkada.Types.Free (P);
      return Float (E.X_Advance);
   end Width_Of;

   --  Text at X (screen pixels), its base line at Y; Align -1 left, 0 middle, 1 right
   procedure Text (S : String; X, Y : Float; Align : Integer := -1; Shadow : Boolean := True) is
      W : constant Float := Width_Of (S);
      X0 : constant Float := (case Align is when -1 => X, when 0 => X - W / 2.0, when others => X - W);
   begin
      if Shadow then
         Save (Cr);
         Set_Source_Rgba (Cr, 0.0, 0.0, 0.0, 0.55);
         Move_To (Cr, Gdouble (X0 + 2.0 * Scale), Gdouble (Y + 2.0 * Scale));
         Show_Text (Cr, S);
         Restore (Cr);
      end if;
      Move_To (Cr, Gdouble (X0), Gdouble (Y));
      Show_Text (Cr, S);
   end Text;

   procedure Rounded (X, Y, W, H, R : Float) is
   begin
      New_Path (Cr);
      Arc (Cr, Gdouble (X + W - R), Gdouble (Y + R), Gdouble (R), Gdouble (-Pi / 2.0), 0.0);
      Arc (Cr, Gdouble (X + W - R), Gdouble (Y + H - R), Gdouble (R), 0.0, Gdouble (Pi / 2.0));
      Arc (Cr, Gdouble (X + R), Gdouble (Y + H - R), Gdouble (R), Gdouble (Pi / 2.0), Gdouble (Pi));
      Arc (Cr, Gdouble (X + R), Gdouble (Y + R), Gdouble (R), Gdouble (Pi), Gdouble (3.0 * Pi / 2.0));
      Close_Path (Cr);
   end Rounded;

   procedure Panel (X, Y, W, H : Float; A : Float := 0.45) is
   begin
      Rounded (X, Y, W, H, 10.0 * Scale);
      Color (0.02, 0.03, 0.06, A);
      Fill (Cr);
   end Panel;

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return (if N >= 0 then S (S'First + 1 .. S'Last) else S);
   end Img;

   function Two (N : Natural) return String is
     (if N < 10 then "0" & Img (N) else Img (N));

   function Time_Of (T : Float) return String is
      Cs : constant Natural := Natural (Float'Max (0.0, T) * 100.0);
   begin
      return Img (Cs / 6000) & ":" & Two ((Cs / 100) mod 60) & "." & Two (Cs mod 100);
   end Time_Of;

   function Ordinal (N : Positive) return String is
     (Img (N) & (case N is
                    when 1 => "st", when 2 => "nd", when 3 => "rd", when others => "th"));

   procedure Paint_Of (I : Race.Car_Index; A : Float := 1.0) is
      P : constant Mesh.Color :=
        Car_Model.Paints (Race.State.Racers (I).Color mod Car_Model.Paints'Length);
   begin
      Color (P.R, P.G, P.B, A);
   end Paint_Of;

   ---------------------------------------------------------------------------
   --  The weapons' little pictures
   ---------------------------------------------------------------------------

   procedure Icon (W : Race.Weapon; CX, CY, S : Float) is
   begin
      Set_Line_Width (Cr, D (4.0));
      case W is
         when Race.None => null;
         when Race.Turbo =>
            Color (1.0, 0.6, 0.1);
            for K in 0 .. 1 loop
               declare
                  X : constant Float := CX - S * 0.35 + Float (K) * S * 0.4;
               begin
                  New_Path (Cr);
                  Move_To (Cr, Gdouble (X), Gdouble (CY - S * 0.4));
                  Line_To (Cr, Gdouble (X + S * 0.35), Gdouble (CY));
                  Line_To (Cr, Gdouble (X), Gdouble (CY + S * 0.4));
                  Stroke (Cr);
               end;
            end loop;
         when Race.Rocket =>
            Color (0.9, 0.9, 0.95);
            New_Path (Cr);
            Move_To (Cr, Gdouble (CX + S * 0.5), Gdouble (CY));
            Line_To (Cr, Gdouble (CX + S * 0.15), Gdouble (CY - S * 0.16));
            Line_To (Cr, Gdouble (CX - S * 0.35), Gdouble (CY - S * 0.16));
            Line_To (Cr, Gdouble (CX - S * 0.5), Gdouble (CY - S * 0.35));
            Line_To (Cr, Gdouble (CX - S * 0.5), Gdouble (CY + S * 0.35));
            Line_To (Cr, Gdouble (CX - S * 0.35), Gdouble (CY + S * 0.16));
            Line_To (Cr, Gdouble (CX + S * 0.15), Gdouble (CY + S * 0.16));
            Close_Path (Cr);
            Fill (Cr);
            Color (1.0, 0.4, 0.1);
            Arc (Cr, Gdouble (CX - S * 0.58), Gdouble (CY), Gdouble (S * 0.1), 0.0, Gdouble (2.0 * Pi));
            Fill (Cr);
         when Race.Mine =>
            Color (0.85, 0.2, 0.15);
            New_Path (Cr);
            Arc (Cr, Gdouble (CX), Gdouble (CY), Gdouble (S * 0.28), 0.0, Gdouble (2.0 * Pi));
            Fill (Cr);
            for K in 0 .. 7 loop
               declare
                  A : constant Float := Float (K) * Pi / 4.0;
               begin
                  New_Path (Cr);
                  Move_To (Cr, Gdouble (CX + S * 0.25 * Cos (A)), Gdouble (CY + S * 0.25 * Sin (A)));
                  Line_To (Cr, Gdouble (CX + S * 0.45 * Cos (A)), Gdouble (CY + S * 0.45 * Sin (A)));
                  Stroke (Cr);
               end;
            end loop;
         when Race.Pulse =>
            Color (0.4, 0.8, 1.0);
            for K in 1 .. 3 loop
               New_Path (Cr);
               Arc (Cr, Gdouble (CX), Gdouble (CY), Gdouble (S * 0.15 * Float (K)), 0.0, Gdouble (2.0 * Pi));
               Stroke (Cr);
            end loop;
         when Race.Shield =>
            Color (0.3, 0.9, 1.0);
            New_Path (Cr);
            Move_To (Cr, Gdouble (CX), Gdouble (CY - S * 0.45));
            Line_To (Cr, Gdouble (CX + S * 0.38), Gdouble (CY - S * 0.3));
            Line_To (Cr, Gdouble (CX + S * 0.3), Gdouble (CY + S * 0.15));
            Line_To (Cr, Gdouble (CX), Gdouble (CY + S * 0.45));
            Line_To (Cr, Gdouble (CX - S * 0.3), Gdouble (CY + S * 0.15));
            Line_To (Cr, Gdouble (CX - S * 0.38), Gdouble (CY - S * 0.3));
            Close_Path (Cr);
            Stroke (Cr);
      end case;
   end Icon;

   ---------------------------------------------------------------------------
   --  The race
   ---------------------------------------------------------------------------

   --  The map: the track drawn once into a picture of its own, the cars on it
   Map_Surface : Cairo_Surface := Null_Surface;
   Map_Track : Natural := 0;
   Map_Size : Natural := 0;
   Map_Serial : Natural := 0;
   Min_X, Max_X, Min_Z, Max_Z : Float := 0.0;
   Map_Span : Float := 1.0;
   Loads : Natural := 0;   --  tracks set up since the start (the same track again is new too)

   procedure Track_Changed is
   begin
      Loads := Loads + 1;
   end Track_Changed;

   procedure Minimap (X0, Y0, Size : Float) is
      N : constant Positive := Track.Count;
      Span : Float := Map_Span;
      function MX (X : Float) return Gdouble is (Gdouble ((X - Min_X) / Span * Size));
      function MY (Z : Float) return Gdouble is (Gdouble ((Z - Min_Z) / Span * Size));
      Pix : constant Natural := Natural (Size) + 1;
   begin
      if Map_Track /= Natural (Track.Current) or else Map_Size /= Pix or else Map_Serial /= Loads then
         Map_Track := Natural (Track.Current);
         Map_Size := Pix;
         Map_Serial := Loads;
         Min_X := Float'Last;
         Max_X := Float'First;
         Min_Z := Float'Last;
         Max_Z := Float'First;
         for I in 0 .. N - 1 loop
            declare
               C : constant Vec3 := Track.Get (I).C;
            begin
               Min_X := Float'Min (Min_X, C.X);
               Max_X := Float'Max (Max_X, C.X);
               Min_Z := Float'Min (Min_Z, C.Z);
               Max_Z := Float'Max (Max_Z, C.Z);
            end;
         end loop;
         Span := Float'Max (Max_X - Min_X, Max_Z - Min_Z);
         --  a margin round it
         Min_X := Min_X - 0.04 * Span;
         Min_Z := Min_Z - 0.04 * Span;
         Span := Span * 1.08;
         Map_Span := Span;
         if Map_Surface /= Null_Surface then
            Cairo.Surface.Destroy (Map_Surface);
         end if;
         Map_Surface := Cairo.Image_Surface.Create
           (Cairo.Image_Surface.Cairo_Format_ARGB32, Gint (Pix), Gint (Pix));
         declare
            Main : constant Cairo_Context := Cr;
         begin
            Cr := Create (Map_Surface);
            Set_Line_Cap (Cr, Cairo_Line_Cap_Round);
            Set_Line_Join (Cr, Cairo_Line_Join_Round);
            for Pass in 1 .. 2 loop
               New_Path (Cr);
               for I in 0 .. N loop
                  if I mod 3 = 0 or else I = N then
                     declare
                        C : constant Vec3 := Track.Get (I).C;
                     begin
                        if I = 0 then
                           Move_To (Cr, MX (C.X), MY (C.Z));
                        else
                           Line_To (Cr, MX (C.X), MY (C.Z));
                        end if;
                     end;
                  end if;
               end loop;
               Close_Path (Cr);
               if Pass = 1 then
                  Set_Line_Width (Cr, D (9.0));
                  Color (0.0, 0.0, 0.0, 0.5);
               else
                  Set_Line_Width (Cr, D (4.0));
                  Color (0.9, 0.92, 1.0, 0.85);
               end if;
               Stroke (Cr);
            end loop;
            --  Where the tunnels are
            Set_Line_Width (Cr, D (4.0));
            Color (0.4, 0.4, 0.45, 1.0);
            New_Path (Cr);
            for I in 0 .. N - 1 loop
               if Track.Get (I).P.Roof > 0.5 then
                  declare
                     A : constant Vec3 := Track.Get (I).C;
                     B : constant Vec3 := Track.Get (I + 1).C;
                  begin
                     Move_To (Cr, MX (A.X), MY (A.Z));
                     Line_To (Cr, MX (B.X), MY (B.Z));
                  end;
               end if;
            end loop;
            Stroke (Cr);
            declare
               S : constant Vec3 := Track.Get (0).C;
            begin
               Color (1.0, 1.0, 1.0);
               New_Path (Cr);
               Arc (Cr, MX (S.X), MY (S.Z), D (5.0), 0.0, Gdouble (2.0 * Pi));
               Fill (Cr);
            end;
            Destroy (Cr);
            Cr := Main;
         end;
      end if;
      Set_Source_Surface (Cr, Map_Surface, Gdouble (X0), Gdouble (Y0));
      Paint (Cr);
      Span := Map_Span;
      for I in reverse 1 .. Race.State.Count loop
         declare
            C : constant Vec3 := Race.State.Racers (I).Car.P;
            R : constant Float := (if I = Race.Player and then not Race.State.Attract then 8.0 else 5.5);
            PX : constant Gdouble := Gdouble (X0) + MX (C.X);
            PY : constant Gdouble := Gdouble (Y0) + MY (C.Z);
         begin
            New_Path (Cr);
            Arc (Cr, PX, PY, D (R + 2.0), 0.0, Gdouble (2.0 * Pi));
            Color (0.0, 0.0, 0.0, 0.8);
            Fill (Cr);
            New_Path (Cr);
            Arc (Cr, PX, PY, D (R), 0.0, Gdouble (2.0 * Pi));
            Paint_Of (I);
            Fill (Cr);
         end;
      end loop;
   end Minimap;

   procedure Draw_Race (W, H : Float; O : Overlay) is
      Me : Race.Racer renames Race.State.Racers (Race.Player);
      Pad : constant Float := 28.0 * Scale;
   begin
      --  Place and lap
      Panel (Pad, Pad, 250.0 * Scale, 150.0 * Scale);
      Color (1.0, 1.0, 1.0);
      Font (78.0);
      Text (Img (Me.Place), Pad + 18.0 * Scale, Pad + 88.0 * Scale);
      Font (30.0);
      Color (0.75, 0.8, 0.9);
      Text ("/" & Img (Natural (Race.State.Count)), Pad + 18.0 * Scale + Width_Of ("0") * 2.6,
            Pad + 88.0 * Scale);
      Font (28.0);
      Color (1.0, 0.85, 0.3);
      Text ("LAP " & Img (Race.Lap_Shown (Race.Player)) & "/" & Img (Race.State.Laps),
            Pad + 20.0 * Scale, Pad + 132.0 * Scale);

      --  Times
      declare
         X : constant Float := W - Pad - 300.0 * Scale;
         Now : constant Float :=
           (if Me.Finished then Me.Finish_T else Float'Max (0.0, Race.State.Clock));
      begin
         Panel (X, Pad, 300.0 * Scale, 150.0 * Scale);
         Font (40.0);
         Color (1.0, 1.0, 1.0);
         Text (Time_Of (Now), X + 280.0 * Scale, Pad + 56.0 * Scale, 1);
         Font (22.0, Italic => False);
         Color (0.75, 0.8, 0.9);
         Text ("LAP  " & Time_Of (Now - Me.Lap_Start), X + 280.0 * Scale, Pad + 92.0 * Scale, 1);
         Text ("BEST " & (if Me.Best_Lap > 0.0 then Time_Of (Me.Best_Lap) else "-:--.--"),
               X + 280.0 * Scale, Pad + 124.0 * Scale, 1);
      end;

      --  The order
      declare
         Y : Float := Pad + 175.0 * Scale;
      begin
         for P in 1 .. Natural (Race.State.Count) loop
            for I in 1 .. Race.State.Count loop
               if Race.State.Racers (I).Place = P then
                  declare
                     Mine : constant Boolean := I = Race.Player;
                  begin
                     Panel (Pad, Y, 200.0 * Scale, 30.0 * Scale, (if Mine then 0.7 else 0.35));
                     Paint_Of (I);
                     Rectangle (Cr, Gdouble (Pad + 6.0 * Scale), Gdouble (Y + 6.0 * Scale), D (6.0), D (18.0));
                     Fill (Cr);
                     Font (18.0, Italic => False, Bold => Mine);
                     Color (1.0, 1.0, 1.0, (if Mine then 1.0 else 0.8));
                     Text (Img (P) & "  " & Race.State.Racers (I).Name, Pad + 20.0 * Scale,
                           Y + 22.0 * Scale, Shadow => False);
                  end;
               end if;
            end loop;
            Y := Y + 34.0 * Scale;
         end loop;
      end;

      --  Speed and the weapon
      declare
         CX : constant Float := Pad + 120.0 * Scale;
         CY : constant Float := H - Pad - 110.0 * Scale;
         Kmh : constant Float := Me.Car.Speed * 3.6;
         Frac : constant Float := Float'Min (1.0, Kmh / 300.0);
      begin
         Panel (Pad, H - Pad - 220.0 * Scale, 240.0 * Scale, 220.0 * Scale);
         Set_Line_Width (Cr, D (12.0));
         Set_Line_Cap (Cr, Cairo_Line_Cap_Round);
         Color (1.0, 1.0, 1.0, 0.15);
         New_Path (Cr);
         Arc (Cr, Gdouble (CX), Gdouble (CY), D (82.0), Gdouble (0.75 * Pi), Gdouble (2.25 * Pi));
         Stroke (Cr);
         if Me.Car.Boost_T > 0.0 then
            Color (1.0, 0.45, 0.1);
         else
            Color (0.3, 0.85, 1.0);
         end if;
         New_Path (Cr);
         Arc (Cr, Gdouble (CX), Gdouble (CY), D (82.0), Gdouble (0.75 * Pi),
              Gdouble (0.75 * Pi + 1.5 * Pi * Frac));
         Stroke (Cr);
         Font (54.0);
         Color (1.0, 1.0, 1.0);
         Text (Img (Integer (Kmh)), CX, CY + 18.0 * Scale, 0);
         Font (16.0, Italic => False);
         Color (0.7, 0.75, 0.85);
         Text ("KM/H", CX, CY + 44.0 * Scale, 0);
         if Me.Car.Shield_T > 0.0 then
            Font (18.0);
            Color (0.3, 0.9, 1.0);
            Text ("SHIELD", CX, CY + 92.0 * Scale, 0);
         end if;
      end;
      declare
         BX : constant Float := W / 2.0 - 70.0 * Scale;
         BY : constant Float := H - Pad - 140.0 * Scale;
      begin
         Panel (BX, BY, 140.0 * Scale, 140.0 * Scale, 0.5);
         if Me.Held /= Race.None then
            Icon (Me.Held, W / 2.0, BY + 60.0 * Scale, 80.0 * Scale);
            Font (17.0);
            Color (1.0, 1.0, 1.0);
            Text (Race.Weapon_Name (Me.Held), W / 2.0, BY + 125.0 * Scale, 0);
         else
            Font (15.0, Italic => False);
            Color (1.0, 1.0, 1.0, 0.4);
            Text ("NO WEAPON", W / 2.0, BY + 76.0 * Scale, 0);
         end if;
      end;

      --  The map
      declare
         Size : constant Float := 260.0 * Scale;
      begin
         Panel (W - Pad - Size - 20.0 * Scale, H - Pad - Size - 20.0 * Scale, Size + 20.0 * Scale,
                Size + 20.0 * Scale, 0.35);
         Minimap (W - Pad - Size - 10.0 * Scale, H - Pad - Size - 10.0 * Scale, Size);
      end;

      --  The start, and what is said
      if Race.State.Phase = Race.Countdown then
         declare
            T : constant Float := -Race.State.Clock;
            N : constant Integer := Integer (Float'Ceiling (T));
            F : constant Float := T - Float'Floor (T);
         begin
            if N <= 3 then
               Font (170.0 + 60.0 * F);
               Color (1.0, 0.85 - 0.25 * Float (N), 0.2, 0.4 + 0.6 * F);
               Text (Img (N), W / 2.0, H * 0.42, 0);
            else
               Font (44.0);
               Color (1.0, 1.0, 1.0);
               Text (Track.Name (Track.Current), W / 2.0, H * 0.33, 0);
            end if;
         end;
      elsif Race.State.Clock < 1.2 and then Race.State.Phase = Race.Running then
         Font (180.0);
         Color (0.3, 1.0, 0.4, 1.0 - Race.State.Clock / 1.2);
         Text ("GO!", W / 2.0, H * 0.42, 0);
      end if;
      if Me.Wrong_Way > 1.5 and then Race.State.Phase = Race.Running then
         Font (60.0);
         Color (1.0, 0.25, 0.2);
         Text ("WRONG WAY", W / 2.0, H * 0.3, 0);
      end if;
      if Race.State.Phase = Race.Over then
         Font (90.0);
         Color (1.0, 0.85, 0.3);
         Text ("FINISHED " & Ordinal (Me.Place), W / 2.0, H * 0.36, 0);
      end if;
      if O.Message_T > 0.0 then
         Font (46.0);
         Color (1.0, 1.0, 1.0, Float'Min (1.0, O.Message_T * 2.0));
         Text (To_String (O.Message), W / 2.0, H * 0.24, 0);
      end if;
   end Draw_Race;

   procedure Draw_Items (W, Y0 : Float; O : Overlay) is
      Y : Float := Y0;
      BW : constant Float := 560.0 * Scale;
   begin
      for K in 1 .. O.Item_Count loop
         declare
            On : constant Boolean := K = O.Selected;
         begin
            Rounded (W / 2.0 - BW / 2.0, Y, BW, 54.0 * Scale, 12.0 * Scale);
            if On then
               Color (1.0, 0.5, 0.1, 0.9);
            else
               Color (0.02, 0.03, 0.06, 0.6);
            end if;
            Fill (Cr);
            Font (26.0, Italic => False);
            Color (1.0, 1.0, 1.0, (if On then 1.0 else 0.85));
            if Length (O.Items (K).Value) > 0 then
               Text (To_String (O.Items (K).Label), W / 2.0 - BW / 2.0 + 24.0 * Scale, Y + 37.0 * Scale,
                     Shadow => False);
               Font (26.0);
               Text ((if On then "<  " else "") & To_String (O.Items (K).Value) & (if On then "  >" else ""),
                     W / 2.0 + BW / 2.0 - 24.0 * Scale, Y + 37.0 * Scale, 1, Shadow => False);
            else
               Font (28.0);
               Text (To_String (O.Items (K).Label), W / 2.0, Y + 37.0 * Scale, 0, Shadow => False);
            end if;
         end;
         Y := Y + 64.0 * Scale;
      end loop;
   end Draw_Items;

   procedure Draw_Title (W, H : Float; O : Overlay) is
   begin
      Color (0.0, 0.0, 0.02, 0.35);
      Rectangle (Cr, 0.0, 0.0, Gdouble (W), Gdouble (H));
      Fill (Cr);
      Font (150.0);
      Color (1.0, 0.5, 0.1);
      Text ("ADAFLIP", W / 2.0, H * 0.22, 0);
      Font (28.0, Bold => False);
      Color (1.0, 1.0, 1.0, 0.9);
      Text ("combat racing on every side of the track", W / 2.0, H * 0.22 + 52.0 * Scale, 0);
      Draw_Items (W, H * 0.36, O);
   end Draw_Title;

   procedure Draw_Results (W, H : Float; O : Overlay) is
      Y : Float := H * 0.22;
      BW : constant Float := 760.0 * Scale;
      X0 : constant Float := W / 2.0 - BW / 2.0;
   begin
      Color (0.0, 0.0, 0.02, 0.5);
      Rectangle (Cr, 0.0, 0.0, Gdouble (W), Gdouble (H));
      Fill (Cr);
      Font (72.0);
      Color (1.0, 0.85, 0.3);
      Text ("RESULTS", W / 2.0, H * 0.16, 0);
      Font (20.0, Italic => False);
      Color (0.7, 0.75, 0.85);
      Text ("TIME", X0 + 470.0 * Scale, Y + 10.0 * Scale, 1, Shadow => False);
      Text ("BEST LAP", X0 + 650.0 * Scale, Y + 10.0 * Scale, 1, Shadow => False);
      Y := Y + 22.0 * Scale;
      for P in 1 .. Natural (Race.State.Count) loop
         for I in 1 .. Race.State.Count loop
            declare
               R : Race.Racer renames Race.State.Racers (I);
            begin
               if R.Place = P then
                  Panel (X0, Y, BW, 46.0 * Scale, (if I = Race.Player then 0.85 else 0.55));
                  Paint_Of (I);
                  Rectangle (Cr, Gdouble (X0 + 10.0 * Scale), Gdouble (Y + 9.0 * Scale), D (8.0), D (28.0));
                  Fill (Cr);
                  Font (26.0);
                  Color (1.0, 1.0, 1.0);
                  Text (Img (P), X0 + 34.0 * Scale, Y + 33.0 * Scale, Shadow => False);
                  Text (R.Name, X0 + 90.0 * Scale, Y + 33.0 * Scale, Shadow => False);
                  Font (24.0, Italic => False);
                  Text ((if R.Finished then Time_Of (R.Finish_T) else "racing"),
                        X0 + 470.0 * Scale, Y + 33.0 * Scale, 1, Shadow => False);
                  Text ((if R.Best_Lap > 0.0 then Time_Of (R.Best_Lap) else "-"),
                        X0 + 650.0 * Scale, Y + 33.0 * Scale, 1, Shadow => False);
                  Font (16.0, Italic => False, Bold => False);
                  Color (1.0, 0.6, 0.4);
                  Text (Img (R.Hits) & " hits", X0 + BW - 14.0 * Scale, Y + 30.0 * Scale, 1, Shadow => False);
               end if;
            end;
         end loop;
         Y := Y + 52.0 * Scale;
      end loop;
      Draw_Items (W, Y + 24.0 * Scale, O);
   end Draw_Results;

   procedure Draw (Width, Height : Natural; O : Overlay) is
      W : constant Float := Float (Width);
      H : constant Float := Float (Height);
   begin
      if Width = 0 or else Height = 0 then
         return;
      end if;
      if Width /= Surf_W or else Height /= Surf_H then
         if Cr /= Null_Context then
            Destroy (Cr);
            Cairo.Surface.Destroy (Surface);
         end if;
         Surface := Cairo.Image_Surface.Create (Cairo.Image_Surface.Cairo_Format_ARGB32, Gint (Width), Gint (Height));
         Cr := Create (Surface);
         Surf_W := Width;
         Surf_H := Height;
      end if;
      Scale := Float'Max (0.5, H / 1080.0);
      Save (Cr);
      Set_Operator (Cr, Cairo_Operator_Clear);
      Paint (Cr);
      Restore (Cr);

      case O.Mode is
         when Title =>
            Draw_Title (W, H, O);
         when Racing =>
            Draw_Race (W, H, O);
         when Paused =>
            Draw_Race (W, H, O);
            Color (0.0, 0.0, 0.02, 0.55);
            Rectangle (Cr, 0.0, 0.0, Gdouble (W), Gdouble (H));
            Fill (Cr);
            Font (90.0);
            Color (1.0, 1.0, 1.0);
            Text ("PAUSED", W / 2.0, H * 0.3, 0);
            Draw_Items (W, H * 0.38, O);
         when Results =>
            Draw_Results (W, H, O);
      end case;
      if Length (O.Hint) > 0 then
         Font (17.0, Italic => False, Bold => False);
         Color (1.0, 1.0, 1.0, 0.6);
         Text (To_String (O.Hint), W / 2.0, H - 14.0 * Scale, 0);
      end if;
      if O.Show_Fps then
         Font (14.0, Italic => False, Bold => False);
         Color (1.0, 1.0, 0.4);
         Text (Img (Integer (O.Fps)) & " fps", 8.0, H - 8.0);
      end if;

      Cairo.Surface.Flush (Surface);
      Hud_Layer.Draw (Cairo.Image_Surface.Get_Data_Generic (Surface), Width, Height,
                      Natural (Cairo.Image_Surface.Get_Stride (Surface)), 0, 0, Width, Height);
   end Draw;

end Hud;
