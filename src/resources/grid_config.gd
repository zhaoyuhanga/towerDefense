class_name GridConfig
extends Resource
## Grid sizing constants — data-driven via .tres (ADR-0002).
## ORIGIN_X and ORIGIN_Y are computed at runtime from window size.

@export var cell_size: int = 56
@export var grid_cols: int = 20
@export var grid_rows: int = 15
