--[[
    Audio System - Sound effects and music playback
    Handles C&C audio including EVA speech
]]

local Events = require("src.core.events")
local System = require("src.ecs.system")
local Paths = require("src.util.paths")

local AudioSystem = setmetatable({}, {__index = System})
AudioSystem.__index = AudioSystem

-- Audio categories
AudioSystem.CATEGORY = {
    MUSIC = "music",
    SFX = "sfx",
    SPEECH = "speech",
    UI = "ui"
}

function AudioSystem.new()
    local self = setmetatable(System.new(), AudioSystem)

    self.name = "AudioSystem"

    -- Volume levels (0-1)
    self.volumes = {
        master = 1.0,
        music = 0.7,
        sfx = 1.0,
        speech = 1.0,
        ui = 1.0
    }

    -- Currently playing music
    self.current_music = nil
    self.music_source = nil

    -- Sound cache
    self.sounds = {}

    -- Speech queue (EVA voices played sequentially)
    self.speech_queue = {}
    self.current_speech = nil

    -- Sound pools for frequently used sounds
    self.sound_pools = {}
    self.pool_size = 8

    -- 3D audio listener position
    self.listener_x = 0
    self.listener_y = 0

    -- Registered sounds
    self.sound_data = {}

    -- Initialize Love2D audio
    self:init_audio()

    -- Register events
    self:register_events()

    return self
end

-- Initialize audio system
function AudioSystem:init_audio()
    -- Set up default audio settings
    love.audio.setVolume(self.volumes.master)

    -- Try to load sound definitions from data files
    self:load_sound_definitions()
end

-- Load sound definitions from JSON data files
function AudioSystem:load_sound_definitions()
    -- Load sounds.json
    local sounds_path = "data/audio/sounds.json"
    if love.filesystem.getInfo(sounds_path) then
        local content = love.filesystem.read(sounds_path)
        if content then
            local success, data = pcall(function()
                return require("lib.json").decode(content)
            end)
            if success and data then
                for name, info in pairs(data) do
                    local path = info.path or Paths.audio("sfx/" .. name .. ".ogg")
                    local category = info.category or AudioSystem.CATEGORY.SFX
                    self:register_sound(name, path, category)
                end
            end
        end
    end

    -- Load themes.json for music
    local themes_path = "data/audio/themes.json"
    if love.filesystem.getInfo(themes_path) then
        local content = love.filesystem.read(themes_path)
        if content then
            local success, data = pcall(function()
                return require("lib.json").decode(content)
            end)
            if success and data then
                self.music_tracks = data
            end
        end
    end
end

