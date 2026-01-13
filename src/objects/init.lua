--[[
    Objects Module - Game object class hierarchy

    This module exports the complete class hierarchy for game objects,
    ported from the original C&C source code.

    Class Hierarchy:
        AbstractClass
            └── ObjectClass
                    └── MissionClass
                            └── RadioClass
                                    └── TechnoClass (TODO)
                                            ├── FootClass (TODO)
                                            │       ├── InfantryClass (TODO)
                                            │       ├── UnitClass (TODO)
                                            │       └── AircraftClass (TODO)
                                            └── BuildingClass (TODO)
]]

local Objects = {}

-- Class system
Objects.Class = require("src.objects.class")

-- Base class hierarchy
Objects.AbstractClass = require("src.objects.abstract")
Objects.ObjectClass = require("src.objects.object")
Objects.MissionClass = require("src.objects.mission")
Objects.RadioClass = require("src.objects.radio")

-- TODO: Add these when implemented
-- Objects.TechnoClass = require("src.objects.techno")
-- Objects.FootClass = require("src.objects.foot")
-- Objects.InfantryClass = require("src.objects.infantry")
-- Objects.UnitClass = require("src.objects.unit")
-- Objects.AircraftClass = require("src.objects.aircraft")
-- Objects.BuildingClass = require("src.objects.building")
-- Objects.BulletClass = require("src.objects.bullet")
-- Objects.AnimClass = require("src.objects.anim")

return Objects
