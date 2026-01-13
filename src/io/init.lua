--[[
    I/O Module - Save/Load system

    This module provides game state serialization and deserialization,
    following the original C&C Code_Pointers/Decode_Pointers pattern.
]]

local IO = {}

-- Export submodules
IO.Pointers = require("src.io.pointers")
IO.Save = require("src.io.save")
IO.Load = require("src.io.load")

-- Convenience functions

--[[
    Save game to file.
    @param filename Save file path
    @param game_state Game state table
    @return true on success
]]
function IO.save_game(filename, game_state)
    return IO.Save.save_game(filename, game_state)
end

--[[
    Load game from file.
    @param filename Save file path
    @return Game state table or nil
]]
function IO.load_game(filename)
    return IO.Load.load_game(filename)
end

--[[
    Quick save with auto-generated filename.
    @param game_state Game state table
    @return true on success
]]
function IO.quick_save(game_state)
    return IO.Save.quick_save(game_state)
end

--[[
    Debug dump of I/O system state.
]]
function IO.Debug_Dump()
    print("=== I/O System ===")
    IO.Save.Debug_Dump()
    IO.Load.Debug_Dump()
    IO.Pointers.Debug_Dump()
end

return IO
