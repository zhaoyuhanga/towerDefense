# TestMonster — Concrete Monster subclass for unit testing.
# Monster is @abstract and cannot be instantiated directly.
# TestMonster inherits all Monster method implementations and is used
# both for direct unit tests (TestMonster.new()) and programmatic
# PackedScene instantiation (for pool lifecycle tests).
class_name TestMonster
extends Monster
