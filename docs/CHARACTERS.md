# Characters, armour and gear: how they are made

This is the recipe for building heroes and their equipment, so the next hero,
armour or helmet is made the same way. Everything is driven by the JSON files
in `data/`; the tools in `tools/` turn those recipes into models.

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
| `clothes` | list of `{"id": "<outfit name>", "asset": "<mhclo name>", "push": metres}`; `push` lifts a layer off the one beneath (e.g. boots over trousers, 0.004) |
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
5. renames each clothing mesh to `outfit_<id>`, builds rigid pieces
   (`outfit_<id>` as well), exports a `.glb`.

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

## 4. Equipment shows outfits (`data/items.json`)

An armour item lists the outfit meshes it turns on:

    "chain_mail":  "visual": {"outfits": ["tunic_mail", "gloves_leather"]}
    "plate_armor": "visual": {"outfits": ["tunic_mail", "cuirass", "gloves_leather"]}

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

Close-up test: `LM_ITEMS="head:great_helm,off_hand:kite_shield" LM_PLAN=helms`.

## 6. Getting assets

* MakeHuman asset packs (CC0 / CC-BY): static.makehumancommunity.org/assets/assetpacks
  - system assets, skins01/02, hair01/02, eyebrows01, eyelashes01, bodyparts05/06
  (beards), suits02/05, shoes03, gloves01. Unzip into the MPFB user data folder.
* Sketchfab (logged in, CC-BY or CC0 only, downloadable): get the **glb at 1024**
  textures. Save under `assets/gear/<name>.glb` and add a line to
  `assets/gear/license.txt` and `CREDITS.md` (title, author, URL, licence).
* Mixamo animations: "Without Skin", "In Place"; they play on MakeHuman heroes
  through `scripts/game/retarget.gd` (A-pose vs T-pose handled automatically).

## 7. Lessons learned

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
  leg proportions sank ~8 cm before).
* Feet and toes are NOT direction-aligned in the retarget (both rest poses stand
  flat; aligning ankle-to-toe directions put the hero on tiptoe).

## 8. Known limits

* MakeHuman hair has see-through strands in some lights.
* Helmets do not hide hair yet (hair mesh should be hidden when a helmet is on).
* Arm and leg plates (bracers, greaves) are not added yet; use `fit` types for
  them when needed (one bone each: `LeftForeArm`, `LeftLeg` ...).
