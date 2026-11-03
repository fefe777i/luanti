The .x and .b3d formats additionally support (a single) animation.
The .gltf and .bbmodel formats support multiple named animations.

#### Blockbench (`.bbmodel`)

Models saved by [Blockbench](https://www.blockbench.net/) can be used directly,
without exporting them first: `mesh = "model.bbmodel"`.

* Geometry: cubes (box UV and per-face UV, rotation, inflate, mirrored UV)
  and mesh elements.
* Groups are bones. Their names are the bone names for bone overrides.
  Cubes are attached rigidly to their group; there are no skin weights.
* Animations are loaded by name, exactly as named in Blockbench
  (e.g. `walk`, `idle`). Use `play_animation("walk", {loop = false})`.
  Rotation, position and scale keyframes are supported. Keyframe times are in
  seconds, so use a speed of `1.0`. The loop mode set in Blockbench is not
  used; pass `loop` explicitly.
  `catmullrom` and `bezier` keyframes are played back as `linear`, and `step`
  keyframes are respected. Molang expressions are not supported.
  Rotation keyframes are interpolated as quaternions, not as Euler angles.
* Textures: a texture embedded in the model (the default when saving from
  Blockbench) is used automatically for every texture slot for which the
  `textures` property (or `tiles`, ...) of the object does not supply
  one. A texture you supply yourself takes precedence. The texture slot of a
  face is the index of its texture in Blockbench. Embedded textures are
  currently used for entities only.
* Scale: 16 Blockbench pixels = 1 node = 10 units. The front of a Blockbench
  model (its north side) is the front of the Luanti model.
* Not supported: Bedrock/Java-specific axis conventions, texture animation
  frames, locators and other non-geometry elements.
