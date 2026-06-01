class_name MonsterData
extends Resource
## Monster configuration data resource.
## One .tres file per monster type. All monster attributes are data-driven per ADR-0002.
##
## Usage:
##     var data := load("res://src/resources/monsters/goblin_standard.tres") as MonsterData
##     print(data.health)  # 50.0

## Unique identifier for this monster type (e.g. "goblin_standard", "orc_boss").
@export var monster_id: String = ""

## Human-readable display name shown in UI.
@export var monster_name: String = ""

## Base health points. Boss > Elite > Standard within related families.
@export var health: float = 0.0

## Movement speed in pixels per second.
@export var speed: float = 0.0

## Gold rewarded to the player when this monster is killed.
@export var reward_gold: int = 0

## Monster tier controlling health scaling and visual treatment.
## Valid values: "Standard", "Elite", "Boss"
@export var tier: String = "Standard"

## Visual size multiplier relative to base monster sprite (default 1.0).
@export var size_ratio: float = 1.0

## Whether this monster can spawn with random affixes (wave 26+).
@export var has_affix: bool = false
