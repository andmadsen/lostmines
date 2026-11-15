# Character design framework

How every hero (and later every NPC) is designed and built, so the party looks
like one game. This document is the *what and why*; `docs/CHARACTERS.md` is
the technical reference (every recipe key, tool and test).

Aurelia is the reference character: when in doubt, match her.

---

## 1. Style pillars

1. **Grounded fantasy realism.** Real human proportions and real materials
   (steel, mail, leather, wool, linen), like Pathfinder: WotR / Solasta. No
   cartoon proportions, no glowing sci-fi parts, no oversized shoulder pads.
2. **One body system.** Every hero is a MakeHuman body on the same "mixamo"
   rig. Same skin shader, same eye and hair quality, same scale of detail.
   Never mix in a model from another source for a hero.
3. **Read at game distance.** The camera is 8-15 m away. Each hero needs one
   strong silhouette idea and one or two colour accents that can be told apart
   at a glance (see section 4). Small details (rings, stitching) are a bonus,
   not the design.
4. **Gear tells the story.** Body, face and hair are fixed; what the hero wears
   comes from the equipment in the game. Armour, weapons and shields must be
   swappable without rebuilding the hero.
5. **Lit by torches.** Caves are dark and orange. Avoid near-black textures;
   prefer mid-value colours that keep their hue under warm light.

## 2. The layer model

Every hero is built from the same five layers, from the skin outwards:

| # | Layer | Source | Swappable in game | Examples |
|---|---|---|---|---|
| 1 | Body, face, eyes, hair, beard | MakeHuman macros + assets | no (part of the hero) | Aurelia's face, Keldrin's beard |
| 2 | Base clothes | MakeHuman cloth (`.mhclo`), skinned | always worn (`outfits_always`) | trousers, boots |
| 3 | Body armour (soft) | MakeHuman cloth, skinned | shown by the armour item | mail tunic, leather, gloves |
| 4 | Plates and panels | rigid Sketchfab plates / generated panels, one bone per vertex | shown by the armour item or always | cuirass, pauldrons, tabard |
| 5 | Held and worn gear | Sketchfab models, attached to bone slots at run time | yes, per item | sword, shield, helmet (hidden for now) |

Rules:

* Anything that **bends** (sleeves, trousers, skirts) is MakeHuman cloth.
* Anything **hard** (plates) is rigid and follows one bone.
* Nothing is merged into the body: every piece is its own `outfit_<id>` mesh,
  and the skin under it is hidden only while it is worn.
* Prefer garments made to be worn together (one creator's set, e.g. the
  `rehmanpolanski_viking_*` tunic, trousers, boots, beard). Mixing sets gives
  clipping where layers overlap.

## 3. Races (proportions in MakeHuman macros)

All macros are 0..1. `look.scale` scales the finished model in game.
Target heights are for the finished hero in game.

| Race | Target height | gender / age | muscle / weight | height macro | proportions | `look.scale` | Notes |
|---|---|---|---|---|---|---|---|
| Human | 1.65-1.85 m | by hero | 0.5-0.7 / 0.5 | 0.5-0.7 | 0.6-0.8 | 1.0 | Aurelia: 0.0 / 0.52, 0.68 / 0.52, 0.62, 0.7 |
| Dwarf | 1.20-1.35 m | 1.0 / 0.75 | 0.9 / 0.85 | 0.0 | 0.1 | 0.92 | plus `targets`: upper/lower leg height decr 0.9/0.7, shoulder dist incr 0.7, torso horiz/depth incr 0.4, neck height decr 0.8, head-square 0.6, upperarm circ incr 0.6; generated beard. Keldrin: 1.37 m built, ~1.26 m in game |
| Halfling | 0.95-1.05 m | by hero / 0.4 | 0.4 / 0.5 | 0.0 | 0.3 | ~0.62 | child-like proportions are wrong: adult face, just small |
| High Elf | 1.70-1.85 m | by hero / 0.4 | 0.35 / 0.3 | 0.7 | 0.9 | 1.0 | slim, long neck; pointed ears (needs an ear asset) |
| Goblin (monster) | ~0.9 m | - | - | - | - | per model | Sketchfab model, same animations |

A dwarf is *not* a scaled-down human: get the stockiness from the macros
(muscle, weight, proportions) and only then shrink with `look.scale`.

## 4. Party identity (silhouette + colours)

| Hero | Silhouette idea | Main colours | Accent | Reference |
|---|---|---|---|---|
| Aurelia (human fighter) | tall, steel chest, long sword, loose dark hair | steel grey, dark brown leather | warm bronze skin | `reference/Aurelia Dawnblade.png` |
| Keldrin (dwarf cleric) | wide and low, huge red beard, pauldrons, long cream tabard | steel/bronze scale, dark leather | cream tabard with gold anvil of Moradin | `reference/Keldrin Ironfist.png` |
| Pip (halfling rogue) | small, hooded, bow | forest green hood, brown leather | green | `reference/Pip Swiftfoot.png` |
| Shirvani (high elf wizard) | slim, long robe, blond braid, staff | white robe | gold trim | `reference/Shirvani Everglow.png` |

