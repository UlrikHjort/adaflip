--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
with Ada.Numerics;
with Ada.Numerics.Elementary_Functions;
with Car_Model;
with GL; use GL;
with Mesh;
with Scenery;
with Shaders;
with Track;
with Vehicle;
with System;
with Interfaces.C;
with Ada.Text_IO;
with Ada.Environment_Variables;

package body Renderer is

   use Ada.Numerics.Elementary_Functions;
   use Math3D;
   use type Race.Event_Kind;
   use type Race.Phase_Kind;
   use type Track.Theme_Kind;
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;

   Pi : constant := Ada.Numerics.Pi;
   Debug : constant Boolean := Ada.Environment_Variables.Exists ("ADAFLIP_DEBUG");

   World_P, Sky_P, Fx_P, Post_P : GLuint := 0;

   --  World uniforms
   U_VP, U_Model, U_Cam, U_Sun_Dir, U_Sun, U_Sky_Amb, U_Ground_Amb, U_Fog, U_Fog_D,
   U_Tint, U_Road, U_Stripe, U_G1, U_G2, U_Night, U_Time : GLint := -1;
   --  Sky
   S_Inv, S_Sun_Dir, S_Sun, S_Zenith, S_Horizon, S_Night, S_Time : GLint := -1;
   --  Effects
   F_VP, F_Cam, F_Fog, F_Fog_D : GLint := -1;
   --  Post
   P_Scene, P_Flash, P_Speed : GLint := -1;

   Scene_FB, Resolve_FB : aliased GLuint := 0;
   Scene_Color, Scene_Depth : aliased GLuint := 0;
   Resolve_Tex : aliased GLuint := 0;
   Empty_VAO : aliased GLuint := 0;
   FB_W, FB_H : Natural := 0;

   World_Mesh : Mesh.GPU;
   Fx_Mesh : Mesh.GPU;
   Fx : Mesh.Builder;

   Look : Scenery.Look := Scenery.Look_Of (Track.Desert);
   Clock : Float := 0.0;

   --  The camera
   Cam_Eye : Vec3 := (0.0, 5.0, 10.0);
   Cam_Up : Vec3 := Up_Y;
   Cam_Fwd : Vec3 := (0.0, 0.0, -1.0);
   Cam_R : Vec3 := (1.0, 0.0, 0.0);
   Cam_U_Screen : Vec3 := Up_Y;
   Cam_Fov : Float := 70.0;
   Cam_Fresh : Boolean := True;

   function Camera_Position return Vec3 is (Cam_Eye);
   function Camera_Right return Vec3 is (Cam_R);

   ---------------------------------------------------------------------------
   --  Particles
   ---------------------------------------------------------------------------

   type Particle is record
      P, V : Vec3 := Zero;
      Age, Life : Float := 0.0;
      Size, Grow : Float := 0.0;
      Col : Mesh.Color := (0.0, 0.0, 0.0);
      Cover : Float := 0.0;   --  0 adds light; more is smoke
      Drag, Fall : Float := 0.0;
   end record;
   Max_Parts : constant := 5000;
   Parts : array (1 .. Max_Parts) of Particle;
   Next_Part : Positive := 1;
   Events_Read : Natural := 0;

   type Seed_Type is mod 2**32;
   Seed : Seed_Type := 99;
   function Rand return Float is
   begin
      Seed := Seed * 1664525 + 1013904223;
      return Float (Seed / 256) / Float (2**24);
   end Rand;
   function Spread return Vec3 is
     (Normalize (Vec3'(Rand * 2.0 - 1.0, Rand * 2.0 - 1.0, Rand * 2.0 - 1.0)));

   procedure Emit (P, V : Vec3; Life, Size, Grow : Float; Col : Mesh.Color;
                   Cover : Float := 0.0; Drag : Float := 0.0; Fall : Float := 0.0) is
   begin
      Parts (Next_Part) := (P, V, 0.0, Life, Size, Grow, Col, Cover, Drag, Fall);
      Next_Part := (if Next_Part = Max_Parts then 1 else Next_Part + 1);
   end Emit;

   procedure Sparks (P : Vec3; N : Natural; Speed : Float) is
   begin
      for K in 1 .. N loop
         Emit (P, (Speed * (0.3 + Rand)) * Spread, 0.25 + 0.4 * Rand, 0.09, -0.05,
               (6.0, 3.2, 1.0), Fall => 12.0, Drag => 1.0);
      end loop;
   end Sparks;

   procedure Boom (P : Vec3; Big : Float) is
   begin
      Emit (P, Zero, 0.18, 7.0 * Big, 10.0, (8.0, 5.0, 2.5));
      for K in 1 .. 34 loop
         Emit (P + 0.8 * Spread, (14.0 * Rand) * Spread, 0.45 + 0.5 * Rand, 1.2 * Big, 3.5,
               (4.0, 1.5 + Rand, 0.35), Drag => 2.5);
      end loop;
      for K in 1 .. 22 loop
         Emit (P + Spread, (5.0 * Rand) * Spread + Vec3'(0.0, 2.5, 0.0), 1.6 + 1.2 * Rand,
               1.4 * Big, 3.0, (0.12, 0.11, 0.1), Cover => 0.55, Drag => 1.2);
      end loop;
      Sparks (P, 30, 28.0);
   end Boom;

   procedure Ring_Burst (P, N : Vec3; Col : Mesh.Color; Speed : Float) is
      A : constant Vec3 := Normalize (Cross (N, (if abs N.Y < 0.9 then Up_Y else (1.0, 0.0, 0.0))));
      B : constant Vec3 := Cross (N, A);
   begin
      for K in 0 .. 63 loop
         declare
            T : constant Float := 2.0 * Pi * Float (K) / 64.0;
            D : constant Vec3 := Cos (T) * A + Sin (T) * B;
         begin
            Emit (P + 0.5 * N, Speed * D, 0.55, 1.1, 1.0, Col, Drag => 1.0);
         end;
      end loop;
   end Ring_Burst;

   procedure Read_Events is
      use Race;
      From : Natural := Events_Read;
   begin
      if Event_Serial - From > Event_Ring then
         From := Event_Serial - Event_Ring;
      end if;
      for K in From .. Event_Serial - 1 loop
         declare
            E : constant Event := Events (K mod Event_Ring);
         begin
            case E.Kind is
               when Explosion => Boom (E.P, E.Size);
               when Bump => Sparks (E.P, 10, 9.0);
               when Scrape => Sparks (E.P, 2, 7.0);
               when Picked =>
                  for J in 1 .. 18 loop
                     Emit (E.P, (6.0 * Rand) * Spread, 0.5, 0.35, -0.3, (3.0, 2.2, 0.5), Drag => 2.0);
                  end loop;
               when Pulsed =>
                  if E.Car in 1 .. State.Count then
                     Ring_Burst (E.P, State.Racers (E.Car).Car.Ground_N, (0.6, 1.6, 3.5), 48.0);
                  end if;
               when Reset_Car =>
                  for J in 1 .. 30 loop
                     Emit (E.P, (5.0 * Rand) * Spread, 0.7, 0.4, 0.5,
                           (Look.Stripe.R, Look.Stripe.G, Look.Stripe.B), Drag => 2.0);
                  end loop;
               when Boost_On | Fired_Rocket =>
                  Emit (E.P, Zero, 0.12, 2.5, 6.0, (4.0, 2.4, 1.0));
               when Shield_On =>
                  Emit (E.P, Zero, 0.3, 3.5, 6.0, (0.5, 1.5, 2.5));
               when others => null;
            end case;
         end;
      end loop;
      Events_Read := Event_Serial;
   end Read_Events;

   procedure Move_Particles (Dt : Float) is
   begin
      for P of Parts loop
         if P.Age < P.Life then
            P.Age := P.Age + Dt;
            P.V := (1.0 - Float'Min (1.0, P.Drag * Dt)) * P.V + Vec3'(0.0, -P.Fall * Dt, 0.0);
            P.P := P.P + Dt * P.V;
         end if;
      end loop;
   end Move_Particles;

   --  The quads, facing the camera
   procedure Put_Sprite (Center : Vec3; Size : Float; Col : Mesh.Color; Cover : Float;
                         A : Vec3 := Cam_R; B : Vec3 := Cam_U_Screen) is
      X : constant Vec3 := Size * A;
      Y : constant Vec3 := Size * B;
      procedure V (P : Vec3; U, W : Float) is
      begin
         Mesh.Add (Fx, (P, Zero, Col.R, Col.G, Col.B, Cover, U, W));
      end V;
   begin
      V (Center - X - Y, 0.0, 0.0);
      V (Center + X - Y, 1.0, 0.0);
      V (Center + X + Y, 1.0, 1.0);
      V (Center - X - Y, 0.0, 0.0);
      V (Center + X + Y, 1.0, 1.0);
      V (Center - X + Y, 0.0, 1.0);
   end Put_Sprite;

   ---------------------------------------------------------------------------

   procedure Resize (W, H : Natural) is
   begin
      if W = FB_W and then H = FB_H then
         return;
      end if;
      FB_W := W;
      FB_H := H;
      glBindRenderbuffer (GL_RENDERBUFFER, Scene_Color);
      glRenderbufferStorageMultisample (GL_RENDERBUFFER, 4, GL_RGBA16F, GLsizei (W), GLsizei (H));
      glBindRenderbuffer (GL_RENDERBUFFER, Scene_Depth);
      glRenderbufferStorageMultisample (GL_RENDERBUFFER, 4, GL_DEPTH_COMPONENT32F, GLsizei (W), GLsizei (H));
      glBindFramebuffer (GL_FRAMEBUFFER, Scene_FB);
      glFramebufferRenderbuffer (GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, Scene_Color);
      glFramebufferRenderbuffer (GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, Scene_Depth);

      glBindTexture (GL_TEXTURE_2D, Resolve_Tex);
      glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA16F, GLsizei (W), GLsizei (H), 0, GL_RGBA, GL_FLOAT,
                    System.Null_Address);
      glGenerateMipmap (GL_TEXTURE_2D);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
      glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
      glBindFramebuffer (GL_FRAMEBUFFER, Resolve_FB);
      glFramebufferTexture2D (GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, Resolve_Tex, 0);
   end Resize;

   procedure Create is
   begin
      World_P := Shaders.Load_Program ("shaders/world.vert", "shaders/world.frag");
      Sky_P := Shaders.Load_Program ("shaders/sky.vert", "shaders/sky.frag");
      Fx_P := Shaders.Load_Program ("shaders/fx.vert", "shaders/fx.frag");
      Post_P := Shaders.Load_Program ("shaders/post.vert", "shaders/post.frag");
      U_VP := Shaders.Location (World_P, "uViewProj");
      U_Model := Shaders.Location (World_P, "uModel");
      U_Cam := Shaders.Location (World_P, "uCamPos");
      U_Sun_Dir := Shaders.Location (World_P, "uSunDir");
      U_Sun := Shaders.Location (World_P, "uSunCol");
      U_Sky_Amb := Shaders.Location (World_P, "uSkyAmb");
      U_Ground_Amb := Shaders.Location (World_P, "uGroundAmb");
      U_Fog := Shaders.Location (World_P, "uFogCol");
      U_Fog_D := Shaders.Location (World_P, "uFogDensity");
      U_Tint := Shaders.Location (World_P, "uTint");
      U_Road := Shaders.Location (World_P, "uRoadCol");
      U_Stripe := Shaders.Location (World_P, "uStripe");
      U_G1 := Shaders.Location (World_P, "uGround1");
      U_G2 := Shaders.Location (World_P, "uGround2");
      U_Night := Shaders.Location (World_P, "uNight");
      U_Time := Shaders.Location (World_P, "uTime");
      S_Inv := Shaders.Location (Sky_P, "uInvViewProj");
      S_Sun_Dir := Shaders.Location (Sky_P, "uSunDir");
      S_Sun := Shaders.Location (Sky_P, "uSunCol");
      S_Zenith := Shaders.Location (Sky_P, "uZenith");
      S_Horizon := Shaders.Location (Sky_P, "uHorizon");
      S_Night := Shaders.Location (Sky_P, "uNight");
      S_Time := Shaders.Location (Sky_P, "uTime");
      F_VP := Shaders.Location (Fx_P, "uViewProj");
      F_Cam := Shaders.Location (Fx_P, "uCamPos");
      F_Fog := Shaders.Location (Fx_P, "uFogCol");
      F_Fog_D := Shaders.Location (Fx_P, "uFogDensity");
      P_Scene := Shaders.Location (Post_P, "uScene");
      P_Flash := Shaders.Location (Post_P, "uFlash");
      P_Speed := Shaders.Location (Post_P, "uSpeed");

      glGenFramebuffers (1, Scene_FB'Address);
      glGenFramebuffers (1, Resolve_FB'Address);
      glGenRenderbuffers (1, Scene_Color'Address);
      glGenRenderbuffers (1, Scene_Depth'Address);
      glGenTextures (1, Resolve_Tex'Address);
      glGenVertexArrays (1, Empty_VAO'Address);
      Car_Model.Build;
   end Create;

   procedure New_Track is
   begin
      Mesh.Delete (World_Mesh);
      Scenery.Build (World_Mesh);
      Look := Scenery.Look_Of (Track.Theme (Track.Current));
      for P of Parts loop
         P.Age := P.Life;
      end loop;
      Events_Read := Race.Event_Serial;
      Cam_Fresh := True;
   end New_Track;

   function V3 (C : Mesh.Color) return Vec3 is (C.R, C.G, C.B);

   ---------------------------------------------------------------------------

   type Pose is record
      P, F, U, R : Vec3;
   end record;

   function Pose_Of (I : Race.Car_Index; Alpha : Float) return Pose is
      R : Race.Racer renames Race.State.Racers (I);
      P : constant Vec3 := Lerp (R.Prev_P, R.Car.P, Alpha);
      F : constant Vec3 := Normalize (Lerp (R.Prev_F, R.Car.F, Alpha));
      U0 : constant Vec3 := Normalize (Lerp (R.Prev_U, R.Car.U, Alpha));
      U : constant Vec3 := Normalize (U0 - Dot (U0, F) * F);
   begin
      if Length (R.Car.P - R.Prev_P) > 5.0 then
         --  put back on the track this step: no sweep across
         return (R.Car.P, R.Car.F, R.Car.U, R.Car.R);
      end if;
      return (P, F, U, Cross (F, U));
   end Pose_Of;

   procedure Place_Camera (V : View; Alpha, Dt : Float) is
      Me : Race.Racer renames Race.State.Racers (V.Focus);
      C : Vehicle.Car renames Me.Car;
      Q : constant Pose := Pose_Of (V.Focus, Alpha);
      K_Up : constant Float := Float'Min (1.0, Dt * (if V.Camera = Bumper then 9.0 else 3.5));
      K_Fwd : constant Float := Float'Min (1.0, Dt * 5.0);
      Want_Up : Vec3;
      Head : Vec3;
   begin
      if C.Grounded > 0 then
         Want_Up := C.Ground_N;
      else
         Want_Up := Normalize (Cam_Up + (Dt * 0.6) * (Up_Y - Cam_Up));
      end if;
      if Cam_Fresh then
         Cam_Up := Want_Up;
         Cam_Fwd := Q.F;
      end if;
      Cam_Up := Normalize (Cam_Up + K_Up * (Want_Up - Cam_Up));
      Head := (if C.Speed > 6.0 and then Dot (C.V, Q.F) > 0.0 then C.V else Q.F);
      Head := Head - Dot (Head, Cam_Up) * Cam_Up;
      if Length (Head) < 0.01 then
         Head := Cam_Fwd;
      end if;
      Head := Normalize (Head);
      Cam_Fwd := (if Cam_Fresh then Head else Normalize (Cam_Fwd + K_Fwd * (Head - Cam_Fwd)));
      Cam_Fwd := Normalize (Cam_Fwd - Dot (Cam_Fwd, Cam_Up) * Cam_Up);
      Cam_Fresh := False;
   end Place_Camera;

   procedure Draw_Car (I : Race.Car_Index; Alpha : Float) is
      R : Race.Racer renames Race.State.Racers (I);
      C : Vehicle.Car renames R.Car;
      Q : constant Pose := Pose_Of (I, Alpha);
      M : constant Mat4 := Frame (Q.R, Q.U, (-1.0) * Q.F, Q.P);
      Paint : constant Mesh.Color := Car_Model.Paints (R.Color mod Car_Model.Paints'Length);
      Steer_A : constant Float := -C.Steer * 0.5 / (1.0 + C.Speed / 30.0) * C.Side;
   begin
      glUniformMatrix4fv (U_Model, 1, GL_FALSE, M'Address);
      Shaders.Set (U_Tint, V3 (Paint));
      Mesh.Draw (Car_Model.Body_Mesh);
      Shaders.Set (U_Tint, Vec3'(1.0, 1.0, 1.0));
      for W in Vehicle.Wheel_Id loop
         declare
            use type Vehicle.Wheel_Id;
            WM : constant Mat4 :=
              M * Translation ((Vehicle.Wheel_X (W), C.Drop (W), -Vehicle.Wheel_Z (W)))
              * Rotation_Y (if W <= 2 then Steer_A else 0.0)
              * Rotation_X (-C.Spin (W));
         begin
            glUniformMatrix4fv (U_Model, 1, GL_FALSE, WM'Address);
            Mesh.Draw (Car_Model.Wheel_Mesh);
         end;
      end loop;
   end Draw_Car;

   procedure Draw (Width, Height : Natural; V : View; Alpha, Dt : Float) is
      GTK_FB : aliased GLint := 0;
      Me : Race.Racer renames Race.State.Racers (V.Focus);
      Q : Pose;
      Eye, Target, Up : Vec3;
      View_M, Proj, VP : Mat4;
      Aspect : constant Float := Float (Width) / Float (Natural'Max (Height, 1));
      Sun_Dir : constant Vec3 := Normalize (V3 (Look.Sun_Dir));
      Back : constant Float := (if V.Look_Back then -1.0 else 1.0);
   begin
      if Width = 0 or else Height = 0 then
         return;
      end if;
      glGetIntegerv (GL_FRAMEBUFFER_BINDING, GTK_FB'Address);
      Clock := Clock + Dt;
      Resize (Width, Height);

      --  The camera
      Place_Camera (V, Alpha, Dt);
      Q := Pose_Of (V.Focus, Alpha);
      declare
         C : Vehicle.Car renames Me.Car;
         Fwd : constant Vec3 := Rotate (Cam_Fwd, Cam_Up, -V.Look_X * 2.6);
         Want_Fov : Float := 68.0 + C.Speed * 0.22 + (if C.Boost_T > 0.0 then 8.0 else 0.0);
      begin
         if V.Orbit then
            declare
               O : constant Vec3 := Rotate ((-1.0) * Cam_Fwd, Cam_Up, Clock * 0.22);
            begin
               Eye := Q.P + 9.0 * O + 3.2 * Cam_Up;
               Target := Q.P + 0.6 * Cam_Up;
               Up := Cam_Up;
               Want_Fov := 62.0;
            end;
         elsif V.Camera = Bumper then
            Up := C.Side * Q.U;
            Eye := Q.P + (0.72 * C.Side) * Q.U + (Back * 0.3) * Q.F;
            Target := Eye + (Back * 10.0) * Q.F;
         else
            declare
               Dist : constant Float := (if V.Camera = Far_Chase then 11.5 else 7.2);
               High : constant Float := (if V.Camera = Far_Chase then 3.8 else 2.5);
            begin
               Eye := Q.P - (Back * Dist) * Fwd + High * Cam_Up;
               Target := Q.P + (Back * 4.0) * Fwd + 1.0 * Cam_Up;
               Up := Cam_Up;
            end;
         end if;
         --  Not through the walls
         if V.Camera /= Bumper then
            declare
               L : constant Track.Locus := Track.Locate (Eye, Me.Car.Hint);
               D : Float;
               N : Vec3;
            begin
               Track.Surface (L, D, N);
               if Debug then
                  Ada.Text_IO.Put_Line ("eye" & Eye.X'Image & Eye.Y'Image & Eye.Z'Image & " car"
                    & Q.P.X'Image & Q.P.Y'Image & Q.P.Z'Image & " d" & D'Image & " hint" & L.I'Image
                    & " carhint" & Me.Car.Hint'Image);
               end if;
               if D < 0.7 and then D > -12.0 then
                  Eye := Eye + (0.7 - D) * N;
               end if;
            end;
         end if;
         Cam_Fov := Cam_Fov + (Want_Fov - Cam_Fov) * Float'Min (1.0, Dt * 3.0);
      end;
      Cam_Eye := Eye;
      View_M := Look_At (Eye, Target, Up);
      Proj := Perspective (Cam_Fov * Pi / 180.0, Aspect, 0.25, 7000.0);
      VP := Proj * View_M;
      declare
         F : constant Vec3 := Normalize (Target - Eye);
      begin
         Cam_R := Normalize (Cross (F, Up));
         Cam_U_Screen := Cross (Cam_R, F);
      end;

      Read_Events;
      Move_Particles (Dt);

      glBindFramebuffer (GL_FRAMEBUFFER, Scene_FB);
      glViewport (0, 0, GLsizei (Width), GLsizei (Height));
      glDisable (GL_CULL_FACE);
      glDisable (GL_BLEND);
      glDepthMask (GL_TRUE);
      glClearColor (0.0, 0.0, 0.0, 1.0);
      glClear (GL_COLOR_BUFFER_BIT + GL_DEPTH_BUFFER_BIT);

      --  The sky
      glDisable (GL_DEPTH_TEST);
      glUseProgram (Sky_P);
      declare
         Inv : constant Mat4 := Inverse (VP);
      begin
         glUniformMatrix4fv (S_Inv, 1, GL_FALSE, Inv'Address);
      end;
      Shaders.Set (S_Sun_Dir, Sun_Dir);
      Shaders.Set (S_Sun, V3 (Look.Sun));
      Shaders.Set (S_Zenith, V3 (Look.Zenith));
      Shaders.Set (S_Horizon, V3 (Look.Horizon));
      Shaders.Set (S_Night, Look.Night);
      Shaders.Set (S_Time, Clock);
      glBindVertexArray (Empty_VAO);
      glDrawArrays (GL_TRIANGLES, 0, 3);

      --  The world
      glEnable (GL_DEPTH_TEST);
      glDepthFunc (GL_LESS);
      glUseProgram (World_P);
      glUniformMatrix4fv (U_VP, 1, GL_FALSE, VP'Address);
      glUniformMatrix4fv (U_Model, 1, GL_FALSE, Identity'Address);
      Shaders.Set (U_Cam, Eye);
      Shaders.Set (U_Sun_Dir, Sun_Dir);
      Shaders.Set (U_Sun, V3 (Look.Sun));
      Shaders.Set (U_Sky_Amb, V3 (Look.Sky_Amb));
      Shaders.Set (U_Ground_Amb, V3 (Look.Ground_Amb));
      Shaders.Set (U_Fog, V3 (Look.Fog));
      Shaders.Set (U_Fog_D, Look.Fog_Density);
      Shaders.Set (U_Tint, Vec3'(1.0, 1.0, 1.0));
      Shaders.Set (U_Road, V3 (Look.Road));
      Shaders.Set (U_Stripe, V3 (Look.Stripe));
      Shaders.Set (U_G1, V3 (Look.Ground_1));
      Shaders.Set (U_G2, V3 (Look.Ground_2));
      Shaders.Set (U_Night, Look.Night);
      Shaders.Set (U_Time, Clock);
      Mesh.Draw (World_Mesh);

      for I in 1 .. Race.State.Count loop
         if not (V.Camera = Bumper and then I = V.Focus and then not V.Orbit) then
            Draw_Car (I, Alpha);
         end if;
      end loop;

      --  Pods, rockets and mines
      declare
         Spin : constant Mat4 := Rotation_Y (Clock * 2.0);
         Pulse : constant Float := 0.8 + 0.4 * Sin (Clock * 6.0);
      begin
         Shaders.Set (U_Tint, Vec3'(Pulse, Pulse, Pulse));
         for K in 1 .. Race.Pod_Count loop
            if Race.Pods (K).Wait <= 0.0 then
               declare
                  M : constant Mat4 :=
                    Translation (Race.Pods (K).P + Vec3'(0.0, 0.25 * Sin (Clock * 2.5 + Float (K)), 0.0))
                    * Spin;
               begin
                  glUniformMatrix4fv (U_Model, 1, GL_FALSE, M'Address);
                  Mesh.Draw (Car_Model.Pod_Mesh);
               end;
            end if;
         end loop;
         Shaders.Set (U_Tint, Vec3'(1.0, 1.0, 1.0));
         for S of Race.Shots loop
            if S.Active then
               declare
                  F : constant Vec3 := Normalize (S.V);
                  U0 : constant Vec3 := (if abs F.Y < 0.9 then Up_Y else (1.0, 0.0, 0.0));
                  R : constant Vec3 := Normalize (Cross (F, U0));
                  U : constant Vec3 := Cross (R, F);
                  M : constant Mat4 := Frame (R, U, (-1.0) * F, S.P);
               begin
                  glUniformMatrix4fv (U_Model, 1, GL_FALSE, M'Address);
                  Mesh.Draw (Car_Model.Rocket_Mesh);
                  Emit (S.P - 0.8 * F, (3.0 * Rand) * Spread, 0.12, 0.45, 1.5, (4.0, 1.6, 0.4));
                  Emit (S.P - 0.9 * F, (1.5 * Rand) * Spread, 1.2, 0.35, 1.8, (0.5, 0.5, 0.52),
                        Cover => 0.35, Drag => 1.0);
               end;
            end if;
         end loop;
         for Mi of Race.Mines loop
            if Mi.Active then
               declare
                  N : constant Vec3 := Mi.N;
                  A : constant Vec3 := Normalize (Cross (N, (if abs N.Y < 0.9 then (1.0, 0.0, 0.0) else (0.0, 0.0, 1.0))));
                  M : constant Mat4 := Frame (A, N, Cross (A, N), Mi.P);
                  Blink : constant Float := (if Sin (Clock * 9.0) > 0.0 then 1.6 else 0.25);
               begin
                  glUniformMatrix4fv (U_Model, 1, GL_FALSE, M'Address);
                  Shaders.Set (U_Tint, Vec3'(Blink, Blink, Blink));
                  Mesh.Draw (Car_Model.Mine_Mesh);
               end;
            end if;
         end loop;
      end;

      --  Shields: light added round the car
      glEnable (GL_BLEND);
      glDepthMask (GL_FALSE);
      glBlendFunc (GL_ONE, GL_ONE);
      for I in 1 .. Race.State.Count loop
         declare
            C : Vehicle.Car renames Race.State.Racers (I).Car;
         begin
            if C.Shield_T > 0.0 then
               declare
                  P : constant Pose := Pose_Of (I, Alpha);
                  M : constant Mat4 := Frame (P.R, P.U, (-1.0) * P.F, P.P);
                  S : constant Float := Float'Min (1.0, C.Shield_T * 2.0) * (0.8 + 0.2 * Sin (Clock * 11.0));
               begin
                  glUniformMatrix4fv (U_Model, 1, GL_FALSE, M'Address);
                  Shaders.Set (U_Tint, Vec3'(S, S, S));
                  Mesh.Draw (Car_Model.Shield_Mesh);
               end;
            end if;
         end;
      end loop;

      --  Effects: flames at the exhausts, dust under sliding wheels, shadows
      for I in 1 .. Race.State.Count loop
         declare
            C : Vehicle.Car renames Race.State.Racers (I).Car;
            P : constant Pose := Pose_Of (I, Alpha);
         begin
            if C.Boost_T > 0.0 then
               for S in -1 .. 1 loop
                  if S /= 0 then
                     Emit (P.P - 2.1 * P.F + (0.4 * Float (S)) * P.R,
                           C.V - 14.0 * P.F + (2.0 * Rand) * Spread, 0.16 + 0.1 * Rand, 0.32, 1.6,
                           (3.5, 1.4, 0.35));
                  end if;
               end loop;
            end if;
            if C.Slip > 0.45 and then C.Grounded >= 2 and then Rand < C.Slip * Dt * 25.0 then
               declare
                  W : constant Vehicle.Wheel_Id := Vehicle.Wheel_Id (1 + Natural (Float'Floor (Rand * 3.99)));
                  Dust : constant Mesh.Color :=
                    (case Track.Theme (Track.Current) is
                        when Track.Desert => (0.55, 0.38, 0.25),
                        when Track.City => (0.35, 0.35, 0.37),
                        when Track.Ice => (0.85, 0.9, 1.0));
               begin
                  Emit (Vehicle.Hub (C, W) - 0.5 * C.Ground_N, 0.3 * C.V + (1.5 * Rand) * Spread,
                        0.9 + Rand * 0.6, 0.5, 2.2, Dust, Cover => 0.3, Drag => 2.0);
               end;
            end if;
         end;
      end loop;

      for P of Parts loop
         if P.Age < P.Life then
            declare
               T : constant Float := P.Age / P.Life;
               Fade : constant Float := (1.0 - T) * (1.0 - T);
               Size : constant Float := Float'Max (0.02, P.Size + P.Grow * P.Age);
            begin
               if P.Cover > 0.0 then
                  Put_Sprite (P.P, Size, P.Col, P.Cover * (1.0 - T));
               else
                  Put_Sprite (P.P, Size, (P.Col.R * Fade, P.Col.G * Fade, P.Col.B * Fade), 0.0);
               end if;
            end;
         end if;
      end loop;
      for I in 1 .. Race.State.Count loop
         declare
            C : Vehicle.Car renames Race.State.Racers (I).Car;
            P : constant Pose := Pose_Of (I, Alpha);
            L : constant Track.Locus := Track.Locate (P.P, C.Hint);
            D : Float;
            N : Vec3;
         begin
            Track.Surface (L, D, N);
            if D < 5.0 and then D > 0.0 then
               declare
                  A : Vec3 := P.F - Dot (P.F, N) * N;
               begin
                  if Length (A) > 0.1 then
                     A := Normalize (A);
                     Put_Sprite (P.P - (D - 0.07) * N, 1.0, (0.0, 0.0, 0.0), 0.6 * (1.0 - D / 5.0),
                                 1.6 * Cross (A, N), 2.6 * A);
                  end if;
               end;
            end if;
         end;
      end loop;
      Mesh.Update (Fx_Mesh, Fx);
      glBlendFunc (GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
      glUseProgram (Fx_P);
      glUniformMatrix4fv (F_VP, 1, GL_FALSE, VP'Address);
      Shaders.Set (F_Cam, Eye);
      Shaders.Set (F_Fog, V3 (Look.Fog));
      Shaders.Set (F_Fog_D, Look.Fog_Density);
      Mesh.Draw (Fx_Mesh);
      glDepthMask (GL_TRUE);
      glDisable (GL_BLEND);

      --  To the screen
      glBindFramebuffer (GL_READ_FRAMEBUFFER, Scene_FB);
      glBindFramebuffer (GL_DRAW_FRAMEBUFFER, Resolve_FB);
      glBlitFramebuffer (0, 0, GLint (Width), GLint (Height), 0, 0, GLint (Width), GLint (Height),
                         GL_COLOR_BUFFER_BIT, GL_NEAREST);
      glBindTexture (GL_TEXTURE_2D, Resolve_Tex);
      glGenerateMipmap (GL_TEXTURE_2D);
      glBindFramebuffer (GL_FRAMEBUFFER, GLuint (GTK_FB));
      glViewport (0, 0, GLsizei (Width), GLsizei (Height));
      glDisable (GL_DEPTH_TEST);
      glUseProgram (Post_P);
      glActiveTexture (GL_TEXTURE0);
      glBindTexture (GL_TEXTURE_2D, Resolve_Tex);
      Shaders.Set (P_Scene, Integer'(0));
      Shaders.Set (P_Flash, Flash);
      Shaders.Set (P_Speed, Clamp ((Me.Car.Speed - 35.0) / 40.0, 0.0, 1.0) * (if V.Orbit then 0.0 else 1.0)
                   + (if Me.Car.Boost_T > 0.0 then 0.4 else 0.0));
      glBindVertexArray (Empty_VAO);
      glDrawArrays (GL_TRIANGLES, 0, 3);
      glBindVertexArray (0);
      Flash := Float'Max (0.0, Flash - Dt * 2.5);
   end Draw;

end Renderer;
