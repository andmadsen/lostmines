extends Node
## D&D 5e rules helpers: dice, ability modifiers, attack resolution.

const ROUND := 6.0          ## seconds per combat round
const PROFICIENCY := 2      ## level 1-4

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


func d(sides: int) -> int:
	return rng.randi_range(1, sides)


## Rolls an expression like "2d6+3". Critical hits double the dice.
func roll(expr: String, crit := false) -> int:
	var e := expr.replace(" ", "")
	var re := RegEx.new()
	re.compile("^(\\d+)d(\\d+)([+-]\\d+)?$")
	var m := re.search(e)
	if m == null:
		return int(e)
	var n := int(m.get_string(1)) * (2 if crit else 1)
	var sides := int(m.get_string(2))
	var bonus := int(m.get_string(3)) if m.get_string(3) != "" else 0
	var total := bonus
	for i in n:
		total += d(sides)
	return maxi(total, 0)


func mod(score: int) -> int:
	return floori((score - 10) / 2.0)


func signed(n: int) -> String:
	return ("+%d" % n) if n >= 0 else str(n)