No two heroes share a main colour. Gold is the "holy/arcane" accent (Keldrin,
Shirvani); steel the martial one (Aurelia).

## 5. Materials and colour

* Use the textures the assets come with; adjust with `look.tints`:
  a colour (`"hair": "#4a2e1c"`) tints, a number (`"tunic_mail": 1.5`) brightens.
  Keep brightening at or below ~2 (colours drift above).
* Rigid plates with poor or off-colour textures use the project material
  (`"material": "steel"`, `"color": [r, g, b]`). Bronze/gilded steel for
  holy warriors: `[0.78, 0.64, 0.42]`.
* Generated panels (tabards, sashes) are painted by the builder: cloth colour,
  a border colour and an emblem (section 7 of `CHARACTERS.md`).
* Hair and beards: natural colours, tinted per hero. Red/auburn: `#7a3418`.

## 6. Gear rules

* One-handed weapons hang at the **left hip**, two-handed weapons and staffs on
  the **back**, bows stay in hand. Shields are strapped to the left forearm.
* Weapon sizes are real sizes (longsword ~1.0 m, mace ~0.6-0.7 m, greatsword
  ~1.4 m); the fitter scales the model to `length`.
* Helmets are **not drawn** for now (`data/settings.json`); they count in the
  rules. Design faces and hair to be seen.
* Animations follow the weapon automatically (`animation_set: "auto"`); a hero
  needs no animation work.

## 7. Building a new hero, step by step

1. **Reference.** Put an image in `reference/<Name>.png`. Write down the
   silhouette idea, 2-3 colours and the signature details (section 4).
2. **Pick assets.** Make a contact sheet of candidate hair, beards, clothes and
   skins (the `.thumb` files in the MPFB data folders) and pick from the same
   set as the other heroes where possible. If nothing fits, download from the
   MakeHuman asset packs (CC0/CC-BY) or Sketchfab (CC-BY/CC0), and credit it.
3. **Write the recipe** in `data/heroes.json -> heroes[<id>].body`: macros from
   the race table, skin, hair, beard and clothes (each with an `id`), rigid
   plates, panels.
4. **Hook it to equipment.** `look.outfits_always` for what is always worn
   (trousers, boots, beard, tabard); armour items list their outfits in
   `items.json`; a hero may replace that list for one item with
   `look.armor_outfits` (e.g. Keldrin's chain mail adds pauldrons).
5. **Build:** `python3 tools/build_hero.py <id>` -> `assets/characters/<id>_mh.glb`;
   set `look.model` to it, `look.animation_set` to `"auto"`, `look.scale` from
   the race table.
6. **Preview in Blender** (front and side, flat colours) for plates and panels;
   tune `scale`, `up`, `forward`, `turn`.
7. **Test in game** (section 8). Fix, rebuild, repeat.
8. **Finish:** credits in `CREDITS.md` and `assets/gear/license.txt`, commit,
   copy to the PC.

## 8. Quality checklist (every hero, every change)

Look at the hero from four sides, standing and walking, armed and unarmed:

- [ ] Feet on the floor, not on tiptoe, not sinking (`LM_PLAN=rootcheck LM_FEET=1`: 0-4 cm).
- [ ] No animation lifts or slides the hero (`LM_PLAN=rootcheck` prints nothing for them).
- [ ] No skin through clothes; no spikes or stretched triangles (hands, armpits, knees).
- [ ] Plates sit on the body, do not flare, do not float when the arms move.
- [ ] Weapon at the left hip / back when put away, in the hand when drawn; shield on the forearm.
- [ ] Each armour item shows the right layers; taking armour off leaves a clean base outfit.
- [ ] Height matches the race table (`LM_PLAN=heights`).
- [ ] Readable at game distance in torchlight; colours match the party table.
- [ ] Portrait and character sheet look right.

Test plans (`tests/shot.gd`): `gearclose` (close-up from four sides; `LM_HERO`,
`LM_EQUIP`, `LM_SHEATHED`, `LM_DIST`, `LM_PITCH`, `LM_FOCUSY`), `walkseq`, `heights`,
`rootcheck`, `styles`, `sheet`, `ui`.

## 9. What we learned not to do

* Whole one-piece Sketchfab armour suits as skinned clothes: the sleeves float.
* Retargeting by copying bone rotations: A-pose vs T-pose breaks the arms; use
  the world-space retarget.
* Scaling raw foot heights between rigs: jumps and falls launched the hero
  metres up. Compare foot *lift* above rest instead.
* JPEG textures in the export: Godot failed to import them; export with `AUTO`.
* Near-black clothing textures: invisible in the cave.
* Leg-length targets lift the feet off the floor: the builder grounds the
  figure; check `LM_FEET=1` (0-4 cm).
* Direction-aligning the spine/neck between rigs: a dwarf's chest tipped
  forward and the beard vanished into the tunic. Only limbs are aligned.
* MakeHuman beards for dwarves: too thin; use the generated `beards`.
* Hair with a near-black texture cannot be tinted; pick a light (blond/grey)
  hair and tint it.
