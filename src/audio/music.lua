--[[
    Music - Background music management with classic/remastered toggle
    Handles C&C soundtrack playback with proper track selection
    Reference: Original C&C music system (AUDIO.CPP)
]]

local Events = require("src.core.events")
local Paths = require("src.util.paths")

local Music = {}
Music.__index = Music

-- Music tracks from original C&C (in order)
Music.TRACKS = {
    -- Main themes
    "act_on_instinct",
    "no_mercy",
    "industrial",
    "just_do_it_up",
    "fight_win_prevail",
    "in_the_line_of_fire",
    "march_to_doom",
    "mechanical_man",
    "airstrike",
    "target",
    "warfare",
    "c&c_thang",
    "take_em_out",
    "prepare_for_battle",
    "heroism",
    "on_the_prowl",
    "cc80s",
    "demolition"
}

-- Track aliases (original filenames)
Music.TRACK_ALIASES = {
    AOI = "act_on_instinct",
    NOMERCY = "no_mercy",
    IND = "industrial",
    JDI = "just_do_it_up",
    FWP = "fight_win_prevail",
    ITF = "in_the_line_of_fire",
    MTD = "march_to_doom",
    MM = "mechanical_man",
    AIR = "airstrike",
    TRG = "target",
    WAR = "warfare",
    CCT = "c&c_thang",
    TEO = "take_em_out",
    PFB = "prepare_for_battle",
    HER = "heroism",
    OTP = "on_the_prowl",
    CC80 = "cc80s",
    DEM = "demolition"
}

-- Faction-specific track preferences
Music.FACTION_TRACKS = {
    GDI = {"act_on_instinct", "fight_win_prevail", "heroism", "on_the_prowl"},
    NOD = {"no_mercy", "march_to_doom", "mechanical_man", "target"}
}

function Music.new()
    local self = setmetatable({}, Music)

    -- Current state
    self.current_track = nil
    self.source = nil
    self.volume = 0.7
    self.fade_volume = 1.0

    -- Playback mode
    self.mode = "remastered"  -- "classic" or "remastered"
    self.shuffle = false
    self.repeat_track = false

    -- Track history for shuffle mode
    self.play_history = {}
    self.shuffle_index = 0

    -- Fade state
    self.fading = false
    self.fade_target = 0
    self.fade_speed = 1.0
    self.fade_callback = nil

    -- Pause state
    self.paused = false

    -- Current faction for themed music
    self.faction = nil

    -- Track cache
    self.loaded_tracks = {}

    -- Register events
    self:register_events()

    return self
end

-- Register event listeners
function Music:register_events()
    Events.on("PLAY_MUSIC", function(track)
        self:play(track)
    end)

    Events.on("STOP_MUSIC", function()
        self:stop()
    end)

    Events.on("PAUSE_MUSIC", function()
        self:pause()
    end)

    Events.on("RESUME_MUSIC", function()
        self:resume()
    end)

    Events.on("SET_MUSIC_VOLUME", function(vol)
        self:set_volume(vol)
    end)

    Events.on("SET_MUSIC_MODE", function(mode)
        self:set_mode(mode)
    end)

    Events.on("FADE_MUSIC", function(target, duration, callback)
        self:fade_to(target, duration, callback)
    end)

    -- Campaign events
    Events.on(Events.EVENTS and Events.EVENTS.GAME_WIN or "GAME_WIN", function()
        self:play("heroism")
    end)

    Events.on(Events.EVENTS and Events.EVENTS.GAME_LOSE or "GAME_LOSE", function()
        self:play("march_to_doom")
    end)

    -- Menu music
    Events.on("ENTER_MAIN_MENU", function()
        self:play("act_on_instinct")
    end)
end

-- Get path for a track
function Music:get_track_path(track_name)
    -- Resolve aliases
    track_name = Music.TRACK_ALIASES[track_name] or track_name

    local base_path
    if self.mode == "classic" then
        base_path = Paths.audio("classic/music/" .. track_name)
    else
        base_path = Paths.audio("remastered/music/" .. track_name)
    end

    -- Try different extensions
    local extensions = {".ogg", ".mp3", ".wav"}
    for _, ext in ipairs(extensions) do
        local path = base_path .. ext
        if love.filesystem.getInfo(path) then
            return path
        end
    end

    -- Fall back to generic path
    return Paths.music(track_name .. ".ogg")
end

-- Load a track
function Music:load_track(track_name)
    if self.loaded_tracks[track_name] then
        return self.loaded_tracks[track_name]
    end

    local path = self:get_track_path(track_name)

    if love.filesystem.getInfo(path) then
        local success, source = pcall(function()
            return love.audio.newSource(path, "stream")
        end)

        if success and source then
            self.loaded_tracks[track_name] = source
            return source
        end
    end

    return nil
end

-- Play a track
function Music:play(track_name, fade_in)
    -- Resolve aliases
    track_name = Music.TRACK_ALIASES[track_name] or track_name

    -- Don't restart if already playing
    if self.current_track == track_name and self.source and self.source:isPlaying() then
        return
    end

    -- Stop current track
    if self.source then
        self.source:stop()
    end

    -- Load new track
    local source = self:load_track(track_name)
    if not source then
        -- Create placeholder if track not found
        self.current_track = track_name
        return
    end

    -- Clone source for fresh playback
    self.source = source:clone()
    self.current_track = track_name

    -- Configure
    self.source:setLooping(self.repeat_track)

    if fade_in then
        self.fade_volume = 0
        self.source:setVolume(0)
        self:fade_to(1.0, fade_in)
    else
        self.fade_volume = 1.0
        self.source:setVolume(self.volume)
    end

    self.source:play()
    self.paused = false

    -- Add to history
    table.insert(self.play_history, track_name)
    if #self.play_history > 20 then
        table.remove(self.play_history, 1)
    end

    Events.emit("MUSIC_STARTED", track_name)
