--[[
    Speech - EVA voice announcements and unit speech
    Handles queued speech playback for game events
    Reference: Original C&C EVA system (AUDIO.CPP, DEFINES.H)
]]

local Events = require("src.core.events")
local Paths = require("src.util.paths")

local Speech = {}
Speech.__index = Speech

-- EVA speech types (from DEFINES.H VOX enum)
Speech.VOX = {
    -- Mission/game state
    MISSION_WON = "accom1",
    MISSION_LOST = "fail1",
    MISSION_SAVED = "saved1",
    MISSION_LOADED = "loaded1",

    -- Construction
    CONSTRUCTION_COMPLETE = "constru1",
    UNIT_READY = "unitredy",
    NEW_OPTIONS = "newopt1",
    DEPLOY = "deploy1",
    STRUCTURE_SOLD = "sold1",
    BUILDING_CAPTURED = "captur1",

    -- Combat alerts
    UNIT_LOST = "unitlost",
    STRUCTURE_LOST = "structur1",
    BASE_UNDER_ATTACK = "baseatk1",
    UNABLE_TO_COMPLY = "unable1",
    BUILDING_IN_PROGRESS = "build1",
    LOW_POWER = "lopower1",
    INSUFFICIENT_FUNDS = "nopower1",
    INSUFFICIENT_CREDITS = "nocash1",
    SILOS_NEEDED = "silrone1",
    ON_HOLD = "onhold1",
    CANCELLED = "cancld1",
    PRIMARY_BUILDING = "pribldg1",

    -- Reinforcements
    REINFORCEMENTS_ARRIVED = "reinfor1",

    -- Special weapons
    AIRSTRIKE_READY = "airone1",
    ION_CANNON_READY = "ionone1",
    NUCLEAR_STRIKE_READY = "nukone1",
    SELECT_TARGET = "select1",

    -- Radar
    RADAR_ONLINE = "radaron1",
    RADAR_OFFLINE = "radarof1",

    -- Harvesting
    HARVESTER_LOST = "harves1",
    HARVESTER_UNDER_ATTACK = "harvat1",

    -- Miscellaneous
    ENEMY_APPROACHING = "enemy1",
    INCOMING_TRANSMISSION = "incmng1",
    ESTABLISHING_COMM = "establsh",

    -- Nod specific
    TEMPLE_OF_NOD_DESTROYED = "tnodest1",

    -- GDI specific
    ION_CANNON_ACTIVATED = "ionact1"
}

-- Priority levels for speech (higher = more important)
Speech.PRIORITY = {
    LOW = 1,
    NORMAL = 5,
    HIGH = 10,
    CRITICAL = 20
}

-- Speech priorities
Speech.VOX_PRIORITY = {
    MISSION_WON = Speech.PRIORITY.CRITICAL,
    MISSION_LOST = Speech.PRIORITY.CRITICAL,
    BASE_UNDER_ATTACK = Speech.PRIORITY.HIGH,
    NUCLEAR_STRIKE_READY = Speech.PRIORITY.HIGH,
    ION_CANNON_READY = Speech.PRIORITY.HIGH,
    HARVESTER_UNDER_ATTACK = Speech.PRIORITY.HIGH,
    UNIT_LOST = Speech.PRIORITY.NORMAL,
    STRUCTURE_LOST = Speech.PRIORITY.NORMAL,
    CONSTRUCTION_COMPLETE = Speech.PRIORITY.NORMAL,
    UNIT_READY = Speech.PRIORITY.NORMAL,
    LOW_POWER = Speech.PRIORITY.NORMAL,
    SILOS_NEEDED = Speech.PRIORITY.NORMAL,
    INSUFFICIENT_FUNDS = Speech.PRIORITY.NORMAL
}

function Speech.new()
    local self = setmetatable({}, Speech)

    -- Speech queue
    self.queue = {}
    self.max_queue = 5

    -- Current speech
    self.current = nil
    self.source = nil

    -- Volume
    self.volume = 1.0

    -- Audio mode
    self.mode = "remastered"  -- "classic" or "remastered"

    -- Sound cache
    self.cache = {}

    -- Cooldowns to prevent spam
    self.cooldowns = {}
    self.default_cooldown = 5.0  -- seconds

    -- Subtitle text for current speech
    self.subtitle_text = nil
    self.subtitle_timer = 0

    -- Enabled state
    self.enabled = true

    -- Register events
    self:register_events()

    return self
end

