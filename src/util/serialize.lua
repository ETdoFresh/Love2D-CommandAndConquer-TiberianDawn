--[[
    Serialization Utilities
    Full state save/load for game state
]]

local Serialize = {}

-- Serialize a Lua value to a string
function Serialize.encode(value, indent)
    indent = indent or 0
    local indent_str = string.rep("  ", indent)
    local t = type(value)

    if t == "nil" then
        return "nil"
    elseif t == "boolean" then
        return tostring(value)
    elseif t == "number" then
        if value ~= value then
            return "0/0"  -- NaN
        elseif value == math.huge then
            return "1/0"  -- Infinity
        elseif value == -math.huge then
            return "-1/0"  -- -Infinity
        else
            return tostring(value)
        end
    elseif t == "string" then
        return string.format("%q", value)
    elseif t == "table" then
        local parts = {}
        local is_array = true
        local max_index = 0

        -- Check if it's an array
        for k, v in pairs(value) do
            if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
                is_array = false
                break
            end
            if k > max_index then
                max_index = k
            end
        end

        -- Check for sparse array
        if is_array and max_index > #value * 2 then
            is_array = false
        end

        if is_array then
            -- Encode as array
            for i, v in ipairs(value) do
                table.insert(parts, Serialize.encode(v, indent + 1))
            end
            if #parts == 0 then
                return "{}"
            elseif #parts <= 5 and not string.find(table.concat(parts, ","), "\n") then
                return "{" .. table.concat(parts, ", ") .. "}"
            else
                return "{\n" .. indent_str .. "  " ..
                       table.concat(parts, ",\n" .. indent_str .. "  ") ..
                       "\n" .. indent_str .. "}"
            end
        else
            -- Encode as dictionary
            local keys = {}
            for k in pairs(value) do
                table.insert(keys, k)
            end
            table.sort(keys, function(a, b)
                local ta, tb = type(a), type(b)
                if ta ~= tb then
                    return ta < tb
                end
                return a < b
            end)

            for _, k in ipairs(keys) do
                local v = value[k]
                local key_str
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                    key_str = k
                else
                    key_str = "[" .. Serialize.encode(k, 0) .. "]"
                end
                local val_str = Serialize.encode(v, indent + 1)
                table.insert(parts, key_str .. " = " .. val_str)
            end

            if #parts == 0 then
                return "{}"
            elseif #parts <= 3 and not string.find(table.concat(parts, ","), "\n") then
                return "{" .. table.concat(parts, ", ") .. "}"
            else
                return "{\n" .. indent_str .. "  " ..
                       table.concat(parts, ",\n" .. indent_str .. "  ") ..
                       "\n" .. indent_str .. "}"
            end
        end
    elseif t == "function" or t == "userdata" or t == "thread" then
        return "nil"  -- Can't serialize these
    else
        return "nil"
    end
end

-- Deserialize a string back to a Lua value
function Serialize.decode(str)
    if not str or str == "" then
        return nil, "Empty string"
    end

    -- Wrap in return statement for load()
    local chunk, err = load("return " .. str, "serialized_data", "t", {})
    if not chunk then
        return nil, "Parse error: " .. tostring(err)
    end

    local success, result = pcall(chunk)
    if not success then
        return nil, "Execution error: " .. tostring(result)
    end

    return result
end

-- Save table to file
function Serialize.save_to_file(filepath, data)
    local encoded = Serialize.encode(data)

    local file, err = io.open(filepath, "w")
    if not file then
        return false, "Could not open file: " .. tostring(err)
    end

    file:write("-- Saved game state\n")
    file:write("return " .. encoded .. "\n")
    file:close()

    return true
end

-- Load table from file
function Serialize.load_from_file(filepath)
    local chunk, err = loadfile(filepath)
    if not chunk then
        return nil, "Could not load file: " .. tostring(err)
    end

    local success, result = pcall(chunk)
    if not success then
        return nil, "Execution error: " .. tostring(result)
    end

    return result
end

