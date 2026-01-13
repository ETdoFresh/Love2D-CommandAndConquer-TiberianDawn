--[[
    Mixins module - Multiple inheritance components for TechnoClass

    These mixins provide functionality that is composed into TechnoClass
    and its derivatives, emulating C++ multiple inheritance.
]]

return {
    FlasherClass = require("src.objects.mixins.flasher"),
    StageClass = require("src.objects.mixins.stage"),
    CargoClass = require("src.objects.mixins.cargo"),
    DoorClass = require("src.objects.mixins.door"),
    CrewClass = require("src.objects.mixins.crew"),
}