-- Register event listeners
function Speech:register_events()
    Events.on("PLAY_SPEECH", function(vox_id, priority)
        self:speak(vox_id, priority)
    end)

    Events.on("SET_SPEECH_VOLUME", function(vol)
        self:set_volume(vol)
    end)

    Events.on("SET_SPEECH_MODE", function(mode)
        self:set_mode(mode)
    end)

    -- Game events that trigger EVA speech
    Events.on(Events.EVENTS and Events.EVENTS.GAME_WIN or "GAME_WIN", function()
        self:speak("MISSION_WON", Speech.PRIORITY.CRITICAL)
    end)

    Events.on(Events.EVENTS and Events.EVENTS.GAME_LOSE or "GAME_LOSE", function()
        self:speak("MISSION_LOST", Speech.PRIORITY.CRITICAL)
    end)

    Events.on(Events.EVENTS and Events.EVENTS.BUILDING_BUILT or "BUILDING_BUILT", function()
        self:speak("CONSTRUCTION_COMPLETE")
    end)

    Events.on(Events.EVENTS and Events.EVENTS.UNIT_BUILT or "UNIT_BUILT", function()
        self:speak("UNIT_READY")
    end)

    Events.on("LOW_POWER", function()
        self:speak("LOW_POWER")
    end)

    Events.on("INSUFFICIENT_FUNDS", function()
        self:speak("INSUFFICIENT_FUNDS")
    end)

    Events.on("SILOS_NEEDED", function()
        self:speak("SILOS_NEEDED")
    end)

    Events.on("BASE_UNDER_ATTACK", function()
        self:speak("BASE_UNDER_ATTACK", Speech.PRIORITY.HIGH)
    end)

    Events.on("HARVESTER_UNDER_ATTACK", function()
        self:speak("HARVESTER_UNDER_ATTACK", Speech.PRIORITY.HIGH)
    end)

    Events.on("UNIT_LOST", function()
        self:speak("UNIT_LOST")
    end)

    Events.on("STRUCTURE_LOST", function()
        self:speak("STRUCTURE_LOST")
    end)

    Events.on("HARVESTER_LOST", function()
        self:speak("HARVESTER_LOST", Speech.PRIORITY.HIGH)
    end)

    Events.on("PRIMARY_BUILDING_DESTROYED", function()
        self:speak("STRUCTURE_LOST", Speech.PRIORITY.HIGH)
    end)

    Events.on("BUILDING_SOLD", function()
        self:speak("STRUCTURE_SOLD")
    end)

    Events.on("BUILDING_CAPTURED", function()
        self:speak("BUILDING_CAPTURED", Speech.PRIORITY.HIGH)
    end)

    Events.on("REINFORCEMENT", function()
        self:speak("REINFORCEMENTS_ARRIVED", Speech.PRIORITY.HIGH)
    end)

    Events.on("SPECIAL_WEAPON_READY", function(house, weapon_type)
        if weapon_type == "ION_CANNON" then
            self:speak("ION_CANNON_READY", Speech.PRIORITY.HIGH)
        elseif weapon_type == "NUKE" then
            self:speak("NUCLEAR_STRIKE_READY", Speech.PRIORITY.HIGH)
        elseif weapon_type == "AIRSTRIKE" then
            self:speak("AIRSTRIKE_READY", Speech.PRIORITY.HIGH)
        end
    end)

    Events.on("RADAR_ONLINE", function()
        self:speak("RADAR_ONLINE")
    end)

    Events.on("RADAR_OFFLINE", function()
        self:speak("RADAR_OFFLINE")
    end)
end

-- Get path for a speech file
function Speech:get_speech_path(speech_name)
    local base_path
    if self.mode == "classic" then
        base_path = Paths.audio("classic/speech/" .. speech_name)
    else
        base_path = Paths.audio("remastered/speech/" .. speech_name)
    end

    -- Try different extensions
    local extensions = {".ogg", ".wav", ".mp3"}
    for _, ext in ipairs(extensions) do
        local path = base_path .. ext
        if love.filesystem.getInfo(path) then
            return path
        end
    end

    -- Try generic path
    return Paths.audio("speech/" .. speech_name .. ".ogg")
end

-- Load a speech file
function Speech:load_speech(speech_name)
    if self.cache[speech_name] then
        return self.cache[speech_name]
    end

    local path = self:get_speech_path(speech_name)

    if love.filesystem.getInfo(path) then
        local success, source = pcall(function()
            return love.audio.newSource(path, "static")
        end)

        if success and source then
            self.cache[speech_name] = source
            return source
        end
    end

    return nil
end

-- Speak an EVA line
function Speech:speak(vox_id, priority)
    if not self.enabled then return false end

    -- Resolve VOX enum to filename
    local speech_file = Speech.VOX[vox_id]
    if not speech_file then
        speech_file = vox_id  -- Assume it's already a filename
    end

    -- Get priority
    priority = priority or Speech.VOX_PRIORITY[vox_id] or Speech.PRIORITY.NORMAL

    -- Check cooldown
    local cooldown_key = vox_id
    if self.cooldowns[cooldown_key] and self.cooldowns[cooldown_key] > 0 then
        -- Only allow critical priority to bypass cooldown
        if priority < Speech.PRIORITY.CRITICAL then
            return false
        end
    end

    -- Set cooldown
    self.cooldowns[cooldown_key] = self.default_cooldown

    -- If nothing playing, play immediately
    if not self.source or not self.source:isPlaying() then
        return self:play_speech(speech_file, vox_id)
    end

    -- Queue based on priority
    local queued = {
        file = speech_file,
        vox_id = vox_id,
        priority = priority
    }

    -- Find position based on priority
    local inserted = false
    for i, item in ipairs(self.queue) do
        if priority > item.priority then
            table.insert(self.queue, i, queued)
            inserted = true
            break
        end
    end

    if not inserted then
        table.insert(self.queue, queued)
    end

    -- Limit queue size
    while #self.queue > self.max_queue do
        table.remove(self.queue)
    end

    -- If very high priority, interrupt current
    if priority >= Speech.PRIORITY.CRITICAL then
        if self.source then
            self.source:stop()
        end
        self:play_next()
    end

    return true
