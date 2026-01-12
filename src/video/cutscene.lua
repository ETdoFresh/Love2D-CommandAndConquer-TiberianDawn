--[[
    Cutscene System - Video playback for mission briefings and endings
    Handles both remastered HD videos and fallback text-based briefings
    Reference: Original C&C FMV sequences played at mission start/end
]]

local Events = require("src.core.events")

local Cutscene = {}
Cutscene.__index = Cutscene

-- Video file mapping (original C&C FMV names to remastered files)
Cutscene.VIDEOS = {
    -- GDI Campaign
    gdi1 = {path = "assets/video/cutscenes/gdi/gdi1.ogv", title = "GDI Mission 1 Briefing"},
    gdi1win = {path = "assets/video/cutscenes/gdi/gdi1win.ogv", title = "GDI Mission 1 Victory"},
    gdi1lose = {path = "assets/video/cutscenes/gdi/gdi1lose.ogv", title = "GDI Mission 1 Defeat"},
    gdi2 = {path = "assets/video/cutscenes/gdi/gdi2.ogv", title = "GDI Mission 2 Briefing"},
    gdi2win = {path = "assets/video/cutscenes/gdi/gdi2win.ogv", title = "GDI Mission 2 Victory"},
    gdi3 = {path = "assets/video/cutscenes/gdi/gdi3.ogv", title = "GDI Mission 3 Briefing"},
    gdifinal = {path = "assets/video/cutscenes/gdi/gdifinal.ogv", title = "GDI Campaign Victory"},

    -- Nod Campaign
    nod1 = {path = "assets/video/cutscenes/nod/nod1.ogv", title = "Nod Mission 1 Briefing"},
    nod1win = {path = "assets/video/cutscenes/nod/nod1win.ogv", title = "Nod Mission 1 Victory"},
    nod1lose = {path = "assets/video/cutscenes/nod/nod1lose.ogv", title = "Nod Mission 1 Defeat"},
    nod2 = {path = "assets/video/cutscenes/nod/nod2.ogv", title = "Nod Mission 2 Briefing"},
    nod2win = {path = "assets/video/cutscenes/nod/nod2win.ogv", title = "Nod Mission 2 Victory"},
    nod3 = {path = "assets/video/cutscenes/nod/nod3.ogv", title = "Nod Mission 3 Briefing"},
    nodfinal = {path = "assets/video/cutscenes/nod/nodfinal.ogv", title = "Nod Campaign Victory"},

    -- Shared/Intro videos
    intro = {path = "assets/video/cutscenes/intro.ogv", title = "Command & Conquer Intro"},
    logo = {path = "assets/video/cutscenes/logo.ogv", title = "Westwood Studios Logo"},
    credits = {path = "assets/video/cutscenes/credits.ogv", title = "Credits"}
}

-- Cutscene states
Cutscene.STATE = {
    LOADING = "loading",
    PLAYING = "playing",
    PAUSED = "paused",
    FINISHED = "finished",
    ERROR = "error"
}

function Cutscene.new()
    local self = setmetatable({}, Cutscene)

    self.state = Cutscene.STATE.FINISHED
    self.video = nil
    self.video_source = nil
    self.current_video_id = nil

    -- Playback state
    self.elapsed = 0
    self.duration = 0
    self.volume = 1.0

    -- Fade effects
    self.fade_alpha = 1  -- Start faded in
    self.fade_target = 0
    self.fade_speed = 2

    -- Fallback text display (when video not available)
    self.fallback_mode = false
    self.fallback_text = ""
    self.fallback_title = ""
    self.text_progress = 0

    -- Subtitles (optional)
    self.subtitles = {}
    self.current_subtitle = ""

    -- Callbacks
    self.on_complete = nil
    self.on_skip = nil

    -- Skip confirmation
    self.skip_hold_time = 0
    self.skip_threshold = 0.5  -- Hold for 0.5s to skip

    return self
end