-- Convert to JSON (simple implementation)
function Serialize.to_json(value, indent)
    indent = indent or 0
    local indent_str = string.rep("  ", indent)
    local t = type(value)

    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return tostring(value)
    elseif t == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return "null"
        end
        return tostring(value)
    elseif t == "string" then
        -- JSON string escaping
        local escaped = value:gsub('[\\"\n\r\t]', {
            ["\\"] = "\\\\",
            ['"'] = '\\"',
            ["\n"] = "\\n",
            ["\r"] = "\\r",
            ["\t"] = "\\t"
        })
        return '"' .. escaped .. '"'
    elseif t == "table" then
        local is_array = true
        local max_index = 0

        for k, v in pairs(value) do
            if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
                is_array = false
                break
            end
            if k > max_index then
                max_index = k
            end
        end

        local parts = {}

        if is_array then
            for i, v in ipairs(value) do
                table.insert(parts, Serialize.to_json(v, indent + 1))
            end
            if #parts == 0 then
                return "[]"
            else
                return "[\n" .. indent_str .. "  " ..
                       table.concat(parts, ",\n" .. indent_str .. "  ") ..
                       "\n" .. indent_str .. "]"
            end
        else
            for k, v in pairs(value) do
                if type(k) == "string" then
                    local key_json = Serialize.to_json(k, 0)
                    local val_json = Serialize.to_json(v, indent + 1)
                    table.insert(parts, key_json .. ": " .. val_json)
                end
            end
            table.sort(parts)
            if #parts == 0 then
                return "{}"
            else
                return "{\n" .. indent_str .. "  " ..
                       table.concat(parts, ",\n" .. indent_str .. "  ") ..
                       "\n" .. indent_str .. "}"
            end
        end
    else
        return "null"
    end
end

-- Parse JSON (simple implementation)
function Serialize.from_json(str)
    if not str then return nil end

    local pos = 1
    local len = #str

    local function skip_whitespace()
        while pos <= len do
            local c = str:sub(pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                pos = pos + 1
            else
                break
            end
        end
    end

    local function parse_value()
        skip_whitespace()
        if pos > len then return nil end

        local c = str:sub(pos, pos)

        if c == '"' then
            -- String
            pos = pos + 1
            local start = pos
            local result = ""
            while pos <= len do
                c = str:sub(pos, pos)
                if c == '"' then
                    pos = pos + 1
                    return result
                elseif c == "\\" then
                    pos = pos + 1
                    local escape = str:sub(pos, pos)
                    if escape == "n" then result = result .. "\n"
                    elseif escape == "r" then result = result .. "\r"
                    elseif escape == "t" then result = result .. "\t"
                    else result = result .. escape
                    end
                else
                    result = result .. c
                end
                pos = pos + 1
            end
            return result

        elseif c == "[" then
            -- Array
            pos = pos + 1
            local arr = {}
            skip_whitespace()
            if str:sub(pos, pos) == "]" then
                pos = pos + 1
                return arr
            end
            while pos <= len do
                local value = parse_value()
                table.insert(arr, value)
                skip_whitespace()
                c = str:sub(pos, pos)
                if c == "]" then
                    pos = pos + 1
                    return arr
                elseif c == "," then
                    pos = pos + 1
                end
            end
            return arr

        elseif c == "{" then
            -- Object
            pos = pos + 1
            local obj = {}
            skip_whitespace()
            if str:sub(pos, pos) == "}" then
                pos = pos + 1
                return obj
            end
            while pos <= len do
                skip_whitespace()
                local key = parse_value()
                skip_whitespace()
                if str:sub(pos, pos) == ":" then
                    pos = pos + 1
                end
                local value = parse_value()
                obj[key] = value
                skip_whitespace()
                c = str:sub(pos, pos)
                if c == "}" then
                    pos = pos + 1
                    return obj
                elseif c == "," then
                    pos = pos + 1
                end
            end
            return obj

        elseif c:match("[%d%-]") then
            -- Number
            local start = pos
            while pos <= len and str:sub(pos, pos):match("[%d%.eE%+%-]") do
                pos = pos + 1
            end
            return tonumber(str:sub(start, pos - 1))

        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true

        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false

        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        end

        return nil
    end

    return parse_value()
end

-- Save JSON to file
function Serialize.save_json(filepath, data)
    local json = Serialize.to_json(data)

    local file, err = io.open(filepath, "w")
    if not file then
        return false, "Could not open file: " .. tostring(err)
    end

    file:write(json)
    file:close()

    return true
end

-- Load JSON from file
function Serialize.load_json(filepath)
    local file, err = io.open(filepath, "r")
    if not file then
        return nil, "Could not open file: " .. tostring(err)
    end

    local content = file:read("*all")
    file:close()

    return Serialize.from_json(content)
end

return Serialize
