class_name SkillConfig
extends Resource
## Emergency skill configuration data resource.
## One .tres file per skill. All skill properties data-driven per ADR-0002.
## Referenced by EmergencySkills system at game init.
##
## Usage:
##     var config := load("res://src/resources/skills/freeze.tres") as SkillConfig
##     print(config.max_uses)  # 3

## Unique identifier for this skill (e.g. "freeze", "repair").
@export var skill_id: String = ""

## Human-readable display name shown on the skill button.
@export var skill_name: String = ""

## Duration in seconds the skill effect lasts once activated.
@export var duration: float = 0.0

## Cooldown in seconds between consecutive activations of this skill.
@export var cooldown: float = 0.0

## Maximum number of uses of this skill across the entire game session.
## 0 = skill unavailable. Per-wave replenishment adds uses back.
@export var max_uses: int = 0

## Numeric effect magnitude. Meaning depends on skill:
## - "freeze": unused (freeze always sets speed=0)
## - "repair": HP restored to defense
@export var effect_amount: float = 0.0

## Number of uses replenished at the start of each wave.
@export var per_wave_replenish: int = 0
