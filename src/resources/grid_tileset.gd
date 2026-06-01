# GridTileset — Grid visual configuration resource (ADR-0005)
# Data-driven tile appearance: colors, cell size, phase opacities.
# Paired with grid_tileset.tres for editor-level tuning.
class_name GridTileset
extends Resource

## Cell fill colors — indexed by CellState enum value (0=EMPTY, 1=BLOCK, 2=TOWER, 3=ENTRANCE, 4=EXIT)
## Defaults per art-bible.md: #263040 base, #4A6078 grid lines
@export var cell_fills: PackedColorArray = [
	Color("263040"),  # EMPTY — dark slate blue (art-bible Section 4.1)
	Color("3A5060"),  # BLOCK — subtly lighter for distinction
	Color("5A7A9A"),  # TOWER — steel blue tower base
	Color("3A7A3A"),  # ENTRANCE — green marker
	Color("8A3A3A"),  # EXIT — red marker
]

## Grid line color — shared across all tiles to form continuous grid lines (art-bible Section 3.2)
@export var grid_line_color: Color = Color("4A6078")

## Grid line width in pixels (1–2px per GDD board-grid.md)
@export var grid_line_width: int = 1

## Pixel size of each grid cell — must match BoardGrid.cell_size (56 per GDD D.1)
@export var cell_size: int = 56

## Grid opacity during PREP phase (70–80% per GDD)
@export var prep_opacity: float = 0.8

## Grid opacity during BATTLE phase (~60% per GDD)
@export var battle_opacity: float = 0.6
