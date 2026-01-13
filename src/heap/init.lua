--[[
    Heap Module - Object pool management

    This module exports the heap management system for game objects.
]]

local Heap = {}

Heap.HeapClass = require("src.heap.heap")
Heap.Globals = require("src.heap.globals")

return Heap