-- Load and play a video
function Cutscene:play(video_id, on_complete)
    self.on_complete = on_complete
    self.current_video_id = video_id
    self.elapsed = 0
    self.skip_hold_time = 0

    -- Start with fade from black
    self.fade_alpha = 1
    self.fade_target = 0

    local video_data = Cutscene.VIDEOS[video_id]

    if not video_data then
        -- Unknown video, use fallback
        self:start_fallback("Video not found: " .. tostring(video_id), "Missing Video")
        return
    end

    -- Check if video file exists
    local video_path = video_data.path
    if love.filesystem.getInfo(video_path) then
        -- Load the video
        self.state = Cutscene.STATE.LOADING

        local success, result = pcall(function()
            return love.graphics.newVideo(video_path)
        end)

        if success and result then
            self.video = result
            self.video_source = self.video:getSource()

            if self.video_source then
                self.video_source:setVolume(self.volume)
            end

            self.video:play()
            self.state = Cutscene.STATE.PLAYING
            self.fallback_mode = false

            -- Try to get duration (may not be available for all formats)
            self.duration = 60  -- Default 60 seconds if unknown

            Events.emit("CUTSCENE_STARTED", video_id)
        else
            -- Video load failed, use fallback
            self:start_fallback(video_data.title or video_id, "Video Unavailable")
        end
    else
        -- Video file doesn't exist, use text fallback
        self:start_fallback(video_data.title or video_id, "Video Not Installed")
    end
end

-- Start fallback text display
function Cutscene:start_fallback(text, title)
    self.fallback_mode = true
    self.fallback_text = text
    self.fallback_title = title or "BRIEFING"
    self.text_progress = 0
    self.duration = 5  -- 5 second display
    self.state = Cutscene.STATE.PLAYING

    Events.emit("CUTSCENE_STARTED", self.current_video_id)
end

-- Stop/cleanup current video
function Cutscene:stop()
    if self.video then
        self.video:pause()
        self.video = nil
    end

    if self.video_source then
        self.video_source:stop()
        self.video_source = nil
    end

    self.state = Cutscene.STATE.FINISHED
    self.fallback_mode = false

    Events.emit("CUTSCENE_ENDED", self.current_video_id)
end

-- Pause/resume
function Cutscene:pause()
    if self.state == Cutscene.STATE.PLAYING then
        if self.video then
            self.video:pause()
        end
        self.state = Cutscene.STATE.PAUSED
    end
end

function Cutscene:resume()
    if self.state == Cutscene.STATE.PAUSED then
        if self.video then
            self.video:play()
        end
        self.state = Cutscene.STATE.PLAYING
    end
end

-- Skip current cutscene
function Cutscene:skip()
    -- Fade to black then complete
    self.fade_target = 1
    self.fade_speed = 4  -- Fast fade

    if self.on_skip then
        self.on_skip(self.current_video_id)
    end
end

-- Complete cutscene (called after fade out)
function Cutscene:complete()
    self:stop()

    if self.on_complete then
        self.on_complete(self.current_video_id)
    end
end

-- Set volume
function Cutscene:set_volume(volume)
    self.volume = math.max(0, math.min(1, volume))

    if self.video_source then
        self.video_source:setVolume(self.volume)
    end
end

-- Update
function Cutscene:update(dt)
    if self.state ~= Cutscene.STATE.PLAYING and self.state ~= Cutscene.STATE.PAUSED then
        return
    end

    -- Update fade
    if self.fade_alpha ~= self.fade_target then
        local dir = self.fade_target > self.fade_alpha and 1 or -1
        self.fade_alpha = self.fade_alpha + dir * self.fade_speed * dt
        self.fade_alpha = math.max(0, math.min(1, self.fade_alpha))

        -- Check if fade out complete
        if self.fade_alpha >= 1 and self.fade_target >= 1 then
            self:complete()
            return
        end
    end

    if self.state ~= Cutscene.STATE.PLAYING then
        return
    end

    self.elapsed = self.elapsed + dt

    -- Update video or fallback
    if self.fallback_mode then
        -- Animate text reveal
        self.text_progress = math.min(1, self.text_progress + dt * 0.5)

        -- Auto-complete after duration
        if self.elapsed >= self.duration then
            self.fade_target = 1
        end
    else
        -- Check if video finished
        if self.video and not self.video:isPlaying() then
            -- Video ended naturally
            self.fade_target = 1
        end
    end

    -- Update subtitles (if any)
    self:update_subtitles()
