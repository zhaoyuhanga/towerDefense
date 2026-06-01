class_name TowerData
extends Resource
## Tower configuration data resource.
## One .tres file per tower variant (tower_id + star_level combination).
## All tower attributes are data-driven per ADR-0002 — no hardcoded values.
##
## Usage:
##     var data := load("res://src/resources/towers/cannon_1.tres") as TowerData
##     print(data.attack)  # 20.0

## Unique identifier for this tower type (e.g. "cannon", "ice", "arrow").
@export var tower_id: String = ""

## Human-readable display name shown in UI tooltips and HUD.
@export var tower_name: String = ""

## Star level: 1, 2, or 3. Attack and range scale with star level.
@export var star_level: int = 1

## Base damage per attack. Must be 1.0–999.0. Monotonic by star within same tower_id.
@export var attack: float = 0.0

## Attacks per second. Higher = faster attack cycle.
@export var attack_speed: float = 1.0

## Targeting range in pixels. Monsters within this radius are eligible targets.
@export var range: float = 0.0

## Special effect numeric parameter. Meaning depends on attack_type:
## - "aoe": splash radius in cells (0 = no splash)
## - "slow": speed multiplier applied to target (0.5 = 50% slow)
## - "pierce": number of additional targets pierced (3 = pierces 3 extra targets)
@export var special_value: float = 0.0

## Duration in seconds for temporary effects (slow duration, etc.). 0 for instant effects.
@export var effect_duration: float = 0.0

## Gold cost to place this tower on the board.
@export var cost: int = 0

## Gold returned when selling this tower (typically cost / 2).
@export var sell_value: int = 0

## Attack type determining combat dispatch logic.
## Valid values: "normal", "aoe", "slow", "pierce"
@export var attack_type: String = "normal"

## Flavor description shown in tower info tooltip.
@export var description: String = ""
