class_name EconomyConfig
extends Resource
## Economy constants and multipliers — data-driven via .tres per ADR-0002.
## Single file: loaded once at game init, referenced by Economy system.
## All values validated at load time (positive, within safe ranges).
##
## Usage:
##     var config := load("res://src/resources/economy_default.tres") as EconomyConfig
##     EconomySystem.new_game(config.starting_gold)

## Initial gold granted to the player at the start of a new game.
@export var starting_gold: int = 200

## Gold cost to place a single block on the board.
@export var BLOCK_COST: int = 10

## Gold returned when selling/removing a block.
@export var BLOCK_SELL_VALUE: int = 5

## Gold cost to perform a tower merge operation.
@export var MERGE_COST: int = 0

## Maximum number of obstacle blocks allowed on the board simultaneously.
## Enforced by ObstacleBlock system; overrides the GDD-authoritative default (10).
@export var MAX_BLOCKS: int = 10

## Global multiplier applied to monster kill gold rewards.
## 1.0 = base reward, 2.0 = double reward.
@export var kill_reward_multiplier: float = 1.0
