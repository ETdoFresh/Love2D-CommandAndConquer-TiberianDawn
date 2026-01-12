--[[
    SFX - Sound effects playback with classic/remastered toggle
    Handles unit sounds, explosions, weapons, and ambient effects
    Reference: Original C&C audio system (AUDIO.CPP)
]]

local Events = require("src.core.events")
local Paths = require("src.util.paths")

local SFX = {}
SFX.__index = SFX

-- Sound effect categories
SFX.CATEGORY = {
    WEAPON = "weapon",
    EXPLOSION = "explosion",
    UNIT = "unit",
    BUILDING = "building",
    UI = "ui",
    AMBIENT = "ambient"
}

-- Priority levels (higher = more important, won't be cut off)
SFX.PRIORITY = {
    LOW = 1,
    NORMAL = 5,
    HIGH = 10,
    CRITICAL = 20
}

-- Common sound effects
SFX.SOUNDS = {
    -- Weapons
    GUN_FIRE = {name = "gun5", category = "weapon", priority = 5},
    MACHINEGUN = {name = "gun11", category = "weapon", priority = 5},
    CANNON = {name = "tnkfire3", category = "weapon", priority = 8},
    ROCKET = {name = "rocket1", category = "weapon", priority = 8},
    GRENADE = {name = "grenade1", category = "weapon", priority = 7},
    FLAME = {name = "flamer1", category = "weapon", priority = 6},
    LASER = {name = "obelisk1", category = "weapon", priority = 10},
    ION_CANNON = {name = "ion1", category = "weapon", priority = 20},

    -- Explosions
    EXPLODE_SMALL = {name = "explode1", category = "explosion", priority = 8},
    EXPLODE_MEDIUM = {name = "explode3", category = "explosion", priority = 10},
    EXPLODE_LARGE = {name = "explode5", category = "explosion", priority = 12},
    BUILDING_EXPLODE = {name = "crumble", category = "explosion", priority = 15},
    NUKE = {name = "nukexplo", category = "explosion", priority = 20},

    -- Unit responses
    UNIT_READY = {name = "unitredy", category = "unit", priority = 10},
    UNIT_LOST = {name = "unitlost", category = "unit", priority = 10},
    UNIT_SELECT = {name = "await1", category = "unit", priority = 3},
    UNIT_MOVE = {name = "roger", category = "unit", priority = 3},
    UNIT_ATTACK = {name = "yessir1", category = "unit", priority = 3},

    -- Building sounds
    BUILDING_PLACE = {name = "constru2", category = "building", priority = 8},
    BUILDING_COMPLETE = {name = "constru1", category = "building", priority = 10},
    BUILDING_SELL = {name = "cashturn", category = "building", priority = 8},
    BUILDING_POWER_UP = {name = "powerup1", category = "building", priority = 5},
    BUILDING_POWER_DOWN = {name = "powrdn1", category = "building", priority = 8},

    -- UI sounds
    BUTTON_CLICK = {name = "button", category = "ui", priority = 5},
    CREDITS_TICK = {name = "cashup1", category = "ui", priority = 2},
    RADAR_ON = {name = "radar1", category = "ui", priority = 8},
    RADAR_OFF = {name = "radaron2", category = "ui", priority = 8},
    MESSAGE = {name = "message1", category = "ui", priority = 10},
    BEEP = {name = "beepy3", category = "ui", priority = 3},

    -- Ambient
    TIBERIUM_GROW = {name = "tibgrow1", category = "ambient", priority = 1},
    HARVESTING = {name = "minelay1", category = "ambient", priority = 2}
}

function SFX.new()
    local self = setmetatable({}, SFX)

    -- Volume levels by category (0-1)
    self.volumes = {
        master = 1.0,
        weapon = 1.0,
        explosion = 1.0,
        unit = 0.8,
        building = 0.9,
        ui = 1.0,
        ambient = 0.5
    }

    -- Audio mode
    self.mode = "remastered"  -- "classic" or "remastered"

    -- Sound cache
    self.sound_cache = {}

    -- Sound pools for frequently played sounds
    self.pools = {}
    self.pool_size = 8

    -- Currently playing sounds
    self.playing = {}
    self.max_concurrent = 32

    -- 3D audio
    self.listener_x = 0
    self.listener_y = 0
    self.audio_range = 1000  -- Distance at which sounds are inaudible
    self.enabled = true

    -- Register events
    self:register_events()

    return self
end

-- Register event listeners
function SFX:register_events()
    Events.on("PLAY_SOUND", function(sound_id, x, y, volume_mult)
        self:play(sound_id, x, y, volume_mult)
    end)

    Events.on("SET_SFX_VOLUME", function(vol, category)
        self:set_volume(vol, category)
    end)

    Events.on("SET_SFX_MODE", function(mode)
        self:set_mode(mode)
    end)

    Events.on("SET_LISTENER_POSITION", function(x, y)
        self:set_listener(x, y)
    end)

    -- Combat events
    Events.on(Events.EVENTS and Events.EVENTS.WEAPON_FIRED or "WEAPON_FIRED", function(entity, weapon)
        local sound = weapon.fire_sound or "gun5"
        local transform = entity:has("transform") and entity:get("transform")
        if transform then
            self:play(sound, transform.x, transform.y)
        end
    end)

    Events.on(Events.EVENTS and Events.EVENTS.ENTITY_DESTROYED or "ENTITY_DESTROYED", function(entity)
        local transform = entity:has("transform") and entity:get("transform")
        if transform then
            if entity:has("building") then
                self:play("BUILDING_EXPLODE", transform.x, transform.y)
            else
                self:play("EXPLODE_MEDIUM", transform.x, transform.y)
            end
        end
    end)

    -- Unit events
    Events.on(Events.EVENTS and Events.EVENTS.UNIT_BUILT or "UNIT_BUILT", function()
        self:play("UNIT_READY")
    end)

    Events.on(Events.EVENTS and Events.EVENTS.BUILDING_BUILT or "BUILDING_BUILT", function()
        self:play("BUILDING_COMPLETE")
    end)

    -- Selection events
    Events.on("UNIT_SELECTED", function(entity)
        self:play("UNIT_SELECT")
    end)

    Events.on("UNIT_ORDERED_MOVE", function(entity)
        self:play("UNIT_MOVE")
    end)

    Events.on("UNIT_ORDERED_ATTACK", function(entity)
        self:play("UNIT_ATTACK")
    end)

    -- UI events
    Events.on("UI_BUTTON_CLICK", function()
        self:play("BUTTON_CLICK")
    end)

    Events.on("CREDITS_CHANGED", function()
        self:play("CREDITS_TICK")
    end)
end

-- Get path for a sound
function SFX:get_sound_path(sound_name)
    local base_path
    if self.mode == "classic" then
        base_path = Paths.audio("classic/sfx/" .. sound_name)
    else
        base_path = Paths.audio("remastered/sfx/" .. sound_name)
    end

    -- Try different extensions
    local extensions = {".ogg", ".wav", ".mp3"}
    for _, ext in ipairs(extensions) do
        local path = base_path .. ext
        if love.filesystem.getInfo(path) then
            return path
        end
    end

    -- Try legacy sounds folder
    return Paths.sound(sound_name .. ".ogg")
end

-- Load a sound
function SFX:load_sound(sound_name)
    if self.sound_cache[sound_name] then
        return self.sound_cache[sound_name]
    end

    local path = self:get_sound_path(sound_name)

    if love.filesystem.getInfo(path) then
        local success, data = pcall(function()
            return love.sound.newSoundData(path)
        end)

        if success and data then
            self.sound_cache[sound_name] = data
            return data
        end
    end

    return nil
end

-- Create or get from sound pool
function SFX:get_from_pool(sound_name)
    if not self.pools[sound_name] then
        self.pools[sound_name] = {
            sources = {},
            index = 1
        }

        local data = self:load_sound(sound_name)
        if data then
            for i = 1, self.pool_size do
                local success, source = pcall(function()
                    return love.audio.newSource(data)
                end)
                if success and source then
                    table.insert(self.pools[sound_name].sources, source)
                end
            end
        end
    end

    local pool = self.pools[sound_name]
    if #pool.sources == 0 then
        return nil
    end

    local source = pool.sources[pool.index]
    pool.index = (pool.index % #pool.sources) + 1

    return source
end

-- Play a sound
function SFX:play(sound_id, x, y, volume_mult)
    if not self.enabled then return nil end

    volume_mult = volume_mult or 1.0

    -- Resolve sound definition
    local sound_def = SFX.SOUNDS[sound_id]
    local sound_name, category, priority

    if sound_def then
        sound_name = sound_def.name
        category = sound_def.category
        priority = sound_def.priority
    else
        sound_name = sound_id
        category = "sfx"
        priority = SFX.PRIORITY.NORMAL
    end

    -- Calculate volume based on distance
    local distance_factor = 1.0
    if x and y then
        local dx = x - self.listener_x
        local dy = y - self.listener_y
        local distance = math.sqrt(dx * dx + dy * dy)

        if distance > self.audio_range then
            return nil  -- Too far to hear
        end

        distance_factor = 1 - (distance / self.audio_range)
        distance_factor = distance_factor * distance_factor  -- Quadratic falloff
    end

    -- Calculate final volume
    local cat_volume = self.volumes[category] or 1.0
    local final_volume = self.volumes.master * cat_volume * distance_factor * volume_mult

    if final_volume < 0.01 then
        return nil  -- Too quiet
    end

    -- Clean up finished sounds
    self:cleanup_finished()

    -- Check concurrent limit
    if #self.playing >= self.max_concurrent then
        -- Remove lowest priority sound
        table.sort(self.playing, function(a, b)
            return (a.priority or 0) < (b.priority or 0)
        end)

        local removed = table.remove(self.playing, 1)
        if removed and removed.source then
            removed.source:stop()
        end
    end

    -- Get source from pool
    local source = self:get_from_pool(sound_name)
    if not source then
        -- Try loading directly
        local data = self:load_sound(sound_name)
        if data then
            local success
            success, source = pcall(function()
                return love.audio.newSource(data)
            end)
            if not success then
                return nil
            end
        else
            return nil
        end
    end

    -- Configure and play
    source:stop()  -- Reset if reused
    source:setVolume(final_volume)

    -- Pan based on position
    if x and y then
        local pan = (x - self.listener_x) / self.audio_range
        pan = math.max(-1, math.min(1, pan))
        -- Note: Love2D doesn't have stereo panning for non-positional sources
        -- Would need to use PositionalSource for true 3D audio
    end

    source:play()

    -- Track playing sound
    table.insert(self.playing, {
        source = source,
        sound_name = sound_name,
        priority = priority,
        x = x,
        y = y
    })

    return source
end

-- Play a sound at specific pitch
function SFX:play_pitched(sound_id, pitch, x, y, volume_mult)
    local source = self:play(sound_id, x, y, volume_mult)
    if source then
        source:setPitch(pitch)
    end
    return source
end

-- Play a looping sound
function SFX:play_loop(sound_id, x, y, volume_mult)
    local source = self:play(sound_id, x, y, volume_mult)
    if source then
        source:setLooping(true)
    end
    return source
end

-- Stop a specific sound
function SFX:stop(source)
    if source then
        source:stop()

        for i, playing in ipairs(self.playing) do
            if playing.source == source then
                table.remove(self.playing, i)
                break
            end
        end
    end
end

-- Stop all sounds
function SFX:stop_all()
    for _, playing in ipairs(self.playing) do
        if playing.source then
            playing.source:stop()
        end
    end
    self.playing = {}
end

-- Stop sounds by category
function SFX:stop_category(category)
    local i = 1
    while i <= #self.playing do
        local playing = self.playing[i]
        local def = SFX.SOUNDS[playing.sound_name]

        if def and def.category == category then
            if playing.source then
                playing.source:stop()
            end
            table.remove(self.playing, i)
        else
            i = i + 1
        end
    end
end

-- Cleanup finished sounds
function SFX:cleanup_finished()
    local i = 1
    while i <= #self.playing do
        local playing = self.playing[i]
        if not playing.source or not playing.source:isPlaying() then
            table.remove(self.playing, i)
        else
            i = i + 1
        end
    end
end

-- Set master volume (0-1)
function SFX:set_volume(vol, category)
    if category then
        self.volumes[category] = math.max(0, math.min(1, vol))
    else
        self.volumes.master = math.max(0, math.min(1, vol))
    end
end

-- Get volume
function SFX:get_volume(category)
    if category then
        return self.volumes[category] or 1.0
    end
    return self.volumes.master
end

-- Set audio mode
function SFX:set_mode(mode)
    if mode ~= self.mode then
        self.mode = mode
        -- Clear caches to reload sounds
        self.sound_cache = {}
        self.pools = {}
    end
end

-- Set listener position for 3D audio
function SFX:set_listener(x, y)
    self.listener_x = x
    self.listener_y = y
end

-- Enable/disable sound effects
function SFX:set_enabled(enabled)
    self.enabled = enabled
    if not enabled then
        self:stop_all()
    end
end

-- Check if a sound is currently playing
function SFX:is_playing(sound_id)
    for _, playing in ipairs(self.playing) do
        if playing.sound_name == sound_id and playing.source and playing.source:isPlaying() then
            return true
        end
    end
    return false
end

-- Get number of currently playing sounds
function SFX:get_playing_count()
    self:cleanup_finished()
    return #self.playing
end

-- Update (call every frame)
function SFX:update(dt)
    -- Update 3D audio positions for moving sounds
    for _, playing in ipairs(self.playing) do
        if playing.source and playing.source:isPlaying() then
            -- Could update volume based on new listener position
            if playing.x and playing.y then
                local dx = playing.x - self.listener_x
                local dy = playing.y - self.listener_y
                local distance = math.sqrt(dx * dx + dy * dy)

                if distance > self.audio_range then
                    playing.source:stop()
                else
                    local factor = 1 - (distance / self.audio_range)
                    factor = factor * factor
                    local cat = SFX.SOUNDS[playing.sound_name]
                    local cat_vol = self.volumes[(cat and cat.category) or "sfx"] or 1.0
                    playing.source:setVolume(self.volumes.master * cat_vol * factor)
                end
            end
        end
    end

    -- Periodic cleanup
    self:cleanup_finished()
end

-- Cleanup
function SFX:destroy()
    self:stop_all()
    self.sound_cache = {}
    self.pools = {}
end

return SFX