-- Register event listeners
function AudioSystem:register_events()
    Events.on("PLAY_SOUND", function(sound_name, x, y)
        self:play_sound(sound_name, x, y)
    end)

    Events.on("PLAY_MUSIC", function(music_name)
        self:play_music(music_name)
    end)

    Events.on("PLAY_SPEECH", function(speech_text)
        self:queue_speech(speech_text)
    end)

    Events.on("STOP_MUSIC", function()
        self:stop_music()
    end)

    -- Game events that trigger sounds with unit response variety
    Events.on(Events.EVENTS.COMMAND_MOVE, function(units, dest_x, dest_y)
        self:play_unit_response("move", units)
    end)

    Events.on(Events.EVENTS.COMMAND_ATTACK, function(units, target)
        self:play_unit_response("attack", units)
    end)

    Events.on(Events.EVENTS.COMMAND_ATTACK_MOVE, function(units, dest_x, dest_y)
        self:play_unit_response("attack", units)
    end)

    Events.on(Events.EVENTS.COMMAND_ATTACK_GROUND, function(units, dest_x, dest_y)
        self:play_unit_response("attack", units)
    end)

    Events.on(Events.EVENTS.ENTITY_DESTROYED, function(entity)
        if entity:has_tag("building") then
            self:play_sound("crumble")
        elseif entity:has_tag("vehicle") then
            self:play_sound("xplobig4")
        elseif entity:has_tag("infantry") then
            self:play_sound("xplosml2")
        end
    end)

    Events.on(Events.EVENTS.UNIT_BUILT, function()
        self:queue_speech("Unit ready")
    end)

    Events.on(Events.EVENTS.BUILDING_BUILT, function()
        self:queue_speech("Construction complete")
    end)

    Events.on("LOW_POWER", function()
        self:queue_speech("Low power")
    end)

    Events.on("UNIT_UNDER_ATTACK", function()
        self:queue_speech("Unit under attack")
    end)

    Events.on("BASE_UNDER_ATTACK", function()
        self:queue_speech("Our base is under attack")
    end)

    Events.on("INSUFFICIENT_FUNDS", function()
        self:queue_speech("Insufficient funds")
    end)

    Events.on("BUILDING_CAPTURED", function()
        self:queue_speech("Building captured")
    end)

    -- Special weapons EVA announcements
    Events.on("SPECIAL_WEAPON_READY", function(house, weapon_type)
        if weapon_type == "ion_cannon" then
            self:queue_speech("Ion cannon ready")
        elseif weapon_type == "nuclear" or weapon_type == "nuke" then
            self:queue_speech("Nuclear missile ready")
        elseif weapon_type == "airstrike" or weapon_type == "a10" then
            self:queue_speech("A-10 ready")
        end
    end)

    Events.on("SPECIAL_WEAPON_TARGETING", function(house, weapon_type)
        self:queue_speech("Select target")
    end)

    Events.on("SPECIAL_WEAPON_FIRED", function(house, weapon_type)
        if weapon_type == "ion_cannon" then
            self:play_sound("ion1")
        elseif weapon_type == "nuclear" or weapon_type == "nuke" then
            self:play_sound("nukexplo")
        elseif weapon_type == "airstrike" or weapon_type == "a10" then
            self:play_sound("airborne")
        end
    end)

    -- Harvester events
    Events.on("HARVESTER_DOCKING", function(entity, refinery)
        -- Could play docking sound
    end)

    Events.on("HARVESTER_UNDER_ATTACK", function(entity)
        self:queue_speech("Harvester under attack")
    end)

    Events.on("SILOS_NEEDED", function()
        self:queue_speech("Silos needed")
    end)

    -- Mission/game events
    Events.on(Events.EVENTS.GAME_WIN, function()
        self:queue_speech("Mission accomplished")
    end)

    Events.on(Events.EVENTS.GAME_LOSE, function()
        self:queue_speech("Mission failed")
    end)

    Events.on("REINFORCEMENTS_ARRIVED", function()
        self:queue_speech("Reinforcements have arrived")
    end)

    Events.on("BUILDING_PLACEMENT_CANCELLED", function()
        self:queue_speech("Cancelled")
    end)

    Events.on("CANNOT_DEPLOY", function()
        self:queue_speech("Cannot deploy here")
    end)

    -- EVA speech from triggers and game events
    -- Reference: Original C&C trigger system uses EVA_SPEECH for mission announcements
    Events.on("EVA_SPEECH", function(speech_text, house)
        -- Only play for player house or if house is -1 (all houses)
        if house == -1 or house == nil or house == self.player_house then
            self:queue_speech(speech_text)
        end
    end)

    -- Structure/unit loss announcements
    -- Reference: Original C&C announces when structures or units are lost
    Events.on("STRUCTURE_LOST", function(house, building_type)
        if house == self.player_house then
            self:queue_speech("Structure lost")
        end
    end)

    Events.on("UNIT_LOST", function(house, unit_type)
        if house == self.player_house then
            self:queue_speech("Unit lost")
        end
    end)

    -- Fire Sale announcement
    Events.on("FIRE_SALE", function(house)
        if house == self.player_house then
            self:queue_speech("Selling all structures")
        end
    end)

    -- Airstrike/bombing run announcements
    Events.on("AIRSTRIKE_INCOMING", function(house)
        if house ~= self.player_house then
            self:queue_speech("Enemy aircraft approaching")
        end
    end)

    -- Ion cannon warning (affects all players)
    Events.on("ION_CANNON_FIRED", function(house, target_x, target_y)
        self:queue_speech("Ion cannon activated")
    end)

    -- Nuclear warning (affects all players)
    Events.on("NUCLEAR_LAUNCHED", function(house, target_x, target_y)
        self:queue_speech("Nuclear warhead approaching")
        self:play_sound("nuke_warn")
    end)

    -- Selection response - play unit acknowledgment when units are selected
    Events.on(Events.EVENTS.SELECTION_CHANGED, function(units)
        if units and #units > 0 then
            self:play_unit_response("select", units)
        end
    end)
end

-- Set the player house for speech filtering
function AudioSystem:set_player_house(house)
    self.player_house = house
end

