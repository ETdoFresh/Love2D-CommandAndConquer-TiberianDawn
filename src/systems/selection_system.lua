--[[
    Selection System - Handles unit selection and control groups
    Supports both classic (single click) and modern (drag box) selection
]]

local System = require("src.ecs.system")
local Constants = require("src.core.constants")
local Events = require("src.core.events")

local SelectionSystem = setmetatable({}, {__index = System})
SelectionSystem.__index = SelectionSystem

function SelectionSystem.new()
    local self = System.new("selection", {"transform", "selectable"})
    setmetatable(self, SelectionSystem)

    -- Selected entities
    self.selected = {}  -- Set of entity IDs

    -- Control groups (1-9)
    self.control_groups = {}
    for i = 1, 9 do
        self.control_groups[i] = {}
    end

    -- Drag selection state
    self.is_dragging = false
    self.drag_start_x = 0
    self.drag_start_y = 0
    self.drag_end_x = 0
    self.drag_end_y = 0
    self.drag_threshold = 5  -- Pixels before drag starts

    -- Selection mode
    self.mode = "modern"  -- "classic" or "modern"

    -- Filter for player-owned only
    self.player_house = Constants.HOUSE.GOOD

    return self
end

function SelectionSystem:init()
    -- Subscribe to events
    self:on(Events.EVENTS.ENTITY_DESTROYED, function(entity)
        self:deselect(entity)
    end)
end

function SelectionSystem:update(dt, entities)
    -- Remove dead entities from selection
    local to_remove = {}
    for entity_id in pairs(self.selected) do
        local entity = self.world:get_entity(entity_id)
        if not entity or not entity:is_alive() then
            table.insert(to_remove, entity_id)
        end
    end

    for _, entity_id in ipairs(to_remove) do
        self.selected[entity_id] = nil
    end
end

-- Select a single entity
function SelectionSystem:select(entity, add_to_selection)
    if not entity or not entity:has("selectable") then
        return false
    end

    -- Check ownership
    if entity:has("owner") then
        local owner = entity:get("owner")
        if owner.house ~= self.player_house then
            -- Can only select own units
            return false
        end
    end

    if not add_to_selection then
        self:clear_selection()
    end

    local selectable = entity:get("selectable")
    selectable.selected = true
    self.selected[entity.id] = true

    self:emit(Events.EVENTS.SELECTION_CHANGED, self:get_selected_entities())
    return true
end

-- Deselect a single entity
function SelectionSystem:deselect(entity)
    if not entity then return end

    if entity:has("selectable") then
        local selectable = entity:get("selectable")
        selectable.selected = false
    end

    self.selected[entity.id] = nil
    self:emit(Events.EVENTS.SELECTION_CHANGED, self:get_selected_entities())
end

-- Toggle selection state
function SelectionSystem:toggle_select(entity)
    if not entity or not entity:has("selectable") then
        return
    end

    local selectable = entity:get("selectable")
    if selectable.selected then
        self:deselect(entity)
    else
        self:select(entity, true)
    end
end

-- Clear all selection
function SelectionSystem:clear_selection()
    for entity_id in pairs(self.selected) do
        local entity = self.world:get_entity(entity_id)
        if entity and entity:has("selectable") then
            entity:get("selectable").selected = false
        end
    end
    self.selected = {}
    self:emit(Events.EVENTS.SELECTION_CLEARED)
end

-- Get list of selected entities
function SelectionSystem:get_selected_entities()
    local entities = {}
    for entity_id in pairs(self.selected) do
        local entity = self.world:get_entity(entity_id)
        if entity and entity:is_alive() then
            table.insert(entities, entity)
        end
    end
    return entities
end

-- Get selected count
function SelectionSystem:get_selection_count()
    local count = 0
    for _ in pairs(self.selected) do
        count = count + 1
    end
    return count
end

-- Check if entity is selected
function SelectionSystem:is_selected(entity)
    return self.selected[entity.id] == true
end

-- Select entities in rectangle (world coordinates)
function SelectionSystem:select_in_rect(x1, y1, x2, y2, add_to_selection)
    if not add_to_selection then
        self:clear_selection()
    end

    -- Normalize rectangle
    if x1 > x2 then x1, x2 = x2, x1 end
    if y1 > y2 then y1, y2 = y2, y1 end

    -- Convert to leptons
    local lx1 = x1 * Constants.PIXEL_LEPTON_W
    local ly1 = y1 * Constants.PIXEL_LEPTON_H
    local lx2 = x2 * Constants.PIXEL_LEPTON_W
    local ly2 = y2 * Constants.PIXEL_LEPTON_H

    local entities = self:get_entities()
    local selected_any = false

    for _, entity in ipairs(entities) do
        if entity:has("owner") then
            local owner = entity:get("owner")
            if owner.house == self.player_house then
                local transform = entity:get("transform")
                if transform.x >= lx1 and transform.x <= lx2 and
                   transform.y >= ly1 and transform.y <= ly2 then
                    self:select(entity, true)
                    selected_any = true
                end
            end
        end
    end

    return selected_any
end

