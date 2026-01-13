--[[
    Spectator Mode Adapter - Observer mode with perspective switching

    Reference: PLAN.md "Intentional Deviations from Original" section
    Original C&C had no spectator mode. This adapter provides:
    - Full observer mode for watching games
    - Perspective switching between players
    - Free camera movement
    - Full map visibility (optional)
    - Unit/building highlighting for tracked player

    This is an optional deviation adapter - not part of original gameplay.
]]

local Spectator = {}
Spectator.__index = Spectator

-- Spectator view modes
Spectator.VIEW_MODE = {
    FREE = 1,        -- Free camera, sees all
    PLAYER = 2,      -- Follows specific player's view
    UNIT = 3         -- Follows specific unit
}

-- Configuration
Spectator.config = {
    enabled = false,
    show_all_units = true,     -- Show all units regardless of fog
    show_production = true,    -- Show production queues
    show_credits = true,       -- Show player credits
    highlight_selected = true, -- Highlight currently tracked player's units
    camera_speed = 500,        -- Free camera movement speed
    zoom_min = 0.5,
    zoom_max = 2.0
}

-- State
Spectator.active = false
Spectator.view_mode = Spectator.VIEW_MODE.FREE
Spectator.tracked_player = nil
Spectator.tracked_unit = nil
Spectator.camera_x = 0
Spectator.camera_y = 0
Spectator.zoom = 1.0
Spectator.game = nil
Spectator.players = {}

--[[
    Initialize the spectator adapter.

    @param game - Game instance reference
]]
function Spectator.init(game)
    Spectator.game = game
    Spectator.active = false
    Spectator.view_mode = Spectator.VIEW_MODE.FREE
    Spectator.tracked_player = nil
    Spectator.tracked_unit = nil
    Spectator.camera_x = 0
    Spectator.camera_y = 0
    Spectator.zoom = 1.0
    Spectator.players = {}

    -- Build player list from game
    if game and game.houses then
        for id, house in pairs(game.houses) do
            table.insert(Spectator.players, {
                id = id,
                name = house.name or ("Player " .. id),
                house = house
            })
        end
    end

    Spectator.config.enabled = true
end

--[[
    Enable spectator mode.
]]
function Spectator.enable()
    if not Spectator.config.enabled then
        return false, "Spectator mode not initialized"
    end

    Spectator.active = true

    -- Disable fog of war for spectator
    if Spectator.game and Spectator.game.fog_system then
        Spectator.game.fog_system:set_enabled(false)
    end

    return true, "Spectator mode enabled"
end

--[[
    Disable spectator mode.
]]
function Spectator.disable()
    Spectator.active = false

    -- Re-enable fog of war
    if Spectator.game and Spectator.game.fog_system then
        Spectator.game.fog_system:set_enabled(true)
    end

    return true, "Spectator mode disabled"
end

--[[
    Check if spectator mode is active.
]]
function Spectator.is_active()
    return Spectator.active
end

--[[
    Set the view mode.

    @param mode - VIEW_MODE enum value
]]
function Spectator.set_view_mode(mode)
    if not Spectator.active then
        return false, "Spectator not active"
    end

    Spectator.view_mode = mode

    -- Reset tracking based on mode
    if mode == Spectator.VIEW_MODE.FREE then
        Spectator.tracked_player = nil
        Spectator.tracked_unit = nil
    elseif mode == Spectator.VIEW_MODE.PLAYER then
        Spectator.tracked_unit = nil
    elseif mode == Spectator.VIEW_MODE.UNIT then
        Spectator.tracked_player = nil
    end

    return true
end

--[[
    Get list of players that can be tracked.
]]
function Spectator.get_players()
    return Spectator.players
end

--[[
    Track a specific player's perspective.

    @param player_id - Player/house ID to track
]]
function Spectator.track_player(player_id)
    if not Spectator.active then
        return false, "Spectator not active"
    end

    -- Find player in list
    for _, player in ipairs(Spectator.players) do
        if player.id == player_id then
            Spectator.tracked_player = player
            Spectator.view_mode = Spectator.VIEW_MODE.PLAYER
            return true, "Now tracking: " .. player.name
        end
    end

    return false, "Player not found"
end

--[[
    Track a specific unit.

    @param entity - Entity to track
]]
function Spectator.track_unit(entity)
    if not Spectator.active then
        return false, "Spectator not active"
    end

    if entity and entity:has("transform") then
        Spectator.tracked_unit = entity
        Spectator.view_mode = Spectator.VIEW_MODE.UNIT
        return true, "Now tracking unit"
    end

    return false, "Invalid unit"
end

