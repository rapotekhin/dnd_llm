class_name FightAnim
extends Node2D
## One animation of a fight on the map (v0.8.4.23): the contract a stub and a real animation share. `FightAnims` makes it, adds it
## over the map and calls `play(ctx)`; it emits `finished` when done and is freed. A real one is a scene whose root extends this
## class, named in its kind's row of `data/anims.json` (`scene`); nothing else changes.
##
## ctx: {anim, phases [{phase, stub, at, time, loop}], from, to, beside: Vector2 (pixels on the map), cells: Array[Vector2],
##   tile: float, colour: Color, n: int (darts, rays), result, miss, sprite, proj, speed (× of the phases' time),
##   frames: SpriteFrames or null, art: {sprite id: Texture2D}}.
## Phases: windup at the doer, travel from the doer to the target (looped while it flies), hit at the target, the area or the
## path, linger, fade. A phase's place: `by` the doer, `to` the target, `path` from one to the other, `cells` the area,
## `beside` where a miss falls.

signal finished

var ctx: Dictionary = {}


func play(c: Dictionary) -> void:
	ctx = c
	await get_tree().process_frame
	finished.emit()


## The seconds a phase lasts at the speed of the fight.
func seconds(p: Dictionary) -> float:
	return maxf(0.01, float(p.get("time", 0.2)) * float(ctx.get("speed", 1.0)))


## Where a phase stands: its point on the map.
func point(at: String) -> Vector2:
	match at:
		"by":
			return ctx["from"]
		"beside":
			return ctx["beside"]
		"cells":
			var cells: Array = ctx.get("cells", [])
			if cells.is_empty():
				return ctx["to"]
			var sum := Vector2.ZERO
			for c: Vector2 in cells:
				sum += c
			return sum / float(cells.size())
	return ctx["to"]
