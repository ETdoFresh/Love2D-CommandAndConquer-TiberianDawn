--[[
    2D Vector math utilities
    Used for positions, velocities, and general 2D math
]]

local Vector = {}
Vector.__index = Vector

-- Create a new vector
function Vector.new(x, y)
    return setmetatable({x = x or 0, y = y or 0}, Vector)
end

-- Create from angle and magnitude
function Vector.from_angle(angle, magnitude)
    magnitude = magnitude or 1
    return Vector.new(
        math.cos(angle) * magnitude,
        math.sin(angle) * magnitude
    )
end

-- Clone vector
function Vector:clone()
    return Vector.new(self.x, self.y)
end

-- Set values
function Vector:set(x, y)
    self.x = x
    self.y = y
    return self
end

-- Addition
function Vector.__add(a, b)
    return Vector.new(a.x + b.x, a.y + b.y)
end

function Vector:add(other)
    self.x = self.x + other.x
    self.y = self.y + other.y
    return self
end

-- Subtraction
function Vector.__sub(a, b)
    return Vector.new(a.x - b.x, a.y - b.y)
end

function Vector:sub(other)
    self.x = self.x - other.x
    self.y = self.y - other.y
    return self
end

-- Scalar multiplication
function Vector.__mul(a, b)
    if type(a) == "number" then
        return Vector.new(a * b.x, a * b.y)
    elseif type(b) == "number" then
        return Vector.new(a.x * b, a.y * b)
    else
        -- Component-wise multiplication
        return Vector.new(a.x * b.x, a.y * b.y)
    end
end

function Vector:scale(s)
    self.x = self.x * s
    self.y = self.y * s
    return self
end

-- Scalar division
function Vector.__div(a, b)
    if type(b) == "number" then
        return Vector.new(a.x / b, a.y / b)
    else
        return Vector.new(a.x / b.x, a.y / b.y)
    end
end

-- Negation
function Vector.__unm(v)
    return Vector.new(-v.x, -v.y)
end

-- Equality
function Vector.__eq(a, b)
    return a.x == b.x and a.y == b.y
end

-- Length (magnitude)
function Vector:len()
    return math.sqrt(self.x * self.x + self.y * self.y)
end

-- Length squared (avoid sqrt for comparisons)
function Vector:len_sq()
    return self.x * self.x + self.y * self.y
end

-- Normalize to unit vector
function Vector:normalize()
    local len = self:len()
    if len > 0 then
        self.x = self.x / len
        self.y = self.y / len
    end
    return self
end

-- Return normalized copy
function Vector:normalized()
    return self:clone():normalize()
end

-- Dot product
function Vector:dot(other)
    return self.x * other.x + self.y * other.y
end

-- Cross product (returns scalar for 2D)
function Vector:cross(other)
    return self.x * other.y - self.y * other.x
end

-- Distance to another vector
function Vector:dist(other)
    local dx = other.x - self.x
    local dy = other.y - self.y
    return math.sqrt(dx * dx + dy * dy)
end

-- Distance squared
function Vector:dist_sq(other)
    local dx = other.x - self.x
    local dy = other.y - self.y
    return dx * dx + dy * dy
end

-- Angle of vector (radians)
function Vector:angle()
    return math.atan2(self.y, self.x)
end

-- Angle to another vector
function Vector:angle_to(other)
    return math.atan2(other.y - self.y, other.x - self.x)
end

-- Rotate by angle (radians)
function Vector:rotate(angle)
    local c = math.cos(angle)
    local s = math.sin(angle)
    local x = self.x * c - self.y * s
    local y = self.x * s + self.y * c
    self.x = x
    self.y = y
    return self
end

-- Return rotated copy
function Vector:rotated(angle)
    return self:clone():rotate(angle)
end

-- Perpendicular vector (90 degrees counter-clockwise)
function Vector:perp()
    return Vector.new(-self.y, self.x)
end

-- Linear interpolation
function Vector:lerp(other, t)
    return Vector.new(
        self.x + (other.x - self.x) * t,
        self.y + (other.y - self.y) * t
    )
end

-- Clamp length
function Vector:clamp_len(max_len)
    local len_sq = self:len_sq()
    if len_sq > max_len * max_len then
        local len = math.sqrt(len_sq)
        self.x = (self.x / len) * max_len
        self.y = (self.y / len) * max_len
    end
    return self
end

-- Floor components
function Vector:floor()
    self.x = math.floor(self.x)
    self.y = math.floor(self.y)
    return self
end

-- Round components
function Vector:round()
    self.x = math.floor(self.x + 0.5)
    self.y = math.floor(self.y + 0.5)
    return self
end

-- Unpack for function calls
function Vector:unpack()
    return self.x, self.y
end

-- String representation
function Vector:__tostring()
    return string.format("Vector(%.2f, %.2f)", self.x, self.y)
end

-- Zero vector constant
Vector.ZERO = Vector.new(0, 0)
Vector.ONE = Vector.new(1, 1)
Vector.UP = Vector.new(0, -1)
Vector.DOWN = Vector.new(0, 1)
Vector.LEFT = Vector.new(-1, 0)
Vector.RIGHT = Vector.new(1, 0)

return Vector
