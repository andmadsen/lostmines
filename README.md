# Lost Mines

Fan-made RPG based on *Lost Mine of Phandelver* — Baldur's Gate 2 style gameplay
(party, real-time with pause, D&D 5e rules), built in Godot 4.7.

Private fan project. *Lost Mine of Phandelver* belongs to Wizards of the Coast;
this game is not for sale or public release.

## Run it
Open the folder in Godot 4.7 and press **F5** (or the ▶ button).
The test scene starts: a cave passage, four heroes and three goblins.
Press **H** in-game for controls.

## Where things live
| Folder | What |
| --- | --- |
| `data/` | All game content as JSON: heroes, monsters, items. Edit while the game runs — it reloads within a second. |
| `scripts/autoload/` | `DataDB` (loads data) and `Rules` (dice, D&D rules). |
| `scripts/game/` | Units, figures and equipment, cave builder, camera, the test scene. |
| `scripts/ui/` | The Baldur's Gate style interface. |
| `scenes/` | Godot scenes. |
| `tests/` | Automated test harness (screenshots, scripted fights). |

## Status
Phase 0 — test scene. Figures are placeholders made of simple shapes; they will
be replaced by real models in the same equipment slots.
