--[[
    Paths - Centralized asset and reference path resolution

    Handles path resolution for both normal operation and git worktree scenarios.
    When running from .worktrees/{branch}/, shared directories are at ../../
    When running from the main repo, they are at ./

    Shared directories (not duplicated in worktrees):
    - assets/  - Game assets (sprites, audio, video)
    - temp/    - Original C++ source reference (CnC_Remastered_Collection)
]]

local Paths = {}

-- Cached base path for assets (computed once on first use)
local asset_base_path = nil

-- Cached main repo path for worktree scenarios
local main_repo_path = nil

-- Detect if we're in a worktree and get the main repo path
local function detect_main_repo_path()
    local source_path = love.filesystem.getSource()
    if source_path and source_path:match("[/\\]%.worktrees[/\\]") then
        -- We're in a worktree, calculate path to main repo
        -- Pattern: /path/to/repo/.worktrees/branchname/ -> /path/to/repo/
        return source_path:gsub("[/\\]%.worktrees[/\\][^/\\]+[/\\]?$", "")
    end
    return nil
end

-- Detect the correct asset base path
local function detect_asset_path()
    -- First, check if assets/ exists in current directory
    if love.filesystem.getInfo("assets") then
        return "assets/"
    end

    -- Check if we're in a worktree
    local source_path = love.filesystem.getSource()
    if source_path and source_path:match("[/\\]%.worktrees[/\\]") then
        -- We're in a worktree, assets should be at the main repo
        local repo_path = detect_main_repo_path()
        if repo_path then
            local worktree_assets = repo_path .. "/assets"

            -- Try to mount the parent assets directory
            local success = pcall(function()
                love.filesystem.mount(worktree_assets, "assets")
            end)

            if success and love.filesystem.getInfo("assets") then
                return "assets/"
            end
        end
    end

    -- Fallback: assume assets/ even if not found (will fail gracefully later)
    return "assets/"
end

-- Mount the temp directory for worktree scenarios
local function mount_temp_directory()
    -- Skip if temp/ already exists
    if love.filesystem.getInfo("temp") then
        return true
    end

    -- Check if we're in a worktree
    local repo_path = detect_main_repo_path()
    if repo_path then
        local worktree_temp = repo_path .. "/temp"

        -- Try to mount the parent temp directory
        local success = pcall(function()
            love.filesystem.mount(worktree_temp, "temp")
        end)

        return success and love.filesystem.getInfo("temp") ~= nil
    end

    return false
end

-- Initialize and get the asset base path
function Paths.get_asset_base()
    if not asset_base_path then
        asset_base_path = detect_asset_path()
    end
    return asset_base_path
end

-- Resolve a path relative to the assets directory
-- Example: Paths.asset("sprites/infantry/e1.png") -> "assets/sprites/infantry/e1.png"
function Paths.asset(relative_path)
    return Paths.get_asset_base() .. relative_path
end

-- Resolve sprite path
-- Example: Paths.sprite("infantry/e1.png") -> "assets/sprites/infantry/e1.png"
function Paths.sprite(relative_path)
    return Paths.asset("sprites/" .. relative_path)
end

-- Resolve audio path
-- Example: Paths.audio("sfx/gunfire.ogg") -> "assets/audio/sfx/gunfire.ogg"
function Paths.audio(relative_path)
    return Paths.asset("audio/" .. relative_path)
end

-- Resolve sound path (legacy folder name)
-- Example: Paths.sound("explosion.wav") -> "assets/sounds/explosion.wav"
function Paths.sound(relative_path)
    return Paths.asset("sounds/" .. relative_path)
end

-- Resolve music path
-- Example: Paths.music("act_on_instinct.ogg") -> "assets/music/act_on_instinct.ogg"
function Paths.music(relative_path)
    return Paths.asset("music/" .. relative_path)
end

-- Resolve video path
-- Example: Paths.video("cutscenes/gdi/gdi1.ogv") -> "assets/video/cutscenes/gdi/gdi1.ogv"
function Paths.video(relative_path)
    return Paths.asset("video/" .. relative_path)
end

-- Check if running from a worktree
function Paths.is_worktree()
    local source_path = love.filesystem.getSource()
    return source_path and source_path:match("[/\\]%.worktrees[/\\]") ~= nil
end

-- Resolve temp directory path (original C++ source reference)
-- Example: Paths.temp("CnC_Remastered_Collection/TIBERIANDAWN/DEFINES.H")
function Paths.temp(relative_path)
    return "temp/" .. relative_path
end

-- Resolve path to original C&C source
-- Example: Paths.cnc_source("DEFINES.H") -> "temp/CnC_Remastered_Collection/TIBERIANDAWN/DEFINES.H"
function Paths.cnc_source(relative_path)
    return Paths.temp("CnC_Remastered_Collection/TIBERIANDAWN/" .. relative_path)
end

-- Get the main repo path (nil if not in worktree)
function Paths.get_main_repo_path()
    if not main_repo_path then
        main_repo_path = detect_main_repo_path()
    end
    return main_repo_path
end

-- Get information about current path configuration (for debugging)
function Paths.get_info()
    return {
        source = love.filesystem.getSource(),
        save_directory = love.filesystem.getSaveDirectory(),
        asset_base = Paths.get_asset_base(),
        is_worktree = Paths.is_worktree(),
        main_repo_path = Paths.get_main_repo_path(),
        assets_found = love.filesystem.getInfo("assets") ~= nil,
        temp_found = love.filesystem.getInfo("temp") ~= nil
    }
end

-- Initialize paths on module load (early detection)
-- This ensures asset and temp mounting happens before any files are loaded
Paths.get_asset_base()
mount_temp_directory()

return Paths