end

-- Stop music
function Music:stop(fade_out)
    if fade_out then
        self:fade_to(0, fade_out, function()
            if self.source then
                self.source:stop()
            end
            self.current_track = nil
        end)
    else
        if self.source then
            self.source:stop()
        end
        self.current_track = nil
        Events.emit("MUSIC_STOPPED")
    end
end

-- Pause music
function Music:pause()
    if self.source and self.source:isPlaying() then
        self.source:pause()
        self.paused = true
        Events.emit("MUSIC_PAUSED")
    end
end

-- Resume music
function Music:resume()
    if self.source and self.paused then
        self.source:play()
        self.paused = false
        Events.emit("MUSIC_RESUMED")
    end
end

-- Set volume (0-1)
function Music:set_volume(vol)
    self.volume = math.max(0, math.min(1, vol))
    if self.source then
        self.source:setVolume(self.volume * self.fade_volume)
    end
end

-- Get current volume
function Music:get_volume()
    return self.volume
end

-- Set audio mode (classic/remastered)
function Music:set_mode(mode)
    if mode ~= self.mode then
        self.mode = mode
        -- Clear cache to reload tracks
        self.loaded_tracks = {}

        -- Restart current track if playing
        if self.current_track and self.source and self.source:isPlaying() then
            local track = self.current_track
            self:stop()
            self:play(track)
        end
    end
end

-- Fade to target volume
function Music:fade_to(target, duration, callback)
    self.fading = true
    self.fade_target = target
    self.fade_speed = 1.0 / (duration or 1.0)
    self.fade_callback = callback
end

-- Play next track (for shuffle/sequential)
function Music:play_next()
    local tracks = self.faction and Music.FACTION_TRACKS[self.faction] or Music.TRACKS

    if self.shuffle then
        -- Random track not in recent history
        local available = {}
        for _, track in ipairs(tracks) do
            local in_history = false
            for i = math.max(1, #self.play_history - 3), #self.play_history do
                if self.play_history[i] == track then
                    in_history = true
                    break
                end
            end
            if not in_history then
                table.insert(available, track)
            end
        end

        if #available > 0 then
            local idx = math.random(1, #available)
            self:play(available[idx], 1.0)
        else
            -- All tracks in history, play random
            local idx = math.random(1, #tracks)
            self:play(tracks[idx], 1.0)
        end
    else
        -- Sequential
        local current_idx = 1
        for i, track in ipairs(tracks) do
            if track == self.current_track then
                current_idx = i
                break
            end
        end

        local next_idx = (current_idx % #tracks) + 1
        self:play(tracks[next_idx], 1.0)
    end
end

-- Play previous track
function Music:play_previous()
    if #self.play_history >= 2 then
        local prev = self.play_history[#self.play_history - 1]
        table.remove(self.play_history)  -- Remove current
        table.remove(self.play_history)  -- Remove previous (will be re-added)
        self:play(prev)
    end
end

-- Set faction for themed music
function Music:set_faction(faction)
    self.faction = faction
end

-- Set shuffle mode
function Music:set_shuffle(enabled)
    self.shuffle = enabled
end

-- Set repeat mode
function Music:set_repeat(enabled)
    self.repeat_track = enabled
    if self.source then
        self.source:setLooping(enabled)
    end
end

-- Check if playing
function Music:is_playing()
    return self.source and self.source:isPlaying()
end

-- Check if paused
function Music:is_paused()
    return self.paused
end

-- Get current track name
function Music:get_current_track()
    return self.current_track
end

-- Get track duration
function Music:get_duration()
    if self.source then
        return self.source:getDuration()
    end
    return 0
end

-- Get playback position
function Music:get_position()
    if self.source then
        return self.source:tell()
    end
    return 0
end

-- Set playback position
function Music:seek(position)
    if self.source then
        self.source:seek(position)
    end
end

-- Update (call every frame for fades and auto-advance)
function Music:update(dt)
    -- Handle fading
    if self.fading then
        local diff = self.fade_target - self.fade_volume
        local step = self.fade_speed * dt

        if math.abs(diff) < step then
            self.fade_volume = self.fade_target
            self.fading = false

            if self.fade_callback then
                self.fade_callback()
                self.fade_callback = nil
            end
        else
            self.fade_volume = self.fade_volume + (diff > 0 and step or -step)
        end

        if self.source then
            self.source:setVolume(self.volume * self.fade_volume)
        end
    end

    -- Check for track end (auto-advance)
    if self.source and not self.paused and not self.source:isPlaying() and not self.repeat_track then
        self:play_next()
    end
end

-- Get list of available tracks
function Music:get_available_tracks()
    local available = {}

    for _, track in ipairs(Music.TRACKS) do
        local path = self:get_track_path(track)
        if love.filesystem.getInfo(path) then
            table.insert(available, track)
        end
    end

    return available
end

-- Cleanup
function Music:destroy()
    if self.source then
        self.source:stop()
        self.source = nil
    end
    self.loaded_tracks = {}
end

return Music
