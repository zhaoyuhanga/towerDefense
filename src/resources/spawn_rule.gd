class_name SpawnRule
extends Resource
## A single spawn instruction within a wave's ruleset.
## Defines what monster type to spawn, how many, and at what interval.
## Nested inside WaveRules as an Array[SpawnRule].

## Monster identifier to spawn. Must match a MonsterData.monster_id.
@export var monster_id: String = ""

## Number of monsters of this type to spawn.
@export var count: int = 0

## Time in seconds between consecutive spawns of this rule.
@export var spawn_interval: float = 1.0

## Pool of affix identifiers that may be applied (wave 26+).
## Empty array means no affixes available for this spawn rule.
@export var affix_pool: Array[String] = []

