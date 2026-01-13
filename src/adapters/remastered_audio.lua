--[[
    Remastered Audio Adapter - High-quality audio support

    This adapter provides support for the remastered audio tracks
    from the C&C Remastered Collection.

    Features:
    - High-fidelity music tracks
    - Remastered sound effects
    - Dynamic audio mixing
    - Toggle between classic and remastered

    Original: Low-quality PCM audio, FM synth music
    This Port: Toggle between classic and remastered audio

    Reference: PLAN.md "Intentional Deviations"
]]

local RemasteredAudio = {}

--============================================================================
-- Configuration
--============================================================================

RemasteredAudio.enabled = false
RemasteredAudio.music_volume = 0.7
RemasteredAudio.sfx_volume = 0.8
RemasteredAudio.voice_volume = 1.0

-- Audio source caches
RemasteredAudio.music_cache = {}
RemasteredAudio.sfx_cache = {}
RemasteredAudio.voice_cache = {}

-- Current playback
RemasteredAudio.current_music = nil
RemasteredAudio.music_source = nil

--============================================================================
-- Initialization
--============================================================================

--[[
    Initialize the remastered audio adapter.
]]
function RemasteredAudio.init()
    RemasteredAudio.enabled = true

    -- Check for remastered audio files
    local remastered_path = "assets/audio/remastered"
    if love and love.filesystem.getInfo(remastered_path) then
        print("RemasteredAudio: Found remastered audio directory")
    else
        print("RemasteredAudio: Remastered audio not found, using classic")
        RemasteredAudio.enabled = false
    end
end

--============================================================================
-- Music Playback
--============================================================================

--[[
    Play a music track.
    @param name - Track name (e.g., "act_on_instinct", "no_mercy")
    @param loop - Whether to loop (default true)
]]
function RemasteredAudio.play_music(name, loop)
    if loop == nil then loop = true end

    -- Stop current music
    RemasteredAudio.stop_music()

    if not love or not love.audio then
        return
    end

    -- Try remastered first, then classic
    local path = nil
    if RemasteredAudio.enabled then
        path = string.format("assets/audio/remastered/music/%s.ogg", name)
        if not love.filesystem.getInfo(path) then
            path = nil
        end
    end

    if not path then
        path = string.format("assets/audio/classic/music/%s.ogg", name)
        if not love.filesystem.getInfo(path) then
            print("RemasteredAudio: Music not found - " .. name)
            return
        end
    end

    -- Load and play
    local source = love.audio.newSource(path, "stream")
    source:setLooping(loop)
    source:setVolume(RemasteredAudio.music_volume)
    source:play()

    RemasteredAudio.current_music = name
    RemasteredAudio.music_source = source
end

--[[
    Stop the current music.
]]
function RemasteredAudio.stop_music()
    if RemasteredAudio.music_source then
        RemasteredAudio.music_source:stop()
        RemasteredAudio.music_source = nil
    end
    RemasteredAudio.current_music = nil
end

--[[
    Pause the current music.
]]
function RemasteredAudio.pause_music()
    if RemasteredAudio.music_source then
        RemasteredAudio.music_source:pause()
    end
end

--[[
    Resume paused music.
]]
function RemasteredAudio.resume_music()
    if RemasteredAudio.music_source then
        RemasteredAudio.music_source:play()
    end
end

--============================================================================
-- Sound Effects
--============================================================================

--[[
    Play a sound effect.
    @param name - Sound effect name
    @param volume - Volume multiplier (0-1, default 1)
    @param pitch - Pitch multiplier (default 1)
    @return Sound source or nil
]]
function RemasteredAudio.play_sfx(name, volume, pitch)
    volume = volume or 1.0
    pitch = pitch or 1.0

    if not love or not love.audio then
        return nil
    end

    -- Check cache
    local source = RemasteredAudio.sfx_cache[name]

    if not source then
        -- Try remastered first, then classic
        local path = nil
        if RemasteredAudio.enabled then
            path = string.format("assets/audio/remastered/sfx/%s.ogg", name)
            if not love.filesystem.getInfo(path) then
                path = nil
            end
        end

        if not path then
            path = string.format("assets/audio/classic/sfx/%s.ogg", name)
            if not love.filesystem.getInfo(path) then
                return nil
            end
        end

        source = love.audio.newSource(path, "static")
        RemasteredAudio.sfx_cache[name] = source
    end

    -- Clone for simultaneous playback
    local clone = source:clone()
    clone:setVolume(RemasteredAudio.sfx_volume * volume)
    clone:setPitch(pitch)
    clone:play()

    return clone
