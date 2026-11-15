# Outdoor maps

Outdoor levels are built at start-up from `data/maps/<id>.json` by
`scripts/game/terrain_builder.gd`. The level script (`scripts/game/forest_road.gd`)
reuses all of the cave test's game logic (party, camera, combat, interface);
only the world is different. `scenes/forest_road.tscn` is the main scene (F5);
the cave is still in `scenes/test_cave.tscn` (open it and press F6).

Coordinates are metres: `x` across, `z` along the map (north is z = 0).

| key | meaning |
|---|---|
| `size` | `[x, z]` metres |
| `height` | `seed`, `amplitude` (m), `frequency` (hills), `bank_height`/`bank_width`: the road runs in a cut between banks |
| `road` | `width` and `points` (a line through the map); the ground is flattened along it |
| `ground` | five textures from `assets/nature/textures/`: base (grass), forest floor, road, muddy verge, rock on slopes; `tile_metres` = how big one tile of the texture is |
| `scatter` | rules that spread models over the map (below) |
| `props` | single models placed by hand: `model`, `at` [x, z], `turn` (degrees), `scale` or `size` (longest side in metres), `block`/`hide` radius |
| `party` | four start positions [x, z] |
| `monsters` | `{"id": "goblin", "at": [x, z]}` |
| `intro` | lines written in the chronicle at the start |

A scatter rule:

| key | meaning |
|---|---|
| `models` | names; looked up in `assets/nature/split/` (trees and rocks from the packs), `assets/nature/models/<n>/` (Poly Haven) and `assets/nature/models_sf/` |
| `density` | copies per square metre |
| `min_road` / `max_road` | distance from the road (keep big trees at 9+ m or their crowns hide the road from the camera) |
| `forest` | `[min, max]` forest amount (0 = open grass, 1 = deep forest) |
| `scale` | random size range |
| `block` | radius that cannot be walked through (trunks, rocks) |
| `hide` | radius that blocks sight (thickets): monsters standing in a thicket can see out but are not seen |
| `spacing` | keep this far from other blockers |
| `multimesh` | `true` for small plants in large numbers (grass, ferns) |

The same seed always gives the same map. Change `height.seed` for another
layout of hills and trees.

Tree and rock packs from Sketchfab are split into single models with
`python3 tools/split_pack.py` (list in the script); each stands on the origin
in metres, textures shared in `split/textures/`.

Tests: `LM_SCENE=forest_road LM_PLAN=view LM_FOCUS=32,47 LM_DIST=18 LM_PITCH=-45`
renders a still; `LM_SCENE=forest_road LM_PLAN=ambush` (run headless) walks
the party into the ambush and prints the fight.
