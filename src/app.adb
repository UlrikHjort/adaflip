--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Real_Time;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces;
with System;

with Gdk;
with Gdk.Event;
with Gdk.Frame_Clock;
with Gdk.Types;
with Gdk.Types.Keysyms;
with Glib; use Glib;
with Gtk.Main;
with Gtk.Widget;
with Gtk.Window;

with Audio;
with Gamepad;
with GL;
with GL_Area;
with Hud;
with Hud_Layer;
with Math3D; use Math3D;
with Race;
with Renderer;
with Track;
with Vehicle;

package body App is

   use type Gdk.Types.Gdk_Key_Type;
   use type Gamepad.Button;
   use type Race.Phase_Kind;
   use type Race.Event_Kind;
   use type Race.Weapon;
   use type Hud.Screen;
   use type Renderer.Camera_Kind;

   Window : Gtk.Window.Gtk_Window;
   procedure Set_Frame_Sync (W : Gdk.Gdk_Window; On : Gboolean)
     with Import, Convention => C, External_Name => "gdk_x11_window_set_frame_sync_enabled";
   Area   : GL_Area.Gtk_GL_Area;
   Ready  : Boolean := False;
   Is_Fullscreen : Boolean := False;

   Mode : Hud.Screen := Hud.Title;
   Selected : Positive := 1;
   Overlay : Hud.Overlay;
   View : Renderer.View;

   --  The choices in the menu
   Track_Sel : Track.Track_Id := 1;
   Opponents : Positive := 5;
   Laps : Positive := 3;
   Level : Race.Difficulty := Race.Normal;
   Camera : Renderer.Camera_Kind := Renderer.Chase;

   --  The keyboard
   type Key_State is record
      Left, Right, Up, Down, Back_View : Boolean := False;
   end record;
   Keys : Key_State;
   Fire_Pending, Reset_Pending : Boolean := False;

   Accum : Float := 0.0;
   New_World : Boolean := False;   --  the scenery is built where GL is current
   Last_Time : Ada.Real_Time.Time := Ada.Real_Time.Clock;
   Events_Read : Natural := 0;
   Attract_Focus_T : Float := 0.0;
   Fps : Float := 60.0;
   Show_Fps : Boolean := False;
   Stick_Was : Integer := 0;
   Rumble_Hard, Rumble_Soft : Float := 0.0;
   Volume : Float := 0.8;

   --  Automated checks: start at once, write a picture and quit
   Shot_File : Unbounded_String;
   Shot_Frame : Natural := 0;
   Frame_Count : Natural := 0;
   Autopilot : Boolean := False;
   Skip_Seconds : Float := 0.0;
   Profile : Boolean := False;
   Time_Scene, Time_Hud, Time_Sim : Float := 0.0;

   function Env (N : String) return String is
     (if Ada.Environment_Variables.Exists (N) then Ada.Environment_Variables.Value (N) else "");

   procedure Say (S : String; Seconds : Float := 2.0) is
   begin
      Overlay.Message := To_Unbounded_String (S);
      Overlay.Message_T := Seconds;
   end Say;

   function Trim (S : String) return String is
     (if S'Length > 0 and then S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);

   function Name_Of (N : String) return String is
      Last : Natural := N'Last;
   begin
      while Last >= N'First and then N (Last) = ' ' loop
         Last := Last - 1;
      end loop;
      return N (N'First .. Last);
   end Name_Of;

   ---------------------------------------------------------------------------
   --  Remembered choices, in ~/.adafliprc
   ---------------------------------------------------------------------------

   function Rc_File return String is (Env ("HOME") & "/.adafliprc");

   procedure Save_Choices is
      use Ada.Text_IO;
      F : File_Type;
   begin
      Create (F, Out_File, Rc_File);
      Put_Line (F, "track" & Integer'Image (Track_Sel));
      Put_Line (F, "opponents" & Integer'Image (Opponents));
      Put_Line (F, "laps" & Integer'Image (Laps));
      Put_Line (F, "level" & Integer'Image (Race.Difficulty'Pos (Level)));
      Put_Line (F, "camera" & Integer'Image (Renderer.Camera_Kind'Pos (Camera)));
      Close (F);
   exception
      when others => null;
   end Save_Choices;

   procedure Load_Choices is
      use Ada.Text_IO;
      F : File_Type;
   begin
      if not Ada.Directories.Exists (Rc_File) then
         return;
      end if;
      Open (F, In_File, Rc_File);
      while not End_Of_File (F) loop
         declare
            L : constant String := Get_Line (F);
            Sp : Natural := 0;
         begin
            for I in L'Range loop
               if L (I) = ' ' then
                  Sp := I;
                  exit;
               end if;
            end loop;
            if Sp > 0 then
               declare
                  K : constant String := L (L'First .. Sp - 1);
                  V : constant Integer := Integer'Value (L (Sp + 1 .. L'Last));
               begin
                  if K = "track" and then V in Track.Track_Id then
                     Track_Sel := V;
                  elsif K = "opponents" and then V in 1 .. Race.Max_Cars - 1 then
                     Opponents := V;
                  elsif K = "laps" and then V in 1 .. 9 then
                     Laps := V;
                  elsif K = "level" and then V in 0 .. 2 then
                     Level := Race.Difficulty'Val (V);
                  elsif K = "camera" and then V in 0 .. 2 then
                     Camera := Renderer.Camera_Kind'Val (V);
                  end if;
               end;
            end if;
         exception
            when others => null;
         end;
      end loop;
      Close (F);
   exception
      when others => null;
   end Load_Choices;

   ---------------------------------------------------------------------------
   --  The screens
   ---------------------------------------------------------------------------

   function Camera_Name (C : Renderer.Camera_Kind) return String is
     (case C is
         when Renderer.Chase => "CHASE",
         when Renderer.Far_Chase => "FAR",
         when Renderer.Bumper => "BUMPER");

   procedure Fill_Items is
      procedure Put (K : Positive; L : String; V : String := "") is
      begin
         Overlay.Items (K) := (To_Unbounded_String (L), To_Unbounded_String (V));
      end Put;
   begin
      case Mode is
         when Hud.Title =>
            Put (1, "START RACE");
            Put (2, "TRACK", Track.Name (Track_Sel));
            Put (3, "OPPONENTS", Trim (Opponents'Image));
            Put (4, "LAPS", Trim (Laps'Image));
            Put (5, "DIFFICULTY", Race.Difficulty'Image (Level));
            Put (6, "CAMERA", Camera_Name (Camera));
            Put (7, "QUIT");
            Overlay.Item_Count := 7;
            Overlay.Hint := To_Unbounded_String
              ((if Gamepad.Present then "D-pad: choose    A: select    " else "")
               & "Arrows: choose    Enter: select    F11: full screen");
         when Hud.Paused =>
            Put (1, "RESUME");
            Put (2, "RESTART");
            Put (3, "CAMERA", Camera_Name (Camera));
            Put (4, "QUIT TO MENU");
            Overlay.Item_Count := 4;
            Overlay.Hint := Null_Unbounded_String;
         when Hud.Results =>
            Put (1, "RACE AGAIN");
            Put (2, "MENU");
            Overlay.Item_Count := 2;
            Overlay.Hint := Null_Unbounded_String;
         when Hud.Racing =>
            Overlay.Item_Count := 0;
            Overlay.Hint := Null_Unbounded_String;
      end case;
      Selected := Positive'Min (Selected, Positive'Max (1, Overlay.Item_Count));
      Overlay.Selected := Selected;
      Overlay.Mode := Mode;
   end Fill_Items;

   procedure Start_Attract is
   begin
      Race.Setup (Track_Sel, 5, 3, Race.Normal, Attract => True);
      --  Some way in, so the cars are spread out and racing
      for K in 1 .. Natural (6.0 / Race.Dt) loop
         Race.Step ((others => <>), Player_AI => True);
      end loop;
      New_World := True;
      Events_Read := Race.Event_Serial;
      View := (Camera => Renderer.Chase, Orbit => True, Focus => 1, others => <>);
      Attract_Focus_T := 0.0;
   end Start_Attract;

   procedure Start_Race is
   begin
      Race.Setup (Track_Sel, Opponents, Laps, Level, Attract => False);
      New_World := True;
      Events_Read := Race.Event_Serial;
      View := (Camera => Camera, Orbit => False, Focus => Race.Player, others => <>);
      Mode := Hud.Racing;
      Accum := 0.0;
      Fire_Pending := False;
      Reset_Pending := False;
      Overlay.Message_T := 0.0;
      Fill_Items;
      Save_Choices;
   end Start_Race;

   procedure To_Title is
   begin
      Mode := Hud.Title;
      Selected := 1;
      Start_Attract;
      Fill_Items;
   end To_Title;

   procedure Change (Dir : Integer) is
   begin
      if Mode = Hud.Title then
         case Selected is
            when 2 =>
               Track_Sel := (if Dir > 0 then (if Track_Sel = Track.Track_Count then 1 else Track_Sel + 1)
                             else (if Track_Sel = 1 then Track.Track_Count else Track_Sel - 1));
               Start_Attract;
            when 3 =>
               Opponents := Positive'Max (1, Positive'Min (Race.Max_Cars - 1, Opponents + Dir));
            when 4 =>
               Laps := Positive'Max (1, Positive'Min (9, Laps + Dir));
            when 5 =>
               Level := Race.Difficulty'Val
                 ((Race.Difficulty'Pos (Level) + Dir + 3) mod 3);
            when 6 =>
               Camera := Renderer.Camera_Kind'Val ((Renderer.Camera_Kind'Pos (Camera) + Dir + 3) mod 3);
            when others => null;
         end case;
      elsif Mode = Hud.Paused and then Selected = 3 then
         Camera := Renderer.Camera_Kind'Val ((Renderer.Camera_Kind'Pos (Camera) + Dir + 3) mod 3);
         View.Camera := Camera;
      end if;
      Fill_Items;
   end Change;

   procedure Choose is
   begin
      case Mode is
         when Hud.Title =>
            case Selected is
               when 1 => Start_Race;
               when 7 => Gtk.Main.Main_Quit;
               when others => Change (1);
            end case;
         when Hud.Paused =>
            case Selected is
               when 1 =>
                  Mode := Hud.Racing;
               when 2 =>
                  Start_Race;
               when 3 =>
                  Change (1);
               when others =>
                  To_Title;
            end case;
         when Hud.Results =>
            if Selected = 1 then
               Start_Race;
            else
               To_Title;
            end if;
         when Hud.Racing => null;
      end case;
      Fill_Items;
   end Choose;

   procedure Menu_Move (Dir : Integer) is
   begin
      if Overlay.Item_Count > 0 then
         Selected := (if Dir > 0 then (if Selected >= Overlay.Item_Count then 1 else Selected + 1)
                      else (if Selected = 1 then Overlay.Item_Count else Selected - 1));
         Fill_Items;
      end if;
   end Menu_Move;

   procedure Toggle_Pause is
   begin
      if Mode = Hud.Racing then
         Mode := Hud.Paused;
         Selected := 1;
      elsif Mode = Hud.Paused then
         Mode := Hud.Racing;
      end if;
      Fill_Items;
   end Toggle_Pause;

   procedure Next_Camera is
   begin
      Camera := Renderer.Camera_Kind'Val ((Renderer.Camera_Kind'Pos (Camera) + 1) mod 3);
      View.Camera := Camera;
      Say (Camera_Name (Camera) & " CAMERA", 1.0);
   end Next_Camera;

   ---------------------------------------------------------------------------
   --  Input
   ---------------------------------------------------------------------------

   function Key_Press (Self : access Gtk.Widget.Gtk_Widget_Record'Class;
                       Event : Gdk.Event.Gdk_Event_Key) return Boolean
   is
      pragma Unreferenced (Self);
      use Gdk.Types.Keysyms;
      K : constant Gdk.Types.Gdk_Key_Type := Event.Keyval;
   begin
      if K = GDK_F11 then
         Is_Fullscreen := not Is_Fullscreen;
         if Is_Fullscreen then
            Window.Fullscreen;
         else
            Window.Unfullscreen;
         end if;
         return True;
      elsif K = GDK_F3 then
         Show_Fps := not Show_Fps;
         return True;
      end if;
      if Mode /= Hud.Racing then
         if K = GDK_Up or else K = GDK_LC_w then Menu_Move (-1);
         elsif K = GDK_Down or else K = GDK_LC_s then Menu_Move (1);
         elsif K = GDK_Left or else K = GDK_LC_a then Change (-1);
         elsif K = GDK_Right or else K = GDK_LC_d then Change (1);
         elsif K = GDK_Return or else K = GDK_KP_Enter or else K = GDK_space then Choose;
         elsif K = GDK_Escape then
            if Mode = Hud.Title then
               Gtk.Main.Main_Quit;
            elsif Mode = Hud.Paused then
               Toggle_Pause;
            else
               To_Title;
            end if;
         else
            return False;
         end if;
         return True;
      end if;
      if K = GDK_Left or else K = GDK_LC_a then Keys.Left := True;
      elsif K = GDK_Right or else K = GDK_LC_d then Keys.Right := True;
      elsif K = GDK_Up or else K = GDK_LC_w then Keys.Up := True;
      elsif K = GDK_Down or else K = GDK_LC_s then Keys.Down := True;
      elsif K = GDK_space or else K = GDK_Control_L or else K = GDK_Control_R then
         Fire_Pending := True;
      elsif K = GDK_LC_b then Keys.Back_View := True;
      elsif K = GDK_LC_c then Next_Camera;
      elsif K = GDK_LC_r then Reset_Pending := True;
      elsif K = GDK_Escape or else K = GDK_LC_p then Toggle_Pause;
      else
         return False;
      end if;
      return True;
   end Key_Press;

   function Key_Release (Self : access Gtk.Widget.Gtk_Widget_Record'Class;
                         Event : Gdk.Event.Gdk_Event_Key) return Boolean
   is
      pragma Unreferenced (Self);
      use Gdk.Types.Keysyms;
      K : constant Gdk.Types.Gdk_Key_Type := Event.Keyval;
   begin
      if K = GDK_Left or else K = GDK_LC_a then Keys.Left := False;
      elsif K = GDK_Right or else K = GDK_LC_d then Keys.Right := False;
      elsif K = GDK_Up or else K = GDK_LC_w then Keys.Up := False;
      elsif K = GDK_Down or else K = GDK_LC_s then Keys.Down := False;
      elsif K = GDK_LC_b then Keys.Back_View := False;
      else
         return False;
      end if;
      return True;
   end Key_Release;

   procedure Pad_Buttons is
      B : Gamepad.Button;
      Pad : constant Gamepad.Input := Gamepad.State;
      Stick : constant Integer := (if Pad.Stick_Y < -0.6 then -1 elsif Pad.Stick_Y > 0.6 then 1 else 0);
      Stick_X : constant Integer := (if Pad.Steer < -0.7 then -1 elsif Pad.Steer > 0.7 then 1 else 0);
   begin
      while Gamepad.Next_Press (B) loop
         if Mode = Hud.Racing then
            case B is
               when Gamepad.A | Gamepad.RB => Fire_Pending := True;
               when Gamepad.X => Reset_Pending := True;
               when Gamepad.Y | Gamepad.Back => Next_Camera;
               when Gamepad.Start => Toggle_Pause;
               when others => null;
            end case;
         else
            case B is
               when Gamepad.Pad_Up => Menu_Move (-1);
               when Gamepad.Pad_Down => Menu_Move (1);
               when Gamepad.Pad_Left => Change (-1);
               when Gamepad.Pad_Right => Change (1);
               when Gamepad.A => Choose;
               when Gamepad.Start =>
                  if Mode = Hud.Paused then
                     Toggle_Pause;
                  else
                     Choose;
                  end if;
               when Gamepad.B =>
                  if Mode = Hud.Paused then
                     Toggle_Pause;
                  elsif Mode = Hud.Results then
                     To_Title;
                  end if;
               when others => null;
            end case;
         end if;
      end loop;
      --  The stick works the menus too
      if Mode /= Hud.Racing then
         if Stick /= 0 and then Stick_Was /= Stick then
            Menu_Move (Stick);
         end if;
         if Stick_X /= 0 and then Stick_Was /= 10 * Stick_X then
            Change (Stick_X);
         end if;
      end if;
      Stick_Was := (if Stick /= 0 then Stick elsif Stick_X /= 0 then 10 * Stick_X else 0);
   end Pad_Buttons;

   function Player_Input return Race.Player_Input is
      I : Race.Player_Input;
      Pad : constant Gamepad.Input := Gamepad.State;
      Steer : Float := Pad.Steer;
   begin
      if Keys.Left then
         Steer := Steer - 1.0;
      end if;
      if Keys.Right then
         Steer := Steer + 1.0;
      end if;
      I.Drive.Steer := Clamp (Steer, -1.0, 1.0);
      I.Drive.Throttle := Float'Max (Pad.Throttle, (if Keys.Up then 1.0 else 0.0));
      I.Drive.Brake := Float'Max (Pad.Brake, (if Keys.Down then 1.0 else 0.0));
      I.Fire := Fire_Pending;
      I.Reset := Reset_Pending;
      return I;
   end Player_Input;

   ---------------------------------------------------------------------------
   --  What happened: sound, words and rumble
   ---------------------------------------------------------------------------

   procedure Hear_Events is
      use Race;
      From : Natural := Events_Read;
      Cam : constant Vec3 := Renderer.Camera_Position;
      Right : constant Vec3 := Renderer.Camera_Right;
      Racing : constant Boolean := not State.Attract;

      procedure Near (E : Event; Fx : Audio.Effect; Gain : Float := 1.0) is
         D : constant Vec3 := E.P - Cam;
         L : constant Float := Length (D);
      begin
         Audio.Play (Fx, Gain / (1.0 + L / 35.0),
                     (if L > 0.5 then Clamp (Dot (D, Right) / L, -1.0, 1.0) else 0.0));
      end Near;
   begin
      if Event_Serial - From > Event_Ring then
         From := Event_Serial - Event_Ring;
      end if;
      for K in From .. Event_Serial - 1 loop
         declare
            E : constant Event := Events (K mod Event_Ring);
            Mine : constant Boolean := Racing and then E.Car = Player;
         begin
            case E.Kind is
               when Explosion =>
                  Near (E, Audio.Bang, 1.3);
                  if Racing and then Length (State.Racers (Player).Car.P - E.P) < 25.0 then
                     Rumble_Hard := Float'Max (Rumble_Hard, 1.0 - Length (State.Racers (Player).Car.P - E.P) / 25.0);
                  end if;
               when Bump =>
                  Near (E, Audio.Thud, Float'Min (1.0, E.Size / 20.0));
                  if Mine then
                     Rumble_Hard := Float'Max (Rumble_Hard, Float'Min (1.0, E.Size / 25.0));
                  end if;
               when Scrape =>
                  if Mine then
                     Rumble_Soft := Float'Max (Rumble_Soft, 0.5 * E.Size);
                  end if;
               when Picked =>
                  if Mine then
                     Audio.Play (Audio.Pickup, 0.9);
                     Say (Weapon_Name (E.W), 1.2);
                  else
                     Near (E, Audio.Pickup, 0.4);
                  end if;
               when Fired_Rocket => Near (E, Audio.Launch);
               when Dropped_Mine => Near (E, Audio.Drop);
               when Pulsed => Near (E, Audio.Zap, 1.2);
               when Boost_On => Near (E, Audio.Whoosh, 0.9);
               when Shield_On => Near (E, Audio.Shield, 0.9);
               when Beep =>
                  if Racing then
                     Audio.Play (Audio.Beep_Low, 0.8);
                  end if;
               when Go =>
                  if Racing then
                     Audio.Play (Audio.Beep_High, 0.9);
                  end if;
               when Lap_Done =>
                  if Mine then
                     Audio.Play (Audio.Lap, 0.8);
                     Say ("LAP " & Trim (Lap_Shown (Player)'Image), 1.5);
                  end if;
               when Final_Lap =>
                  if Mine then
                     Say ("FINAL LAP", 2.0);
                  end if;
               when Finished =>
                  if Mine then
                     Audio.Play (Audio.Lap, 1.0);
                  end if;
               when Hit_Player =>
                  if Racing then
                     if E.Car = Player then
                        Renderer.Flash := 0.45;
                        Rumble_Hard := 1.0;
                        if E.Other in 1 .. State.Count and then E.Other /= Player then
                           Say ("HIT BY " & Name_Of (State.Racers (E.Other).Name), 1.5);
                        end if;
                     elsif E.Other = Player and then E.Car in 1 .. State.Count then
                        Say ("YOU HIT " & Name_Of (State.Racers (E.Car).Name), 1.5);
                     end if;
                  end if;
               when Reset_Car => null;
            end case;
         end;
      end loop;
      Events_Read := Event_Serial;
   end Hear_Events;

   procedure Update_Sound is
      use Race;
      F : constant Car_Index := View.Focus;
      C : Vehicle.Car renames State.Racers (F).Car;
      P : Audio.Params;
      Cam : constant Vec3 := Renderer.Camera_Position;
      Best : Float := 80.0;
      In_Race : constant Boolean := Mode = Hud.Racing or else Mode = Hud.Results;
   begin
      P.Speed := C.Speed;
      P.Throttle := (if State.Racers (F).AI or else Autopilot or else not In_Race
                     then 0.8 else Player_Input.Drive.Throttle);
      P.Boost := C.Boost_T > 0.0;
      P.Air := C.Grounded = 0;
      P.Scrape := C.Scrape;
      P.Slip := C.Slip;
      for I in 1 .. State.Count loop
         if I /= F then
            declare
               D : constant Vec3 := State.Racers (I).Car.P - Cam;
               L : constant Float := Length (D);
            begin
               if L < Best then
                  Best := L;
                  P.Other_Speed := State.Racers (I).Car.Speed;
                  P.Other_Level := 1.0 / (1.0 + L / 8.0);
                  P.Other_Pan := (if L > 0.5 then Clamp (Dot (D, Renderer.Camera_Right) / L, -1.0, 1.0) else 0.0);
               end if;
            end;
         end if;
      end loop;
      P.Master := (if Mode = Hud.Paused then 0.25 * Volume
                   elsif Mode = Hud.Title then 0.5 * Volume else Volume);
      Audio.Set (P);
   end Update_Sound;

   ---------------------------------------------------------------------------
   --  The frame
   ---------------------------------------------------------------------------

   procedure Write_Picture (Name : String; W, H : Natural) is
      use Ada.Streams.Stream_IO;
      use Interfaces;
      type Bytes is array (Natural range <>) of aliased Unsigned_8;
      Pix : Bytes (0 .. W * H * 4 - 1);
      F : File_Type;
      Header : constant String := "P6" & ASCII.LF & Trim (W'Image) & " " & Trim (H'Image)
        & ASCII.LF & "255" & ASCII.LF;
   begin
      GL.glPixelStorei (16#0D05#, 1);   --  GL_PACK_ALIGNMENT
      GL.glReadPixels (0, 0, GL.GLsizei (W), GL.GLsizei (H), GL.GL_RGBA, GL.GL_UNSIGNED_BYTE,
                       Pix (0)'Address);
      Create (F, Out_File, Name);
      String'Write (Stream (F), Header);
      for Y in reverse 0 .. H - 1 loop
         declare
            Row : Bytes (0 .. W * 3 - 1);
         begin
            for X in 0 .. W - 1 loop
               Row (X * 3) := Pix ((Y * W + X) * 4);
               Row (X * 3 + 1) := Pix ((Y * W + X) * 4 + 1);
               Row (X * 3 + 2) := Pix ((Y * W + X) * 4 + 2);
            end loop;
            Bytes'Write (Stream (F), Row);
         end;
      end loop;
      Close (F);
      Ada.Text_IO.Put_Line ("Wrote " & Name);
   end Write_Picture;

   procedure Step_World (Dt : Float) is
      Steps : Natural := 0;
   begin
      if Mode = Hud.Paused then
         return;
      end if;
      Accum := Accum + Dt;
      while Accum >= Race.Dt and then Steps < 60 loop
         declare
            I : Race.Player_Input := Player_Input;
         begin
            if Mode /= Hud.Racing then
               I := (others => <>);
            end if;
            Race.Step (I, Player_AI => Race.State.Attract or else Autopilot);
            Fire_Pending := False;
            Reset_Pending := False;
         end;
         Accum := Accum - Race.Dt;
         Steps := Steps + 1;
      end loop;
      if Steps = 60 then
         Accum := 0.0;
      end if;
   end Step_World;

   function Render (A, Context, Data : System.Address) return Gboolean
     with Convention => C;
   function Render (A, Context, Data : System.Address) return Gboolean is
      pragma Unreferenced (A, Context, Data);
      use Ada.Real_Time;
      Now : constant Time := Clock;
      Dt : constant Float := Float'Min (0.1, Float (To_Duration (Now - Last_Time)));
      Viewport : aliased GL.GLint_Array (0 .. 3) := (others => 0);
      T0, T1, T2 : Time;
   begin
      if not Ready then
         return 1;
      end if;
      Last_Time := Now;
      if Dt > 0.0 then
         Fps := Fps + (1.0 / Dt - Fps) * 0.05;
      end if;
      Frame_Count := Frame_Count + 1;

      Gamepad.Poll;
      Pad_Buttons;
      if New_World then
         New_World := False;
         Renderer.New_Track;
         Hud.Track_Changed;
         Events_Read := Race.Event_Serial;
         Last_Time := Ada.Real_Time.Clock;
      end if;
      Step_World (Dt);

      --  Behind the menu the camera moves from car to car
      if Race.State.Attract then
         Attract_Focus_T := Attract_Focus_T + Dt;
         if Attract_Focus_T > 12.0 then
            Attract_Focus_T := 0.0;
            View.Focus := (if View.Focus >= Race.State.Count then 1 else View.Focus + 1);
         end if;
      elsif Mode = Hud.Racing and then Race.State.Phase = Race.Over and then Race.State.Over_T > 4.0 then
         Mode := Hud.Results;
         Selected := 1;
         Fill_Items;
      end if;
      View.Look_Back := Keys.Back_View or else Gamepad.Held (Gamepad.B) or else Gamepad.Held (Gamepad.LB);
      View.Look_X := Gamepad.State.Look_X;

      GL.glGetIntegerv (GL.GL_VIEWPORT, Viewport (0)'Address);
      declare
         W : constant Natural := Natural (Viewport (2));
         H : constant Natural := Natural (Viewport (3));
      begin
         T0 := Ada.Real_Time.Clock;
         Renderer.Draw (W, H, View, Clamp (Accum / Race.Dt, 0.0, 1.0), Dt);
         T1 := Ada.Real_Time.Clock;
         Hear_Events;
         Update_Sound;
         Overlay.Message_T := Float'Max (0.0, Overlay.Message_T - Dt);
         Overlay.Fps := Fps;
         Overlay.Show_Fps := Show_Fps;
         Overlay.Mode := Mode;
         Hud.Draw (W, H, Overlay);
         T2 := Ada.Real_Time.Clock;
         if Profile then
            Time_Scene := Time_Scene + Float (To_Duration (T1 - T0));
            Time_Hud := Time_Hud + Float (To_Duration (T2 - T1));
            Time_Sim := Time_Sim + Float (To_Duration (T0 - Now));
            if Frame_Count mod 120 = 0 then
               Ada.Text_IO.Put_Line ("fps" & Integer (Fps)'Image & "  sim" & Integer (Time_Sim / 120.0 * 1.0E6)'Image
                  & " us  scene" & Integer (Time_Scene / 120.0 * 1.0E6)'Image
                  & " us  hud" & Integer (Time_Hud / 120.0 * 1.0E6)'Image & " us");
               Time_Scene := 0.0;
               Time_Hud := 0.0;
               Time_Sim := 0.0;
            end if;
         end if;
         if Shot_Frame > 0 and then Frame_Count = Shot_Frame then
            Write_Picture (To_String (Shot_File), W, H);
            Gtk.Main.Main_Quit;
         end if;
      end;

      --  The controller shakes with what hits the car
      if Mode = Hud.Racing then
         Gamepad.Rumble (Rumble_Hard, Float'Max (Rumble_Soft, Rumble_Hard * 0.5));
      else
         Gamepad.Rumble (0.0, 0.0);
      end if;
      Rumble_Hard := Float'Max (0.0, Rumble_Hard - Dt * 3.0);
      Rumble_Soft := Float'Max (0.0, Rumble_Soft - Dt * 6.0);
      return 1;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line ("Frame failed: " & Ada.Exceptions.Exception_Information (E));
         Gtk.Main.Main_Quit;
         return 1;
   end Render;

   function Tick (Widget : not null access Gtk.Widget.Gtk_Widget_Record'Class;
                  Frame_Clock : not null access Gdk.Frame_Clock.Gdk_Frame_Clock_Record'Class)
                  return Boolean
   is
      pragma Unreferenced (Widget, Frame_Clock);
   begin
      Area.Queue_Render;
      return True;
   end Tick;

   procedure Realize (Widget, Data : System.Address) with Convention => C;
   procedure Realize (Widget, Data : System.Address) is
      pragma Unreferenced (Widget, Data);
   begin
      Area.Make_Current;
      if Area.Error_Message /= "" then
         Ada.Text_IO.Put_Line ("OpenGL 4.5 is needed: " & Area.Error_Message);
         Gtk.Main.Main_Quit;
         return;
      end if;
      Renderer.Create;
      Hud_Layer.Create;
      Ready := True;
      Gamepad.Open;
      Audio.Start;
      if Env ("ADAFLIP_AUTOSTART") /= "" then
         Start_Race;
         --  Raced ahead in an instant, for pictures from later on
         for K in 1 .. Natural (Skip_Seconds / Race.Dt) loop
            Race.Step ((others => <>), Player_AI => True);
         end loop;
         Events_Read := Race.Event_Serial;
      else
         To_Title;
      end if;
      Last_Time := Ada.Real_Time.Clock;
   exception
      when E : others =>
         Ada.Text_IO.Put_Line ("Start failed: " & Ada.Exceptions.Exception_Information (E));
         Gtk.Main.Main_Quit;
   end Realize;

   procedure On_Destroy (Self : access Gtk.Widget.Gtk_Widget_Record'Class) is
      pragma Unreferenced (Self);
   begin
      Gtk.Main.Main_Quit;
   end On_Destroy;

   procedure Find_Home is
      --  The shaders are found from where the program is
      Cmd : constant String := Ada.Command_Line.Command_Name;
   begin
      if not Ada.Directories.Exists ("shaders/world.vert") then
         for I in reverse Cmd'Range loop
            if Cmd (I) = '/' then
               Ada.Directories.Set_Directory (Cmd (Cmd'First .. I) & "..");
               exit;
            end if;
         end loop;
      end if;
   end Find_Home;

   procedure Run is
      Id : Guint;
   begin
      Find_Home;
      Gtk.Main.Init;
      Load_Choices;
      Shot_File := To_Unbounded_String (Env ("ADAFLIP_SHOT"));
      if Env ("ADAFLIP_SHOT_FRAME") /= "" then
         Shot_Frame := Natural'Value (Env ("ADAFLIP_SHOT_FRAME"));
      end if;
      if Env ("ADAFLIP_TRACK") /= "" then
         Track_Sel := Track.Track_Id'Value (Env ("ADAFLIP_TRACK"));
      end if;
      if Env ("ADAFLIP_CAMERA") /= "" then
         Camera := Renderer.Camera_Kind'Value (Env ("ADAFLIP_CAMERA"));
      end if;
      if Env ("ADAFLIP_SKIP") /= "" then
         Skip_Seconds := Float'Value (Env ("ADAFLIP_SKIP"));
      end if;
      if Env ("ADAFLIP_VOLUME") /= "" then
         Volume := Float'Value (Env ("ADAFLIP_VOLUME"));
      end if;
      Autopilot := Env ("ADAFLIP_AUTOPILOT") /= "";
      Profile := Env ("ADAFLIP_PROFILE") /= "";

      Gtk.Window.Gtk_New (Window);
      Window.Set_Title ("AdaFlip");
      Window.Set_Default_Size (1600, 900);
      Window.On_Destroy (On_Destroy'Access);
      Window.On_Key_Press_Event (Key_Press'Access, False);
      Window.On_Key_Release_Event (Key_Release'Access, False);

      GL_Area.Gtk_New (Area);
      Area.Set_Required_Version (4, 5);
      Area.Set_Has_Depth_Buffer (False);
      Area.On_Realize (Realize'Access);
      Area.On_Render (Render'Access);
      Area.Set_Can_Focus (True);
      Window.Add (Area);
      Window.Show_All;
      --  GTK's handshake with the compositor settles into every other
      --  refresh otherwise; without it the frame clock keeps the display's
      if Env ("ADAFLIP_FRAME_SYNC") = "" then
         Set_Frame_Sync (Window.Get_Window, 0);
      end if;
      if Env ("ADAFLIP_FULLSCREEN") /= "" then
         Window.Fullscreen;
         Is_Fullscreen := True;
      end if;
      Id := Area.Add_Tick_Callback (Tick'Access);
      pragma Unreferenced (Id);
      Gtk.Main.Main;
      Gamepad.Rumble (0.0, 0.0);
      Gamepad.Close;
      Audio.Stop;
   end Run;

end App;
