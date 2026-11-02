--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Everything written over the 3D view: the race panels (place, lap,
--  times, speed, the weapon in hand, the map), the countdown, and the
--  title, pause and results screens.  Drawn with cairo into a picture
--  that Hud_Layer lays over the scene.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Hud is

   type Screen is (Title, Racing, Paused, Results);

   type Item is record
      Label, Value : Unbounded_String;
   end record;
   type Item_List is array (1 .. 8) of Item;

   type Overlay is record
      Mode      : Screen := Title;
      Items     : Item_List;
      Item_Count : Natural := 0;
      Selected  : Positive := 1;
      Message   : Unbounded_String;
      Message_T : Float := 0.0;      --  seconds it stays
      Hint      : Unbounded_String;  --  the controls, at the foot of a screen
      Fps       : Float := 0.0;
      Show_Fps  : Boolean := False;
   end record;

   procedure Draw (Width, Height : Natural; O : Overlay);
   --  (GL context current, GTK's frame buffer bound)

   procedure Track_Changed;
   --  A race was set up: the map is drawn again

end Hud;
