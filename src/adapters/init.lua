--[[
    Adapters Module - Optional deviation adapters

    These adapters provide modern enhancements that deviate from the
    original C&C behavior. They are kept separate from core game logic
    to maintain fidelity to the original implementation.

    All adapters are optional and can be enabled/disabled in settings.

    Reference: PLAN.md "Intentional Deviations from Original" section
]]

local Adapters = {}

-- Load individual adapters
Adapters.HDGraphics = require("src.adapters.hd_graphics")
Adapters.Controller = require("src.adapters.controller")
Adapters.Hotkeys = require("src.adapters.hotkeys")
Adapters.RemasteredAudio = require("src.adapters.remastered_audio")

-- Configuration flags
Adapters.config = {
    use_hd_graphics = false,      -- Use remastered HD sprites
    use_controller = false,       -- Enable controller support
    use_custom_hotkeys = false,   -- Use rebindable hotkeys
    use_remastered_audio = false, -- Use remastered audio
}

--[[
    Initialize all adapters.
    @param settings - Settings table with adapter configuration
]]
function Adapters.init(settings)
    settings = settings or {}

    -- Apply configuration
    Adapters.config.use_hd_graphics = settings.hd_graphics or false
    Adapters.config.use_controller = settings.controller or false
    Adapters.config.use_custom_hotkeys = settings.custom_hotkeys or false
    Adapters.config.use_remastered_audio = settings.remastered_audio or false

    -- Initialize enabled adapters
    if Adapters.config.use_hd_graphics then
        Adapters.HDGraphics.init()
    end

    if Adapters.config.use_controller then
        Adapters.Controller.init()
    end

    if Adapters.config.use_custom_hotkeys then
        Adapters.Hotkeys.init()
    end

    if Adapters.config.use_remastered_audio then
        Adapters.RemasteredAudio.init()
    end
end

--[[
    Update all enabled adapters.
    @param dt - Delta time
]]
function Adapters.update(dt)
    if Adapters.config.use_controller then
        Adapters.Controller.update(dt)
    end
end

--[[
    Debug dump of adapter states.
]]
function Adapters.Debug_Dump()
    print("Adapters:")
    print(string.format("  HD Graphics: %s", tostring(Adapters.config.use_hd_graphics)))
    print(string.format("  Controller: %s", tostring(Adapters.config.use_controller)))
    print(string.format("  Custom Hotkeys: %s", tostring(Adapters.config.use_custom_hotkeys)))
    print(string.format("  Remastered Audio: %s", tostring(Adapters.config.use_remastered_audio)))
end

return Adapters