-- Unit response sound mappings by unit type
-- Based on original C&C unit voice responses
AudioSystem.UNIT_RESPONSES = {
    -- Infantry responses
    infantry = {
        select = {"yessir1", "ready", "awaiting"},
        move = {"ackno", "affirm1", "roger"},
        attack = {"affirm1", "yessir1", "ugotit"}
    },
    -- Vehicle responses
    vehicle = {
        select = {"vehic1", "report1", "await1"},
        move = {"ackno", "moveout", "onmove"},
        attack = {"affirm1", "ugotit", "yessir1"}
    },
    -- Aircraft responses
    aircraft = {
        select = {"await1", "ready", "report1"},
        move = {"ackno", "affirm1", "roger"},
        attack = {"affirm1", "ugotit", "yessir1"}
    },
    -- Commando responses (unique)
    commando = {
        select = {"iamgod", "keepem", "laugh1"},
        move = {"noprblm", "yessir1", "roger"},
        attack = {"gotit", "noprblm", "yessir1"}
    },
    -- Engineer responses
    engineer = {
        select = {"ready", "yessir1", "await1"},
        move = {"ackno", "affirm1", "roger"},
        attack = {"affirm1", "ugotit", "yessir1"}
    },
    -- Default fallback
    default = {
        select = {"yessir1", "ready", "report1"},
        move = {"ackno", "affirm1", "roger"},
        attack = {"affirm1", "ugotit", "yessir1"}
    }
}

-- Response rotation index to cycle through variety
AudioSystem.response_index = 1

