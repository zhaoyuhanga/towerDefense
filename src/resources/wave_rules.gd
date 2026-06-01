class_name WaveRules
extends Resource
## Wave configuration rules for a range of wave numbers.
## Contains an array of SpawnRule resources defining the spawn schedule.
## WaveRules files are loaded per wave range and applied by the WaveSpawner system.
##
## Usage:
##     var rules := load("res://src/resources/waves/wave_1_5.tres") as WaveRules
##     for spawn_rule in rules.rules:
##         print(spawn_rule.monster_id, ": ", spawn_rule.count)

## Ordered array of spawn instructions executed sequentially within the wave.
@export var rules: Array[SpawnRule] = []

## Starting wave number this ruleset applies to (inclusive).
@export var wave_range_start: int = 1

## Ending wave number this ruleset applies to (inclusive).
@export var wave_range_end: int = 1
