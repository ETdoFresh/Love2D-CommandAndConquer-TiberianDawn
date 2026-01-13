--[[
    Drive module - Movement specialization classes

    This module provides movement-related classes for mobile units:
    - DriveClass: Ground vehicle movement (track-based turning, harvesting)
    - TurretClass: Turret control for turret-equipped vehicles
    - TarComClass: Targeting computer for combat vehicles
    - FlyClass: Aircraft flight physics (mixin)

    Inheritance chain for ground vehicles:
    FootClass → DriveClass → TurretClass → TarComClass → UnitClass

    Aircraft use FlyClass as a mixin component instead.
]]

return {
    DriveClass = require("src.objects.drive.drive"),
    TurretClass = require("src.objects.drive.turret"),
    TarComClass = require("src.objects.drive.tarcom"),
    FlyClass = require("src.objects.drive.fly"),
}
