# Asset sources — MVP 0.2.0

All third-party artwork admitted in this upgrade is CC0: modification, commercial games and public source redistribution are allowed. Original notices and full CC0 text are in `licenses/`. Exact archive hashes, versions, selected files and adaptations are in `characters/sources.json` and `nature/sources.json`. Preparation tools enforce the reviewed input hashes. No paid Extra/Source tier, subscription, Mixamo or Quaternius assets are included.

| Runtime assets | Author and reviewed free version | Adaptation |
| --- | --- | --- |
| Six humanoid GLBs, weapons | Kay Lousberg, Adventurers Free 2.0 | 23 standardized bones, palette/identity accessories, 19 selected clips per model |
| Human animation data | Kay Lousberg, Character Animations Free 1.1, Rig_Medium | Five categories; matched same-author rest poses; horizontal root motion removed |
| `wolf.glb` base mesh | crownjoshua, OpenGameArt `Wolf_1.zip` | Repaired legacy bind space, mirror, normalized top-four weights, clean FK rig; all 13 clips and collar/face details authored here |
| Thirteen `nature/` models and atlas | Kay Lousberg, Forest Nature Pack Free 1.0 | Original geometry and atlas unchanged; runtime scale/orientation and muted palette shader |

Source pages: [Adventurers](https://kaylousberg.itch.io/kaykit-adventurers), [Animations](https://kaylousberg.itch.io/kaykit-character-animations), [Forest Nature](https://kaylousberg.itch.io/kaykit-forest), [Wolf](https://opengameart.org/content/wolf-low-poly-rigged).

`boar.glb`, `lurker.glb`, `spider.glb` and `swarm.glb` are original project meshes, skins, rigs and 13 clips per family, reproducible with `tools/build_creature_assets.py`. Hex geometry, soil/surface shaders, ruins, reeds, ocean, palette shaders and PCM audio are project code. No third-party scripts or external sound samples were introduced.

`portraits/` contains original illustrations generated with the built-in image_gen tool. The title illustration and two additional profession portraits were generated on 2026-11-05. Art direction is recorded in `portrait-prompts.md`. Noto Sans SC is from [google/fonts](https://github.com/google/fonts/tree/main/ofl/notosanssc), under `fonts/OFL.txt`.

`story/` contains original widescreen scene illustrations generated with the built-in image_gen tool. The three `opening-*.png` images paint the protagonist into each opening scene. Other images provide locations and terrain backdrops for the game's character portraits.

`ui/inventory-items.png` contains original item icons generated with the built-in image_gen tool. The inventory uses shared icons for the three equipment slots and for relics.

`portraits/mattes/` contains grayscale opacity masks derived from the existing portraits using U²-NetP and refined around clothing and props. The dialogue shader uses the original portrait colors and samples these masks for opacity only.

Godot and its components retain their notices in `licenses/`. Standard export templates are used. No editor, Blender, original download archive, access token or paid source pack is shipped.