end

-- Play a speech file directly
function Speech:play_speech(speech_file, vox_id)
    local source = self:load_speech(speech_file)

    if source then
        -- Clone for fresh playback
        self.source = source:clone()
        self.source:setVolume(self.volume)
        self.source:play()

        self.current = vox_id or speech_file

        -- Set subtitle
        self.subtitle_text = self:get_subtitle_text(vox_id or speech_file)
        self.subtitle_timer = source:getDuration() or 2.0

        -- Emit event for UI
        Events.emit("SPEECH_STARTED", self.current, self.subtitle_text)

        return true
    end

    return false
end

-- Play next queued speech
function Speech:play_next()
    if #self.queue > 0 then
        local next_speech = table.remove(self.queue, 1)
        self:play_speech(next_speech.file, next_speech.vox_id)
    else
        self.current = nil
        self.subtitle_text = nil
        Events.emit("SPEECH_ENDED")
    end
end

-- Get subtitle text for a VOX
function Speech:get_subtitle_text(vox_id)
    local subtitles = {
        MISSION_WON = "Mission accomplished.",
        MISSION_LOST = "Mission failed.",
        CONSTRUCTION_COMPLETE = "Construction complete.",
        UNIT_READY = "Unit ready.",
        LOW_POWER = "Low power.",
        INSUFFICIENT_FUNDS = "Insufficient funds.",
        INSUFFICIENT_CREDITS = "Insufficient credits.",
        SILOS_NEEDED = "Silos needed.",
        BASE_UNDER_ATTACK = "Our base is under attack.",
        UNIT_LOST = "Unit lost.",
        STRUCTURE_LOST = "Structure lost.",
        STRUCTURE_SOLD = "Structure sold.",
        BUILDING_CAPTURED = "Building captured.",
        REINFORCEMENTS_ARRIVED = "Reinforcements have arrived.",
        ION_CANNON_READY = "Ion cannon ready.",
        NUCLEAR_STRIKE_READY = "Nuclear strike ready.",
        AIRSTRIKE_READY = "Airstrike ready.",
        SELECT_TARGET = "Select target.",
        RADAR_ONLINE = "Radar online.",
        RADAR_OFFLINE = "Radar offline.",
        HARVESTER_UNDER_ATTACK = "Harvester under attack.",
        UNABLE_TO_COMPLY = "Unable to comply.",
        ON_HOLD = "On hold.",
        CANCELLED = "Cancelled.",
        NEW_OPTIONS = "New construction options."
    }

    return subtitles[vox_id] or vox_id
end

-- Set volume (0-1)
function Speech:set_volume(vol)
    self.volume = math.max(0, math.min(1, vol))
    if self.source then
        self.source:setVolume(self.volume)
    end
end

-- Get volume
function Speech:get_volume()
    return self.volume
end

-- Set audio mode
function Speech:set_mode(mode)
    if mode ~= self.mode then
        self.mode = mode
        -- Clear cache to reload speech files
        self.cache = {}
    end
end

-- Enable/disable speech
function Speech:set_enabled(enabled)
    self.enabled = enabled
    if not enabled then
        self:stop()
    end
end

-- Stop current speech
function Speech:stop()
    if self.source then
        self.source:stop()
    end
    self.current = nil
    self.subtitle_text = nil
    self.subtitle_timer = 0
    Events.emit("SPEECH_ENDED")
end

-- Clear queue
function Speech:clear_queue()
    self.queue = {}
end

-- Check if speaking
function Speech:is_speaking()
    return self.source and self.source:isPlaying()
end

-- Get current subtitle
function Speech:get_subtitle()
    if self.subtitle_timer > 0 then
        return self.subtitle_text
    end
    return nil
end

-- Get queue size
function Speech:get_queue_size()
    return #self.queue
end

-- Update (call every frame)
function Speech:update(dt)
    -- Update cooldowns
    for key, timer in pairs(self.cooldowns) do
        self.cooldowns[key] = timer - dt
        if self.cooldowns[key] <= 0 then
            self.cooldowns[key] = nil
        end
    end

    -- Update subtitle timer
    if self.subtitle_timer > 0 then
        self.subtitle_timer = self.subtitle_timer - dt
        if self.subtitle_timer <= 0 then
            self.subtitle_text = nil
        end
    end

    -- Check if current speech finished
    if self.source and not self.source:isPlaying() then
        self:play_next()
    end
end

-- Cleanup
function Speech:destroy()
    self:stop()
    self:clear_queue()
    self.cache = {}
end

return Speech
