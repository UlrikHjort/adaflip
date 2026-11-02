--  AdaFlip: a combat racer in Ada
--  Copyright (c) 2026 Ulrik Hørlyk Hjort
--  SPDX-License-Identifier: MIT
--
--  Triangles on their way to the graphics card.

with GL;
with Math3D;

package Mesh is

   --  How the shader paints a surface (see world.frag).  Add Indoor to
   --  any of them for a surface under a tunnel roof, out of the sun.
   Plain    : constant := 0.0;
   Road     : constant := 1.0;   --  UV: metres along, metres across from the middle
   Wall     : constant := 2.0;   --  UV: metres along, metres round the profile
   Glow     : constant := 3.0;   --  lit by itself
   Ground   : constant := 4.0;
   Building : constant := 5.0;   --  UV in metres: windows
   Concrete : constant := 6.0;
   Tyre     : constant := 7.0;   --  U: round the tread
   Paint    : constant := 8.0;   --  tinted by the car's colour
   Chevron  : constant := 9.0;   --  arrows lit by themselves; U along
   Rock     : constant := 11.0;
   Checker  : constant := 12.0;  --  black and white squares, UV in metres
   Metal    : constant := 13.0;
   Glass    : constant := 14.0;
   Indoor   : constant := 100.0;

   type Vertex is record
      P, N : Math3D.Vec3;
      R, G, B, Mat, U, V : Float;
   end record
     with Convention => C;

   type Vertex_Array is array (Natural range <>) of aliased Vertex
     with Convention => C;
   type Vertex_Access is access Vertex_Array;

   type Builder is record
      Data : Vertex_Access;
      Used : Natural := 0;
   end record;

   procedure Add (B : in out Builder; V : Vertex);

   type Color is record
      R, G, B : Float;
   end record;

   procedure Tri (B : in out Builder; A, C, D : Math3D.Vec3; Col : Color; Mat : Float := Plain);
   --  Flat shaded, counter-clockwise from the front

   procedure Quad (B : in out Builder; A, C, D, E : Math3D.Vec3; Col : Color; Mat : Float := Plain);
   --  A C D E in order round the face

   procedure Box (B : in out Builder; Lo, Hi : Math3D.Vec3; Col : Color; Mat : Float := Plain);

   procedure Oriented_Box
     (B : in out Builder; Centre, Along, Up : Math3D.Vec3; L, H, W : Float;
      Col : Color; Mat : Float := Plain);
   --  A box lying along a direction: half sizes L, H, W

   type GPU is record
      VAO, VBO : aliased GL.GLuint := 0;
      Count    : GL.GLsizei := 0;
   end record;

   function Upload (B : in out Builder) return GPU;
   --  Sends it and frees the builder

   procedure Update (M : in out GPU; B : in out Builder);
   --  Sends it again into the same buffers (made on first use), for what
   --  changes every frame; the builder is kept for reuse

   procedure Draw (M : GPU);
   procedure Delete (M : in out GPU);

end Mesh;