--[[
    Cycle to next player.
]]
function Spectator.next_player()
    if not Spectator.active then return end
    if #Spectator.players == 0 then return end

    local current_idx = 0
    if Spectator.tracked_player then
        for i, player in ipairs(Spectator.players) do
            if player.id == Spectator.tracked_player.id then
                current_idx = i
                break
            end
        end
    end

    local next_idx = (current_idx % #Spectator.players) + 1
    Spectator.track_player(Spectator.players[next_idx].id)
end

--[[
    Cycle to previous player.
]]
function Spectator.prev_player()
    if not Spectator.active then return end
    if #Spectator.players == 0 then return end

    local current_idx = 1
    if Spectator.tracked_player then
        for i, player in ipairs(Spectator.players) do
            if player.id == Spectator.tracked_player.id then
                current_idx = i
                break
            end
        end
    end

    local prev_idx = current_idx - 1
    if prev_idx < 1 then prev_idx = #Spectator.players end
    Spectator.track_player(Spectator.players[prev_idx].id)
end

--[[
    Set free camera position.

    @param x, y - World coordinates
]]
function Spectator.set_camera(x, y)
    Spectator.camera_x = x
    Spectator.camera_y = y
end

--[[
    Move camera by delta.

    @param dx, dy - Delta movement
]]
function Spectator.move_camera(dx, dy)
    Spectator.camera_x = Spectator.camera_x + dx
    Spectator.camera_y = Spectator.camera_y + dy
end

--[[
    Set zoom level.

    @param zoom - Zoom factor (1.0 = normal)
]]
function Spectator.set_zoom(zoom)
    Spectator.zoom = math.max(Spectator.config.zoom_min,
        math.min(Spectator.config.zoom_max, zoom))
end

--[[
    Adjust zoom by delta.

    @param delta - Zoom change
]]
function Spectator.adjust_zoom(delta)
    Spectator.set_zoom(Spectator.zoom + delta)
end

--[[
    Update spectator state.

    @param dt - Delta time
]]
function Spectator.update(dt)
    if not Spectator.active then return end

    -- Handle camera movement based on view mode
    if Spectator.view_mode == Spectator.VIEW_MODE.PLAYER then
        -- Follow player's camera if they have one
        if Spectator.tracked_player and Spectator.game then
            local house_id = Spectator.tracked_player.id
            -- Get player's scroll position
            if Spectator.game.scroll_x and Spectator.game.scroll_y then
                -- Could sync to player's view here
            end
        end

    elseif Spectator.view_mode == Spectator.VIEW_MODE.UNIT then
        -- Follow tracked unit
        if Spectator.tracked_unit and Spectator.tracked_unit:has("transform") then
            local transform = Spectator.tracked_unit:get("transform")
            Spectator.camera_x = transform.x
            Spectator.camera_y = transform.y
        else
            -- Unit no longer exists, switch to free mode
            Spectator.view_mode = Spectator.VIEW_MODE.FREE
            Spectator.tracked_unit = nil
        end

    elseif Spectator.view_mode == Spectator.VIEW_MODE.FREE then
        -- Handle free camera input
        local speed = Spectator.config.camera_speed * dt

        if love and love.keyboard then
            if love.keyboard.isDown("w") or love.keyboard.isDown("up") then
                Spectator.camera_y = Spectator.camera_y - speed
            end
            if love.keyboard.isDown("s") or love.keyboard.isDown("down") then
                Spectator.camera_y = Spectator.camera_y + speed
            end
            if love.keyboard.isDown("a") or love.keyboard.isDown("left") then
                Spectator.camera_x = Spectator.camera_x - speed
            end
            if love.keyboard.isDown("d") or love.keyboard.isDown("right") then
                Spectator.camera_x = Spectator.camera_x + speed
            end

            -- Zoom with +/-
            if love.keyboard.isDown("=") or love.keyboard.isDown("+") then
                Spectator.adjust_zoom(dt)
            end
            if love.keyboard.isDown("-") then
                Spectator.adjust_zoom(-dt)
            end
        end
    end
end

--[[
    Handle key press events.

    @param key - Key that was pressed
]]
function Spectator.keypressed(key)
    if not Spectator.active then return false end

    -- Player cycling
    if key == "tab" then
        if love and love.keyboard.isDown("lshift", "rshift") then
            Spectator.prev_player()
        else
            Spectator.next_player()
        end
        return true
    end

    -- Number keys for direct player selection
    local num = tonumber(key)
    if num and num >= 1 and num <= 9 then
        if Spectator.players[num] then
            Spectator.track_player(Spectator.players[num].id)
        end
        return true
    end

    -- Free camera mode
    if key == "f" then
        Spectator.set_view_mode(Spectator.VIEW_MODE.FREE)
        return true
    end

    -- Toggle show all units
    if key == "v" then
        Spectator.config.show_all_units = not Spectator.config.show_all_units
        return true
    end

    -- Reset zoom
    if key == "r" then
        Spectator.zoom = 1.0
        return true
    end

    return false
end

--[[
    Get camera transform for rendering.

    @return x, y, zoom - Camera position and zoom
]]
function Spectator.get_camera_transform()
    return Spectator.camera_x, Spectator.camera_y, Spectator.zoom
end

--[[
    Draw spectator UI overlay.
]]
function Spectator.draw_overlay()
    if not Spectator.active or not love then return end

    local width, height = love.graphics.getDimensions()

    -- Draw semi-transparent header bar
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, width, 30)

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("SPECTATOR MODE", 10, 5)

    -- Show current view mode
    local mode_text = "FREE CAMERA"
    if Spectator.view_mode == Spectator.VIEW_MODE.PLAYER and Spectator.tracked_player then
        mode_text = "Following: " .. Spectator.tracked_player.name
    elseif Spectator.view_mode == Spectator.VIEW_MODE.UNIT then
        mode_text = "Following Unit"
    end
    love.graphics.print(mode_text, 200, 5)

    -- Show zoom
    love.graphics.print(string.format("Zoom: %.1fx", Spectator.zoom), 450, 5)

    -- Draw player list on right side
    if Spectator.config.show_credits then
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", width - 200, 40, 190, 20 + #Spectator.players * 25)

        for i, player in ipairs(Spectator.players) do
            local y = 45 + (i - 1) * 25

            -- Highlight tracked player
            if Spectator.tracked_player and Spectator.tracked_player.id == player.id then
                love.graphics.setColor(0.3, 0.3, 0.5)
                love.graphics.rectangle("fill", width - 195, y - 2, 180, 22)
            end

            -- Player color indicator
            love.graphics.setColor(1, 1, 0)  -- Yellow for GDI-ish
            if player.id == 1 then
                love.graphics.setColor(1, 0, 0)  -- Red for NOD-ish
            end
            love.graphics.rectangle("fill", width - 195, y, 10, 18)

            -- Player name and credits
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(player.name, width - 180, y)

            if player.house and player.house.credits then
                love.graphics.setColor(0, 1, 0)
                love.graphics.print(string.format("$%d", player.house.credits),
                    width - 80, y)
            end
        end
    end

    -- Instructions at bottom
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, height - 25, width, 25)

    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.print(
        "[TAB] Next Player  [1-9] Select Player  [F] Free Camera  [V] Toggle Units  [+/-] Zoom",
        10, height - 20)

    love.graphics.setColor(1, 1, 1)
