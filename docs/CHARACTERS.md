# Characters, armour and gear: how they are made

(The design rules - style, races, party colours, the step-by-step recipe and
the checklist - are in `docs/CHARACTER_DESIGN.md`. This file is the technical
reference.)

This is the recipe for building heroes and their equipment, so the next hero,
armour or helmet is made the same way. Everything is driven by the JSON files
in `data/`; the tools in `tools/` turn those recipes into models.

## 0. Folder structure (`assets/`, not in git)

    animations/   onehand, onehand_shield_pack, twohand_pack, bow, bow_pack,
                  spell_pack, heal          (Mixamo, "Without Skin")
    characters/   <hero>.fbx (Mixamo) or <hero>_mh.glb (built by tools/build_hero.py)
                  + the textures Godot extracts from them (keep them)
    monsters/     <monster>/  model, textures/, license.txt
    weapons/      older hand-picked weapons, one folder each (scene.gltf ...)
    gear/         Sketchfab library: armour, helmets, weapons, shields (.glb) + license.txt
    textures/     cave_wall, cave_floor (Poly Haven)
    _unused/      no longer used; ignored by Godot (.gdignore) - safe to delete

Monsters with weapons use the same animation sets as heroes
(`look.animation_set: "auto"`).

## 1. Overview

| Layer | Where it comes from | How it follows the body | Example |
|---|---|---|---|
| Body, face, hair, eyes | MakeHuman (MPFB2 in Blender) | skinned to the "mixamo" rig | Aurelia's body |
| Cloth (shirts, tunics, trousers, boots, gloves, robes) | MakeHuman clothes (`.mhclo`) | fitted and skinned by MakeHuman, perfect fit | `tunic_mail`, `pants`, `boots_riding` |
| Rigid armour (cuirass, pauldrons, bracers, greaves) | Sketchfab models in `assets/gear/` | fitted once, then each vertex follows ONE bone 100% | `cuirass` |
| Hand-held and head gear (weapons, shields, helmets, torch) | Sketchfab models in `assets/gear/`, `assets/weapons/` | attached in Godot to a bone slot (BoneAttachment3D) | longsword, kite shield, great helm |

**Do not** use whole one-piece Sketchfab outfits (e.g. a full armour suit with
sleeves and skirt) as skinned clothing. They are made for a different body in a
different pose; their sleeves get the wrong bones and stick out. (Tried with
"Female Noble Knight Armor" on 2026-11-15: the arms floated.) Use MakeHuman
cloth for anything that bends, and rigid pieces for plates.

## 2. Heroes (`tools/build_hero.py`)

Needs Blender's Python module `bpy` and the MPFB2 extension with the
MakeHuman asset packs (see section 6). Run:

    python3 tools/build_hero.py aurelia

It reads `heroes.json -> heroes[aurelia].body` and writes
`assets/characters/aurelia_mh.glb`. Set `look.model` to that file.

`body` recipe:

| key | meaning |
|---|---|
| `gender, age, muscle, weight, height, proportions, cupsize, firmness` | MakeHuman macros, 0..1 (gender 0 = female, 1 = male) |
| `race` | `{"african": .., "asian": .., "caucasian": ..}` |
| `skin` | a skin from the skins packs, e.g. `toigo_light_skin_female_bronze` |
| `eyes, eyebrows, eyelashes, teeth, tongue, hair` | MakeHuman asset names, e.g. `low-poly`, `elvs_daisy_hair` |
| `targets` | extra MakeHuman body targets with weights, e.g. `{"legs/measure-upperleg-height-decr": 0.9}` (files in MPFB `data/targets/<group>/`). Keldrin uses them for short legs, broad shoulders, short neck, square head |
| `clothes` | list of `{"id": "<outfit name>", "asset": "<mhclo name>", "push": metres, "scale": [w, d, l]}`; `push` lifts a layer off the one beneath (e.g. boots over trousers, 0.004); `scale` enlarges a piece about its top-back-centre (moustache) |
| `panels` | generated cloth panels (tabards), section 3b |
| `beards` | generated full beards with braids, section 3c |
| `outfits` | generated cloth layers (`under_top`, `under_legs`, `boots`, `gloves`, `leather`, `chain`) - fallback only |
| `rigid` | rigid armour pieces, see section 3 |

What the builder does, in order:
1. creates the human from the macros, sets the skin, adds the **mixamo** rig;
2. adds eyes, brows, lashes, teeth, tongue, hair and every `clothes` entry;
3. removes MakeHuman's skin-hiding masks (clothes can be taken off in game);
   instead the skin each garment covers is split off as `body_hide_<id>` and the
   game hides it while that garment is worn (no toes through boots);
4. makes an export copy, snaps eyes/lashes to the final face, freezes the body
   shape (shape keys applied) so Godot shows exactly what Blender built;
