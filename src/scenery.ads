--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  The still world of the current track: the road, its walls and tunnels,
--  their lights and signs, and what stands round it (mesas, towers, ice).

with Mesh;
with Track;

package Scenery is

   type Look is record
      Wall, Concrete, Road, Stripe : Mesh.Color;
      Ground_1, Ground_2 : Mesh.Color;
      Sun_Dir : Mesh.Color;    --  towards the sun
      Sun, Sky_Amb, Ground_Amb : Mesh.Color;
      Zenith, Horizon, Fog : Mesh.Color;
      Fog_Density : Float;
      Night : Float;
   end record;

   function Look_Of (T : Track.Theme_Kind) return Look;

   procedure Build (World : out Mesh.GPU);
   --  For the track loaded (GL context current)

end Scenery;