-- Select all units of same type as currently selected
function SelectionSystem:select_all_of_type()
    local selected = self:get_selected_entities()
    if #selected == 0 then return end

    -- Get type of first selected
    local first = selected[1]
    local type_tag = nil

    if first:has("infantry") then
        type_tag = first:get("infantry").infantry_type
    elseif first:has("vehicle") then
        type_tag = first:get("vehicle").vehicle_type
    elseif first:has("building") then
        type_tag = first:get("building").structure_type
    end

    if not type_tag then return end

    -- Select all of same type
    local entities = self:get_entities()
    for _, entity in ipairs(entities) do
        if entity:has("owner") then
            local owner = entity:get("owner")
            if owner.house == self.player_house then
                local match = false
                if first:has("infantry") and entity:has("infantry") then
                    match = entity:get("infantry").infantry_type == type_tag
                elseif first:has("vehicle") and entity:has("vehicle") then
                    match = entity:get("vehicle").vehicle_type == type_tag
                elseif first:has("building") and entity:has("building") then
                    match = entity:get("building").structure_type == type_tag
                end

                if match then
                    self:select(entity, true)
                end
            end
        end
    end
end

-- Assign selection to control group
function SelectionSystem:assign_control_group(group_num)
    if group_num < 1 or group_num > 9 then return end

    self.control_groups[group_num] = {}
    for entity_id in pairs(self.selected) do
        local entity = self.world:get_entity(entity_id)
        if entity and entity:has("selectable") then
            entity:get("selectable").group = group_num
            table.insert(self.control_groups[group_num], entity_id)
        end
    end
end

-- Select control group
function SelectionSystem:select_control_group(group_num, add_to_selection)
    if group_num < 1 or group_num > 9 then return end

    if not add_to_selection then
        self:clear_selection()
    end

    for _, entity_id in ipairs(self.control_groups[group_num]) do
        local entity = self.world:get_entity(entity_id)
        if entity and entity:is_alive() then
            self:select(entity, true)
        end
    end
end

-- Mouse input handling
function SelectionSystem:on_mouse_pressed(x, y, button, render_system)
    if button == 1 then  -- Left click
        self.is_dragging = true
        self.drag_start_x = x
        self.drag_start_y = y
        self.drag_end_x = x
        self.drag_end_y = y
    end
end

function SelectionSystem:on_mouse_moved(x, y)
    if self.is_dragging then
        self.drag_end_x = x
        self.drag_end_y = y
    end
end

function SelectionSystem:on_mouse_released(x, y, button, render_system)
    if button == 1 and self.is_dragging then
        self.is_dragging = false

        local dx = math.abs(x - self.drag_start_x)
        local dy = math.abs(y - self.drag_start_y)

        local shift_held = love.keyboard.isDown("lshift", "rshift")

        if dx < self.drag_threshold and dy < self.drag_threshold then
            -- Click selection
            self:handle_click_selection(x, y, render_system, shift_held)
        else
            -- Drag box selection
            local wx1, wy1 = render_system:screen_to_world(self.drag_start_x, self.drag_start_y)
            local wx2, wy2 = render_system:screen_to_world(x, y)
            self:select_in_rect(wx1, wy1, wx2, wy2, shift_held)
        end
    end
end

function SelectionSystem:handle_click_selection(screen_x, screen_y, render_system, add_to_selection)
    local world_x, world_y = render_system:screen_to_world(screen_x, screen_y)

    -- Convert to leptons
    local lx = world_x * Constants.PIXEL_LEPTON_W
    local ly = world_y * Constants.PIXEL_LEPTON_H

    -- Find entity under click
    local click_radius = Constants.LEPTON_PER_CELL / 2

    local entities = self:get_entities()
    local best_entity = nil
    local best_dist = click_radius

    for _, entity in ipairs(entities) do
        local transform = entity:get("transform")
        local dx = transform.x - lx
        local dy = transform.y - ly
        local dist = math.sqrt(dx * dx + dy * dy)

        if dist < best_dist then
            best_dist = dist
            best_entity = entity
        end
    end

    if best_entity then
        if add_to_selection then
            self:toggle_select(best_entity)
        else
            self:select(best_entity, false)
        end
    elseif not add_to_selection then
        self:clear_selection()
    end
end

-- Draw selection box
function SelectionSystem:draw_selection_box()
    if not self.is_dragging then return end

    local dx = math.abs(self.drag_end_x - self.drag_start_x)
    local dy = math.abs(self.drag_end_y - self.drag_start_y)

    if dx >= self.drag_threshold or dy >= self.drag_threshold then
        love.graphics.setColor(0, 1, 0, 0.3)
        love.graphics.rectangle("fill",
            math.min(self.drag_start_x, self.drag_end_x),
            math.min(self.drag_start_y, self.drag_end_y),
            dx, dy)

        love.graphics.setColor(0, 1, 0, 1)
        love.graphics.rectangle("line",
            math.min(self.drag_start_x, self.drag_end_x),
            math.min(self.drag_start_y, self.drag_end_y),
            dx, dy)

        love.graphics.setColor(1, 1, 1, 1)
    end
end

return SelectionSystem