end

--============================================================================
-- Voice/Speech
--============================================================================

--[[
    Play a voice line (EVA announcements, etc.)
    @param name - Voice line name
    @return Sound source or nil
]]
function RemasteredAudio.play_voice(name)
    if not love or not love.audio then
        return nil
    end

    -- Check cache
    local source = RemasteredAudio.voice_cache[name]

    if not source then
        local path = nil
        if RemasteredAudio.enabled then
            path = string.format("assets/audio/remastered/voice/%s.ogg", name)
            if not love.filesystem.getInfo(path) then
                path = nil
            end
        end

        if not path then
            path = string.format("assets/audio/classic/voice/%s.ogg", name)
            if not love.filesystem.getInfo(path) then
                return nil
            end
        end

        source = love.audio.newSource(path, "static")
        RemasteredAudio.voice_cache[name] = source
    end

    local clone = source:clone()
    clone:setVolume(RemasteredAudio.voice_volume)
    clone:play()

    return clone
end

--============================================================================
-- Volume Control
--============================================================================

--[[
    Set music volume.
    @param volume - Volume level (0-1)
]]
function RemasteredAudio.set_music_volume(volume)
    RemasteredAudio.music_volume = math.max(0, math.min(1, volume))

    if RemasteredAudio.music_source then
        RemasteredAudio.music_source:setVolume(RemasteredAudio.music_volume)
    end
end

--[[
    Set sound effects volume.
    @param volume - Volume level (0-1)
]]
function RemasteredAudio.set_sfx_volume(volume)
    RemasteredAudio.sfx_volume = math.max(0, math.min(1, volume))
end

--[[
    Set voice volume.
    @param volume - Volume level (0-1)
]]
function RemasteredAudio.set_voice_volume(volume)
    RemasteredAudio.voice_volume = math.max(0, math.min(1, volume))
end

--============================================================================
-- Settings
--============================================================================

--[[
    Toggle between classic and remastered audio.
    @return New state
]]
function RemasteredAudio.toggle()
    RemasteredAudio.enabled = not RemasteredAudio.enabled

    -- Restart current music with new audio set
    if RemasteredAudio.current_music then
        local track = RemasteredAudio.current_music
        RemasteredAudio.stop_music()
        RemasteredAudio.play_music(track)
    end

    -- Clear caches to force reload
    RemasteredAudio.sfx_cache = {}
    RemasteredAudio.voice_cache = {}

    return RemasteredAudio.enabled
end

--============================================================================
-- Debug
--============================================================================

function RemasteredAudio.Debug_Dump()
    print("RemasteredAudio Adapter:")
    print(string.format("  Enabled: %s", tostring(RemasteredAudio.enabled)))
    print(string.format("  Music Volume: %.0f%%", RemasteredAudio.music_volume * 100))
    print(string.format("  SFX Volume: %.0f%%", RemasteredAudio.sfx_volume * 100))
    print(string.format("  Voice Volume: %.0f%%", RemasteredAudio.voice_volume * 100))
    print(string.format("  Current Music: %s", RemasteredAudio.current_music or "none"))

    local sfx_cached = 0
    for _ in pairs(RemasteredAudio.sfx_cache) do sfx_cached = sfx_cached + 1 end
    print(string.format("  Cached SFX: %d", sfx_cached))

    local voice_cached = 0
    for _ in pairs(RemasteredAudio.voice_cache) do voice_cached = voice_cached + 1 end
    print(string.format("  Cached Voice: %d", voice_cached))
end

return RemasteredAudio
