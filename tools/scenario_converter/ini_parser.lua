--[[
    INI Parser - Parse original C&C scenario INI files
    Reference: Original C&C scenario format (SCxxEA.INI files)
]]

local INIParser = {}
INIParser.__index = INIParser

function INIParser.new()
    local self = setmetatable({}, INIParser)
    return self
end

-- Parse INI content string into sections
function INIParser:parse(content)
    local result = {
        sections = {},
        order = {}  -- Preserve section order
    }

    local current_section = nil

    for line in content:gmatch("[^\r\n]+") do
        -- Remove leading/trailing whitespace
        line = line:match("^%s*(.-)%s*$")

        -- Skip empty lines and comments
        if line ~= "" and not line:match("^;") and not line:match("^#") then
            -- Check for section header [SectionName]
            local section = line:match("^%[(.+)%]$")

            if section then
                current_section = section
                result.sections[section] = {}
                table.insert(result.order, section)
            elseif current_section then
                -- Parse key=value pair
                local key, value = line:match("^([^=]+)=(.*)$")

                if key and value then
                    key = key:match("^%s*(.-)%s*$")
                    value = value:match("^%s*(.-)%s*$")

                    -- Handle comma-separated values
                    if value:find(",") then
                        local values = {}
                        for v in value:gmatch("([^,]+)") do
                            v = v:match("^%s*(.-)%s*$")
                            -- Try to convert to number
                            local num = tonumber(v)
                            table.insert(values, num or v)
                        end
                        result.sections[current_section][key] = values
                    else
                        -- Try to convert to number or boolean
                        local num = tonumber(value)
                        if num then
                            result.sections[current_section][key] = num
                        elseif value:lower() == "true" or value:lower() == "yes" then
                            result.sections[current_section][key] = true
                        elseif value:lower() == "false" or value:lower() == "no" then
                            result.sections[current_section][key] = false
                        else
                            result.sections[current_section][key] = value
                        end
                    end
                end
            end
        end
    end

    return result
end

-- Parse a file
function INIParser:parse_file(filepath)
    local file = io.open(filepath, "r")
    if not file then
        return nil, "Could not open file: " .. filepath
    end

    local content = file:read("*all")
    file:close()

    return self:parse(content)
end

-- Get section
function INIParser:get_section(parsed, section_name)
    return parsed.sections[section_name]
end

-- Get value with default
function INIParser:get_value(parsed, section, key, default)
    local section_data = parsed.sections[section]
    if section_data and section_data[key] ~= nil then
        return section_data[key]
    end
    return default
end

-- Get all sections matching a pattern
function INIParser:get_sections_matching(parsed, pattern)
    local matches = {}

    for _, section_name in ipairs(parsed.order) do
        if section_name:match(pattern) then
            table.insert(matches, {
                name = section_name,
                data = parsed.sections[section_name]
            })
        end
    end

    return matches
end

-- Parse cell reference (e.g., "123" -> x, y)
function INIParser:parse_cell(cell_number, map_width)
    map_width = map_width or 64
    local cell = tonumber(cell_number)
    if not cell then return nil, nil end

    local x = cell % map_width
    local y = math.floor(cell / map_width)
    return x, y
end

-- Parse waypoint format
function INIParser:parse_waypoint(value)
    -- Waypoint can be a cell number or coordinate pair
    if type(value) == "table" then
        return value[1], value[2]
    else
        return self:parse_cell(value)
    end
end

return INIParser