end

-- Update subtitle display
function Cutscene:update_subtitles()
    self.current_subtitle = ""

    for _, sub in ipairs(self.subtitles) do
        if self.elapsed >= sub.start_time and self.elapsed <= sub.end_time then
            self.current_subtitle = sub.text
            break
        end
    end
end

-- Load subtitles from file
function Cutscene:load_subtitles(video_id)
    self.subtitles = {}

    local sub_path = "assets/video/subtitles/" .. video_id .. ".srt"
    if not love.filesystem.getInfo(sub_path) then
        return
    end

    local content = love.filesystem.read(sub_path)
    if not content then return end

    -- Simple SRT parser
    local current_sub = nil

    for line in content:gmatch("[^\r\n]+") do
        if line:match("^%d+$") then
            -- Subtitle index
            if current_sub then
                table.insert(self.subtitles, current_sub)
            end
            current_sub = {text = ""}

        elseif line:match("-->") then
            -- Timestamp line
            if current_sub then
                local start_h, start_m, start_s, start_ms, end_h, end_m, end_s, end_ms =
                    line:match("(%d+):(%d+):(%d+),(%d+) --> (%d+):(%d+):(%d+),(%d+)")

                if start_h then
                    current_sub.start_time = tonumber(start_h) * 3600 + tonumber(start_m) * 60 +
                                            tonumber(start_s) + tonumber(start_ms) / 1000
                    current_sub.end_time = tonumber(end_h) * 3600 + tonumber(end_m) * 60 +
                                          tonumber(end_s) + tonumber(end_ms) / 1000
                end
            end

        elseif line ~= "" and current_sub then
            -- Subtitle text
            if current_sub.text ~= "" then
                current_sub.text = current_sub.text .. "\n"
            end
            current_sub.text = current_sub.text .. line
        end
    end

    if current_sub and current_sub.text ~= "" then
        table.insert(self.subtitles, current_sub)
    end
end

-- Handle input
function Cutscene:keypressed(key)
    if self.state ~= Cutscene.STATE.PLAYING and self.state ~= Cutscene.STATE.PAUSED then
        return
    end

    if key == "escape" or key == "space" or key == "return" then
        self:skip()
    elseif key == "p" then
        if self.state == Cutscene.STATE.PLAYING then
            self:pause()
        else
            self:resume()
        end
    end
end

-- Hold-to-skip support
function Cutscene:update_skip_input(dt, skip_held)
    if skip_held then
        self.skip_hold_time = self.skip_hold_time + dt
        if self.skip_hold_time >= self.skip_threshold then
            self:skip()
        end
    else
        self.skip_hold_time = 0
    end
end

-- Draw
function Cutscene:draw()
    if self.state == Cutscene.STATE.FINISHED then
        return
    end

    local w, h = love.graphics.getDimensions()

    -- Black background
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)

    if self.fallback_mode then
        self:draw_fallback(w, h)
    else
        self:draw_video(w, h)
    end

    -- Draw subtitles
    if self.current_subtitle ~= "" then
        self:draw_subtitles(w, h)
    end

    -- Draw skip indicator
    if self.skip_hold_time > 0 then
        self:draw_skip_indicator(w, h)
    end

    -- Draw fade overlay
    if self.fade_alpha > 0 then
        love.graphics.setColor(0, 0, 0, self.fade_alpha)
        love.graphics.rectangle("fill", 0, 0, w, h)
    end

    -- Skip hint
    love.graphics.setColor(0.5, 0.5, 0.5, 0.5 * (1 - self.fade_alpha))
    love.graphics.printf("Press SPACE or ESC to skip", 0, h - 30, w, "center")

    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw video