-- Play unit response audio with variety
function AudioSystem:play_unit_response(response_type, units)
    if not units or #units == 0 then
        -- Fallback to default sounds
        if response_type == "move" then
            self:play_sound("ackno")
        elseif response_type == "attack" then
            self:play_sound("affirm1")
        end
        return
    end

    -- Get the first selected unit to determine response type
    local unit = units[1]
    if type(units) ~= "table" then
        unit = units  -- Single unit passed
    end

    -- Determine unit category for responses
    local category = "default"
    if unit and type(unit.has) == "function" then
        if unit:has("infantry") then
            local infantry = unit:get("infantry")
            local infantry_type = infantry and infantry.infantry_type or "E1"
            -- Check for special unit types
            if infantry_type == "RMBO" then
                category = "commando"
            elseif infantry_type == "E6" then
                category = "engineer"
            else
                category = "infantry"
            end
        elseif unit:has("aircraft") then
            category = "aircraft"
        elseif unit:has("vehicle") then
            category = "vehicle"
        end
    end

    -- Get response sounds for this category and type
    local responses = self.UNIT_RESPONSES[category]
    if not responses then
        responses = self.UNIT_RESPONSES.default
    end

    local sounds = responses[response_type]
    if not sounds then
        sounds = responses.select or {"yessir1"}
    end

    -- Rotate through sound variety
    local sound_name = sounds[((self.response_index - 1) % #sounds) + 1]
    self.response_index = self.response_index + 1
    if self.response_index > 100 then
        self.response_index = 1  -- Prevent overflow
    end

    -- Play the response
    self:play_sound(sound_name)
end

-- Register a sound file
function AudioSystem:register_sound(name, filepath, category)
    self.sound_data[name] = {
        path = filepath,
        category = category or AudioSystem.CATEGORY.SFX
    }
end

-- Load a sound (lazy loading)
function AudioSystem:load_sound(name)
    if self.sounds[name] then
        return self.sounds[name]
    end

    local data = self.sound_data[name]
    if not data then
        -- Try default path
        local path = Paths.sound(name .. ".wav")
        if love.filesystem.getInfo(path) then
            data = {path = path, category = AudioSystem.CATEGORY.SFX}
        else
            return nil
        end
    end

    local success, source = pcall(function()
        return love.audio.newSource(data.path, "static")
    end)

    if success then
        self.sounds[name] = {
            source = source,
            category = data.category
        }
        return self.sounds[name]
    end

    return nil
end

-- Play a sound effect
function AudioSystem:play_sound(name, x, y)
    local sound = self:load_sound(name)
    if not sound then return nil end

    -- Clone source for simultaneous playback
    local source = sound.source:clone()

    -- Set volume based on category
    local volume = self.volumes.master * self.volumes[sound.category]
    source:setVolume(volume)

    -- Apply positional audio if coordinates provided
    if x and y then
        local dist = self:calculate_distance(x, y)
        local falloff = math.max(0, 1 - dist / 1000)  -- Falloff over 1000 pixels
        source:setVolume(volume * falloff)
    end

    source:play()
    return source
end

-- Play from a sound pool (for frequent sounds)
function AudioSystem:play_pooled(name, x, y)
    if not self.sound_pools[name] then
        self:create_pool(name)
    end

    local pool = self.sound_pools[name]
    if not pool then return nil end

    -- Find available source in pool
    for _, source in ipairs(pool) do
        if not source:isPlaying() then
            local volume = self.volumes.master * self.volumes.sfx
            if x and y then
                local dist = self:calculate_distance(x, y)
                local falloff = math.max(0, 1 - dist / 1000)
                volume = volume * falloff
            end
            source:setVolume(volume)
            source:play()
            return source
        end
    end

    -- All sources busy, skip
    return nil
end

-- Create a sound pool
function AudioSystem:create_pool(name)
    local sound = self:load_sound(name)
    if not sound then return end

    self.sound_pools[name] = {}
    for _ = 1, self.pool_size do
        table.insert(self.sound_pools[name], sound.source:clone())
    end
end

-- Play music track
function AudioSystem:play_music(name)
    -- Stop current music
    self:stop_music()

    -- Try to load music file
    local path = Paths.music(name .. ".ogg")
    if not love.filesystem.getInfo(path) then
        path = Paths.music(name .. ".mp3")
    end
    if not love.filesystem.getInfo(path) then
        return false
    end

    local success, source = pcall(function()
        return love.audio.newSource(path, "stream")
    end)

    if success then
        self.music_source = source
        self.current_music = name

        source:setVolume(self.volumes.master * self.volumes.music)
        source:setLooping(true)
        source:play()
        return true
    end

    return false
end

-- Stop music
function AudioSystem:stop_music()
    if self.music_source then
        self.music_source:stop()
        self.music_source = nil
        self.current_music = nil
    end
end

-- Pause/resume music
function AudioSystem:pause_music()
    if self.music_source then
        self.music_source:pause()
    end
end

function AudioSystem:resume_music()
    if self.music_source then
        self.music_source:play()
    end
end

-- Queue EVA speech
function AudioSystem:queue_speech(text)
    table.insert(self.speech_queue, text)
end

-- Play next speech in queue
function AudioSystem:play_next_speech()
    if #self.speech_queue == 0 then return end

    local text = table.remove(self.speech_queue, 1)

    -- Try to find audio file for this text
    local sound_name = text:lower():gsub(" ", "_"):gsub("[^%w_]", "")
    local sound = self:load_sound(sound_name)

    if sound then
        self.current_speech = sound.source:clone()
        self.current_speech:setVolume(self.volumes.master * self.volumes.speech)
        self.current_speech:play()
    else
        -- No audio file, just emit event for subtitle display
        Events.emit("SPEECH_TEXT", text)
        self.current_speech = nil
    end
end

-- Update audio system
function AudioSystem:update(dt)
    -- Process speech queue
    if self.current_speech then
        if not self.current_speech:isPlaying() then
            self.current_speech = nil
            -- Small delay between speeches
            -- (Could add timer here)
            self:play_next_speech()
        end
    elseif #self.speech_queue > 0 then
        self:play_next_speech()
    end
end

-- Set listener position (for 3D audio)
function AudioSystem:set_listener_position(x, y)
    self.listener_x = x
    self.listener_y = y
end

-- Calculate distance from listener
function AudioSystem:calculate_distance(x, y)
    local dx = x - self.listener_x
    local dy = y - self.listener_y
    return math.sqrt(dx * dx + dy * dy)
end

-- Set volume
function AudioSystem:set_volume(category, volume)
    volume = math.max(0, math.min(1, volume))

    if category == "master" then
        self.volumes.master = volume
        love.audio.setVolume(volume)

        -- Update music volume
        if self.music_source then
            self.music_source:setVolume(volume * self.volumes.music)
        end
    elseif self.volumes[category] then
        self.volumes[category] = volume

        if category == "music" and self.music_source then
            self.music_source:setVolume(self.volumes.master * volume)
        end
    end
end

-- Get volume
function AudioSystem:get_volume(category)
    return self.volumes[category] or 0
end

-- Mute/unmute
function AudioSystem:set_muted(muted)
    if muted then
        love.audio.setVolume(0)
    else
        love.audio.setVolume(self.volumes.master)
    end
end

-- Stop all sounds
function AudioSystem:stop_all()
    love.audio.stop()
    self.current_speech = nil
    self.speech_queue = {}
end

-- C&C specific EVA phrases
AudioSystem.EVA_PHRASES = {
    -- Construction
    "Construction complete",
    "Building",
    "On hold",
    "Cancelled",
    "Cannot deploy here",
    "Building in progress",
    "Unit ready",

    -- Combat
    "Unit under attack",
    "Our base is under attack",
    "Unit lost",
    "Structure destroyed",

    -- Economy
    "Insufficient funds",
    "Silos needed",
    "Low power",

    -- Special
    "Ion cannon ready",
    "Nuclear missile ready",
    "A-10 ready",
    "Select target",
    "Reinforcements have arrived",
    "Mission accomplished",
    "Mission failed"
}

return AudioSystem