end

--[[
    Check if an entity should be visible to spectator.

    @param entity - Entity to check
    @return true if visible
]]
function Spectator.is_entity_visible(entity)
    if not Spectator.active then return true end

    -- In spectator mode with show_all_units, everything is visible
    if Spectator.config.show_all_units then
        return true
    end

    -- Otherwise, follow tracked player's visibility
    if Spectator.tracked_player and entity:has("owner") then
        local owner = entity:get("owner")
        return owner.house == Spectator.tracked_player.id
    end

    return true
end

--[[
    Get player info for UI display.

    @param house_id - House ID
    @return Table with player info
]]
function Spectator.get_player_info(house_id)
    if not Spectator.game then return nil end

    local info = {
        credits = 0,
        power = 0,
        drain = 0,
        unit_count = 0,
        building_count = 0
    }

    -- Get credits from harvest system
    if Spectator.game.harvest_system then
        info.credits = Spectator.game.harvest_system:get_credits(house_id) or 0
    end

    -- Count entities
    if Spectator.game.world then
        local entities = Spectator.game.world:get_all_entities()
        for _, entity in ipairs(entities) do
            if entity:has("owner") then
                local owner = entity:get("owner")
                if owner.house == house_id then
                    if entity:has("building") then
                        info.building_count = info.building_count + 1
                        local b = entity:get("building")
                        info.power = info.power + (b.power or 0)
                        info.drain = info.drain + (b.drain or 0)
                    elseif entity:has("unit") or entity:has("infantry") then
                        info.unit_count = info.unit_count + 1
                    end
                end
            end
        end
    end

    return info
end

--[[
    Get current spectator state for serialization.
]]
function Spectator.get_state()
    return {
        active = Spectator.active,
        view_mode = Spectator.view_mode,
        tracked_player_id = Spectator.tracked_player and Spectator.tracked_player.id,
        camera_x = Spectator.camera_x,
        camera_y = Spectator.camera_y,
        zoom = Spectator.zoom,
        config = Spectator.config
    }
end

--[[
    Restore spectator state.

    @param state - Previously saved state
]]
function Spectator.restore_state(state)
    if not state then return end

    Spectator.active = state.active or false
    Spectator.view_mode = state.view_mode or Spectator.VIEW_MODE.FREE
    Spectator.camera_x = state.camera_x or 0
    Spectator.camera_y = state.camera_y or 0
    Spectator.zoom = state.zoom or 1.0

    if state.config then
        for k, v in pairs(state.config) do
            Spectator.config[k] = v
        end
    end

    if state.tracked_player_id then
        Spectator.track_player(state.tracked_player_id)
    end
end

return Spectator