function Cutscene:draw_video(w, h)
    if not self.video then return end

    -- Calculate scaling to fit screen (letterbox)
    local vw, vh = self.video:getDimensions()
    local scale = math.min(w / vw, h / vh)
    local draw_w = vw * scale
    local draw_h = vh * scale
    local draw_x = (w - draw_w) / 2
    local draw_y = (h - draw_h) / 2

    love.graphics.setColor(1, 1, 1, 1 - self.fade_alpha)
    love.graphics.draw(self.video, draw_x, draw_y, 0, scale, scale)
end

-- Draw fallback text display
function Cutscene:draw_fallback(w, h)
    local alpha = 1 - self.fade_alpha

    -- Decorative frame
    love.graphics.setColor(0.2, 0.3, 0.2, alpha * 0.5)
    love.graphics.rectangle("fill", w * 0.1, h * 0.2, w * 0.8, h * 0.6)

    love.graphics.setColor(0.4, 0.6, 0.4, alpha)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", w * 0.1, h * 0.2, w * 0.8, h * 0.6)
    love.graphics.setLineWidth(1)

    -- Title
    love.graphics.setColor(0.8, 0.8, 0.2, alpha)
    love.graphics.printf(self.fallback_title, 0, h * 0.25, w, "center")

    -- Divider line with animation
    local line_width = w * 0.6 * self.text_progress
    love.graphics.setColor(0.6, 0.6, 0.2, alpha)
    love.graphics.rectangle("fill", (w - line_width) / 2, h * 0.32, line_width, 2)

    -- Main text with typewriter effect
    local visible_chars = math.floor(#self.fallback_text * self.text_progress)
    local display_text = self.fallback_text:sub(1, visible_chars)

    love.graphics.setColor(0.9, 0.9, 0.9, alpha)
    love.graphics.printf(display_text, w * 0.15, h * 0.4, w * 0.7, "center")

    -- Loading dots animation
    local dots = string.rep(".", math.floor(self.elapsed * 2) % 4)
    love.graphics.setColor(0.5, 0.5, 0.5, alpha)
    love.graphics.printf("Loading video" .. dots, 0, h * 0.7, w, "center")
end

-- Draw subtitles
function Cutscene:draw_subtitles(w, h)
    local alpha = 1 - self.fade_alpha

    -- Subtitle background
    local font = love.graphics.getFont()
    local text_h = font:getHeight() * 2  -- Assume 2 lines max
    local sub_y = h - 80 - text_h

    love.graphics.setColor(0, 0, 0, 0.7 * alpha)
    love.graphics.rectangle("fill", w * 0.1, sub_y - 10, w * 0.8, text_h + 20)

    -- Subtitle text
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.printf(self.current_subtitle, w * 0.12, sub_y, w * 0.76, "center")
end

-- Draw skip indicator
function Cutscene:draw_skip_indicator(w, h)
    local progress = self.skip_hold_time / self.skip_threshold
    local bar_w = 100
    local bar_h = 5
    local bar_x = (w - bar_w) / 2
    local bar_y = h - 50

    love.graphics.setColor(0.3, 0.3, 0.3, 0.8)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_w, bar_h)

    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.rectangle("fill", bar_x, bar_y, bar_w * progress, bar_h)
end

-- Check if currently playing
function Cutscene:is_playing()
    return self.state == Cutscene.STATE.PLAYING or self.state == Cutscene.STATE.PAUSED
end

-- Get playback progress (0-1)
function Cutscene:get_progress()
    if self.duration <= 0 then return 0 end
    return math.min(1, self.elapsed / self.duration)
end

return Cutscene