5. renames each clothing mesh to `outfit_<id>`, builds rigid pieces, panels
   and beards (`outfit_<id>` as well);
6. moves the whole figure so the soles stand at zero (leg targets and the
   lowest height lift the feet; skin hidden under boots counts too), exports a `.glb`.

Quick look without the game: `python3 tools/preview_hero.py <glb> <out.png> pants,boots,beard,...`
renders front, side, back, 3/4 and the face with only the listed outfits.

Every outfit mesh is in the file; the game shows only the ones the equipment
asks for (section 4).

Asset names: browse with a contact sheet (`.thumb` files) in
`~/.config/blender/<ver>/extensions/.user/user_default/mpfb/data/<clothes|hair|skins>/`.

## 3. Rigid armour

A `rigid` entry:

    {"id": "cuirass", "file": "armor_avacynian.glb", "fit": "torso",
     "turn": -90, "scale": 1.5, "up": -0.06, "grow": false,
     "material": "steel", "color": [0.8, 0.82, 0.86]}

| key | meaning |
|---|---|
| `fit` | `torso` (cuirass incl. pauldrons and belt), `chest` (breastplate only), `shoulders` (a pauldron pair) |
| `turn` | degrees about the vertical axis so the piece faces the same way as the body (-Y in Blender). Check with a Blender preview: many Sketchfab models face +X (`turn: -90`) |
| `scale` | size factor on top of the automatic fit (torso: from body depth; chest: torso width; shoulders: shoulder width) |
| `up`, `forward` | metres to move it after fitting |
| `grow` | `true` = enlarge step by step until the body no longer pokes through (works for closed shells; switch off for pieces with open sides) |
| `material`, `color` | replace the model's own material with the project's `steel`/`leather`/`chain`/`cloth` look (use when the model's texture is low-res or off-colour) |
| `drop` / `keep` | mesh names in the file to leave out / to use only (e.g. take just the `chestplate` of a full armour suit) |
| `depth` | extra front-to-back size, room for the chest (1.15) |
| `taper`, `taper_gap` | pull the lower part (share of the height, e.g. 0.45) in to the waist, `taper_gap` metres off the body - stops plates flaring at the bottom |
| `shoulders_only` | with `fit: torso`: keep only the pauldron parts of a cuirass |

Bone assignment (`fit: torso`): pauldron parts -> `LeftShoulder`/`RightShoulder`,
chest -> `Spine2`, middle -> `Spine1`, belt -> `Hips`. Each vertex follows one bone
fully, so plates never stretch.

Tuning loop: build, render a Blender preview (front + side) with the body and
the piece in flat colours, adjust `scale`/`up`/`turn`, repeat. Then check in game
from four sides and walking (tests: `LM_PLAN=gearclose`, `LM_PLAN=walkseq`).

## 3b. Panels (tabards)

    "panels": [{"id": "tabard", "top": 0.15, "bottom": 0.1, "width_top": 0.3,
                "width_bottom": 0.24, "gap": 0.012, "back": true,
                "color": [0.56, 0.51, 0.40], "trim": [0.55, 0.39, 0.13],
                "emblem": "anvil", "emblem_y": 0.17, "emblem_y2": 0.7}]

A grid is laid over the front (and back: `outfit_<id>_back`) of the dressed body
(clothes and rigid plates included), `gap` metres off it. `top` is a share of the
way from Spine2 to the neck, `bottom` a share from the knee up to the hips.
Above the belt it follows the chest; below it hangs straight and follows the
hips plus a share (`legs`, 0.35) of both thighs. It is painted with `color`, a
`trim` border and an `emblem` (`anvil`; add more outlines in `EMBLEMS`).

Capes use the same generator with `"sides": ["back"]` and a shaped top:
`neck_width` (width at the neck), `shoulder_drop` (how far down the shoulders
widen to `width_top`), `width_bottom` (flare at the hem), `columns` (more for
folds), `folds` + `fold_depth` (soft vertical folds deepening to the hem),
`belt` (metres above the hips where it starts to hang straight; higher =
looser over the back), `flare` (metres the hem falls away from the body),
`gap`, `legs` (how much the hem follows the thighs). Pip:

    {"id": "cape", "sides": ["back"], "top": 0.95, "bottom": -0.35,
     "neck_width": 0.14, "shoulder_drop": 0.09, "width_top": 0.34, "width_bottom": 0.44,
     "belt": 0.42, "gap": 0.02, "bones": {"chains": 5, "segments": 4},
     "columns": 31, "folds": 6, "fold_depth": 0.04, "legs": 0.25,
     "color": [0.22, 0.31, 0.15], "trim": [0.62, 0.47, 0.17], "border": 0.05}

**Hanging cloth that moves (spring bones).** A rigidly weighted cape tips with
the hips and stands off the back like a board. Give the panel bones:

    "bones": {"chains": 5, "segments": 4, "parent": "Spine2"}

The builder adds chains of bones `<id>_<chain>_<segment>` down the hanging part
(below `belt`) and weights the cloth to them. In game `look.springs` simulates
them with gravity (Godot's SpringBoneSimulator3D), with capsules around hips,
lower back and legs so the cloth stays out of the body:

    "springs": [{"bones": "cape", "stiffness": 0.6, "drag": 0.5, "gravity": 1.5, "radius": 0.02}]

Less `stiffness` = looser; more `drag` = calmer. Use no `flare` with bones -
gravity decides how it falls. The same works for robes, tabard tails or hair.

## 3c. Beards

    "beards": [{"id": "beard", "length": 0.3, "thickness": 0.05, "top": 0.03,
                "width_top": 0.095, "width_bottom": 0.035, "color": [0.42, 0.17, 0.07],
                "braids": [{"x": -0.038, "radius": 0.017, "start": -0.03},
                           {"x": 0.038, "radius": 0.017, "start": -0.03}]}]

Rings from the cheeks (`top` metres above the mouth) to `length` below the
chin, wrapped over the face and chest, `thickness` thick, narrowing from
`width_top` to `width_bottom` (half-widths). The lips stay free; below the chin
it hangs straight. Braids are plaited lumps with metal rings (`ring_color`),
laid on the beard at `x`. The face part follows the head, the hanging part the
chest. Hair-strand texture is painted in `color` (no tint needed). MakeHuman's
own beards are thin cards that cannot be made full - use this for dwarves.

## 3d. Props (quiver)

    "props": [{"type": "quiver", "id": "quiver", "x": -0.05, "up": -0.06, "tilt": -28,
               "length": 0.42, "radius": 0.045, "arrows": 7, "color": [0.5, 0.3, 0.16]}]

A leather quiver with arrows on the back (on top of a cape), slanted by `tilt`
degrees (negative: top over the right shoulder), rigid on Spine2.

Generated outfits (`under_top`, `leather`, `chain`, `plate`) are smoothed so
they do not follow every curve of the body (`SMOOTH` in `build_hero.py`), and
their edges (neckline, armholes, hem) are trimmed and relaxed into smooth
lines (`_smooth_edges`) - cut by bone they would zigzag.

## 4. Equipment shows outfits (`data/items.json`)

An armour item lists the outfit meshes it turns on:

    "chain_mail":  "visual": {"outfits": ["tunic_mail", "gloves_leather"]}
    "plate_armor": "visual": {"outfits": ["tunic_mail", "cuirass", "gloves_leather"]}

A hero can replace the list for one item with `look.armor_outfits`, e.g. Keldrin:
`{"chain_mail": ["tunic_mail", "pauldrons", "gloves_leather"]}`.

A hero's `look.outfits_always` lists what is always worn (e.g. `pants`,
`boots_riding`). With no armour the generated `under_top` shirt is shown.
`look.tints` adjusts a mesh by name: a colour (`"hair": "#4a2e1c"`) tints it, a
number (`"tunic_mail": 2.2`) brightens it.

## 5. Weapons, shields, helmets (Godot, `scripts/game/model_fit.gd`)

Downloaded models are fitted at run time from the item's `visual`:

* weapons: `model`, `length` (m), `grip` (0..1 along the blade axis or auto),
  `flip`, `hand` (`left` for bows/crossbows), `sheathe` (`true` = back, `"hip"`, `false`),
  `brightness`, `metallic`;
* shields: `model`, `size` (m), `offset` [x,y,z], `rotation`, `flip`;
* helmets: `model`, `size` (width in m), `offset`, `rotation` (turn until the
  visor faces forward: try 0, 90, -90), `brightness`, `metallic`.

Where gear sits: grips in `animations.json` (`right`, `left`, `back`, `hip`,
`head`) are tuned on Mixamo models. On MakeHuman heroes (other bone axes,
A-pose) `Retarget.slot_correction` turns each slot so the item sits exactly as
it would on the Mixamo model - no separate tuning needed. `look.grip` can still
override a slot for one hero.

* One-handed melee weapons hang at the LEFT hip by default (drawn with the right
  hand); two-handed weapons go on the back; bows/crossbows stay in hand
  (`sheathe` overrides: `true` = back, `"hip"`, `false`).
* Shields: strapped ACROSS the left forearm while the weapon is drawn (grip
  `shield` in the animation set: position on the forearm, `turn: 90` turns it
  about its face so it stands upright in the guard pose, `spin` turns it about
  its long axis to choose which side faces out). While the weapon is put away
  the shield hangs on the back (grip `shield_back` on Spine2: `[0, 0, 0.03]`,
  rotation `[0, 90, 180]`, `spin: 180`). Per shield, `rotation` turns it about
  its own face until the point is down and `flip` makes the painted side face
  out (most models need neither).
* Check shields in both states: `LM_EQUIP=off_hand:<shield> LM_PLAN=gearclose`
  (drawn) and the same with `LM_SHEATHED=1` (on the back).

Close-up test: `LM_ITEMS="head:great_helm,off_hand:kite_shield" LM_PLAN=helms`.

## 6. Animations

Mixamo packs live in `assets/animations/<pack>/` (onehand, onehand_shield_pack,
twohand_pack, bow_pack, spell_pack). They work on every hero (retargeting).

* An animation set in `data/animations.json` lists `idle`, `walk`, `attack`,
  `death`, `cast`; `attack` may be a list - each swing picks one at random.
* `look.animation_set: "auto"` picks the set from what the hero holds, through
  the `auto` table: `one_hand`, `shield` (one-hander + shield), `two_hand`,
  `bow`, `unarmed`. Changing weapons changes the set at once.
* While the weapon is put away the hero uses a relaxed `idle_calm` /
  `walk_calm` (per set, or the shared `calm` entry: unarmed idle and walk);
  the combat idle/walk come back when the weapon is drawn. Bows stay drawn.
* Root motion is removed on load: walks keep their sway, attacks and deaths
  stay on the spot. The walk speed is measured from the walk's own travel, so
  feet do not slide.

## 7. Getting assets

* MakeHuman asset packs (CC0 / CC-BY): static.makehumancommunity.org/assets/assetpacks
  - system assets, skins01/02, hair01/02, eyebrows01, eyelashes01, bodyparts05/06
  (beards), suits02/05, shoes03, gloves01. Unzip into the MPFB user data folder.
* Sketchfab (logged in, CC-BY or CC0 only, downloadable): get the **glb at 1024**
  textures. Save under `assets/gear/<name>.glb` and add a line to
  `assets/gear/license.txt` and `CREDITS.md` (title, author, URL, licence).
* Mixamo animations: "Without Skin", "In Place"; they play on MakeHuman heroes
  through `scripts/game/retarget.gd` (A-pose vs T-pose handled automatically).

## 8. Lessons learned

* Spikes from hands/feet: MakeHuman sometimes gives a few clothing vertices a
  little weight on a far bone (a glove vertex on the shoulder). The builder
  removes influences more than 0.3 m from their bone (`clean_weights`, hair is
  skipped), keeps 4 per vertex and renormalises.
* Pick clothes made to be worn together (the `rehmanpolanski_viking_*` tunic,
  trousers and boots fit each other). Mixing packs gives z-fighting where
  layers overlap; `push` helps a little.
* Check the texture before choosing a garment: some are black (punkduck riding
  boots) and disappear in the cave light.
* Dark textures can be lifted with a numeric tint (`"tunic_mail": 1.5`); above
  ~2 colours drift (blue sleeves).
* Low-res or odd-coloured armour textures: use `material: "steel"`.

* Aurelia's plate: the feminine chestplate (`keep: chestplate`) of "Female Noble
  Knight Armor" + the pauldrons of "Avacynian Knight Armor" (`shoulders_only`).
* Feet on the floor: `retarget.gd` shifts the hips per animation so the lowest
  foot stays as high above the floor as in the Mixamo source (bodies with other
  leg proportions sank ~8 cm before). It compares how far the foot *lifts off
  its rest height* (scaled by hip height), never the raw foot height: scaling
  raw heights blew jumps and death falls up by metres (the hero "jumped out of
  the screen").
* Check every set after changing the retarget: `LM_PLAN=rootcheck` prints any
  animation where the hips leave the spot (> 0.25 m) or rise above 1.6 m;
  add `LM_FEET=1` for the average foot height in idle/walk (should be ~0-4 cm).
* Feet, toes and the trunk (hips, spine, neck, head) are NOT direction-aligned
  in the retarget: they stand the same way in both rest poses. Aligning feet put
  heroes on tiptoe; aligning the trunk tilted Keldrin's chest 30 degrees forward
  and sank his head into it (short neck, deep chest). Only arms and legs are aligned.
* Hero meshes always draw at full detail (`lod_bias` 1000 in `unit_visual.gd`).
* `LM_PLAN=outfits LM_HERO=<n>` lists which meshes a hero shows.

* Helmets are not drawn for now (`data/settings.json` → `"show_helmets": false`).
  They still count in the rules and show in the character sheet; set it to
  `true` to draw them again (fitting is in `items.json`, `visual` of each helmet).

## 9. Known limits

* MakeHuman hair has see-through strands in some lights.
* Helmets do not hide hair yet (hair mesh should be hidden when a helmet is on).
* Arm and leg plates (bracers, greaves) are not added yet; use `fit` types for
  them when needed (one bone each: `LeftForeArm`, `LeftLeg` ...).
