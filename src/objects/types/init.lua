--[[
    Types module - Type class hierarchy for game objects

    Type classes hold STATIC data that is initialized once at game
    start and never changes during gameplay. Instance classes use
    their corresponding type class to get properties.

    Hierarchy:
    - AbstractTypeClass: Base with INI name and display name
    - ObjectTypeClass: Physical/visual properties, armor, health
    - TechnoTypeClass: Combat, production, ownership for fighting objects

    Concrete type classes (to be added):
    - BuildingTypeClass: Building-specific type data
    - UnitTypeClass: Vehicle-specific type data
    - InfantryTypeClass: Infantry-specific type data
    - AircraftTypeClass: Aircraft-specific type data
]]

return {
    AbstractTypeClass = require("src.objects.types.abstracttype"),
    ObjectTypeClass = require("src.objects.types.objecttype"),
    TechnoTypeClass = require("src.objects.types.technotype"),
}
