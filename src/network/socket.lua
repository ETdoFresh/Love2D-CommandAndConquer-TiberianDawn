--[[
    Socket - LuaSocket wrapper for network communication
    Provides TCP and UDP networking for multiplayer
    Reference: LuaSocket documentation, EVENT.H
]]

local Events = require("src.core.events")

-- Try to load LuaSocket
local socket = nil
local has_socket = pcall(function()
    socket = require("socket")
end)

local Socket = {}
Socket.__index = Socket

-- Connection states
Socket.STATE = {
    DISCONNECTED = "disconnected",
    CONNECTING = "connecting",
    CONNECTED = "connected",
    LISTENING = "listening",
    ERROR = "error"
}

-- Default settings
Socket.DEFAULT_PORT = 7777
Socket.TIMEOUT = 0.001  -- Non-blocking
Socket.BUFFER_SIZE = 4096
Socket.HEARTBEAT_INTERVAL = 1.0  -- Seconds
Socket.TIMEOUT_THRESHOLD = 10.0  -- Seconds without response = disconnect

function Socket.new()
    local self = setmetatable({}, Socket)

    -- Check socket availability
    self.has_socket = has_socket

    -- Connection state
    self.state = Socket.STATE.DISCONNECTED

    -- TCP for reliable messages
    self.tcp_socket = nil
    self.tcp_clients = {}  -- For server: connected clients

    -- UDP for fast updates
    self.udp_socket = nil

    -- Address info
    self.local_address = nil
    self.local_port = nil
    self.remote_address = nil
    self.remote_port = nil

    -- Receive buffer
    self.receive_buffer = ""
    self.message_queue = {}

    -- Timing
    self.last_send_time = 0
    self.last_receive_time = 0
    self.heartbeat_timer = 0

    -- Statistics
    self.stats = {
        bytes_sent = 0,
        bytes_received = 0,
        packets_sent = 0,
        packets_received = 0,
        latency = 0
    }

    -- Callbacks
    self.on_connect = nil
    self.on_disconnect = nil
    self.on_receive = nil
    self.on_error = nil

    return self
end

-- Check if networking is available
function Socket:is_available()
    return self.has_socket
end

-- Initialize as server (host)
function Socket:listen(port)
    if not self.has_socket then
        return false, "LuaSocket not available"
    end

    port = port or Socket.DEFAULT_PORT

    -- Create TCP server socket
    local tcp, err = socket.tcp()
    if not tcp then
        self.state = Socket.STATE.ERROR
        return false, "Failed to create TCP socket: " .. (err or "unknown")
    end

    -- Set options
    tcp:setoption("reuseaddr", true)
    tcp:settimeout(Socket.TIMEOUT)

    -- Bind to port
    local ok, bind_err = tcp:bind("*", port)
    if not ok then
        tcp:close()
        self.state = Socket.STATE.ERROR
        return false, "Failed to bind to port " .. port .. ": " .. (bind_err or "unknown")
    end

    -- Listen for connections
    local listen_ok, listen_err = tcp:listen(Socket.BUFFER_SIZE)
    if not listen_ok then
        tcp:close()
        self.state = Socket.STATE.ERROR
        return false, "Failed to listen: " .. (listen_err or "unknown")
    end

    self.tcp_socket = tcp
    self.local_port = port

    -- Create UDP socket for game state updates
    local udp = socket.udp()
    if udp then
        udp:settimeout(Socket.TIMEOUT)
        udp:setsockname("*", port)
        self.udp_socket = udp
    end

    self.state = Socket.STATE.LISTENING
    self.last_receive_time = socket.gettime()

    -- Get local address
    local sockname = tcp:getsockname()
    self.local_address = sockname

    return true
end

-- Connect to server (client)
function Socket:connect(host, port)
    if not self.has_socket then
        return false, "LuaSocket not available"
    end

    port = port or Socket.DEFAULT_PORT
    self.state = Socket.STATE.CONNECTING

    -- Create TCP socket
    local tcp, err = socket.tcp()
    if not tcp then
        self.state = Socket.STATE.ERROR
        return false, "Failed to create TCP socket: " .. (err or "unknown")
    end

    tcp:settimeout(5)  -- 5 second connection timeout

    -- Connect
    local ok, connect_err = tcp:connect(host, port)
    if not ok then
        tcp:close()
        self.state = Socket.STATE.ERROR
        return false, "Failed to connect to " .. host .. ":" .. port .. ": " .. (connect_err or "unknown")
    end

    -- Set non-blocking after connection
    tcp:settimeout(Socket.TIMEOUT)

    self.tcp_socket = tcp
    self.remote_address = host
    self.remote_port = port

    -- Create UDP socket
    local udp = socket.udp()
    if udp then
        udp:settimeout(Socket.TIMEOUT)
        udp:setpeername(host, port)
        self.udp_socket = udp
    end

    self.state = Socket.STATE.CONNECTED
    self.last_receive_time = socket.gettime()

    if self.on_connect then
        self.on_connect()
    end

    return true
end

-- Accept incoming connection (server)
function Socket:accept()
    if self.state ~= Socket.STATE.LISTENING or not self.tcp_socket then
        return nil
    end

    local client, err = self.tcp_socket:accept()
    if client then
        client:settimeout(Socket.TIMEOUT)

        local addr, port = client:getpeername()
        local client_id = addr .. ":" .. port

        self.tcp_clients[client_id] = {
            socket = client,
            address = addr,
            port = port,
            last_receive = socket.gettime()
        }

        return client_id, addr, port
    end

    return nil
end

-- Send data over TCP (reliable)
function Socket:send_tcp(data, client_id)
    if not data then return false end

    -- Add length prefix for framing
    local packet = string.pack(">I4", #data) .. data

    if self.state == Socket.STATE.LISTENING then
        -- Server: send to specific client or all
        if client_id then
            local client = self.tcp_clients[client_id]
            if client and client.socket then
                local ok, err = client.socket:send(packet)
                if ok then
                    self.stats.bytes_sent = self.stats.bytes_sent + #packet
                    self.stats.packets_sent = self.stats.packets_sent + 1
                    return true
                else
                    self:handle_client_error(client_id, err)
                    return false, err
                end
            end
        else
            -- Broadcast to all clients
            for cid, client in pairs(self.tcp_clients) do
                if client.socket then
                    client.socket:send(packet)
                end
            end
            self.stats.bytes_sent = self.stats.bytes_sent + #packet * self:get_client_count()
            self.stats.packets_sent = self.stats.packets_sent + self:get_client_count()
            return true
        end
    elseif self.state == Socket.STATE.CONNECTED and self.tcp_socket then
        -- Client: send to server
        local ok, err = self.tcp_socket:send(packet)
        if ok then
            self.stats.bytes_sent = self.stats.bytes_sent + #packet
            self.stats.packets_sent = self.stats.packets_sent + 1
            self.last_send_time = socket.gettime()
            return true
        else
            self:handle_error(err)
            return false, err
        end
    end

    return false, "Not connected"
end

-- Send data over UDP (fast, unreliable)
function Socket:send_udp(data, address, port)
    if not self.udp_socket or not data then return false end

    local ok, err
    if address and port then
        ok, err = self.udp_socket:sendto(data, address, port)
    else
        ok, err = self.udp_socket:send(data)
    end

    if ok then
        self.stats.bytes_sent = self.stats.bytes_sent + #data
        self.stats.packets_sent = self.stats.packets_sent + 1
        return true
    end

    return false, err
end

-- Receive TCP data
function Socket:receive_tcp()
    local messages = {}

    if self.state == Socket.STATE.LISTENING then
        -- Server: receive from all clients
        for client_id, client in pairs(self.tcp_clients) do
            local msg = self:receive_from_client(client_id)
            while msg do
                table.insert(messages, {
                    client_id = client_id,
                    address = client.address,
                    port = client.port,
                    data = msg
                })
                msg = self:receive_from_client(client_id)
            end
        end
    elseif self.state == Socket.STATE.CONNECTED and self.tcp_socket then
        -- Client: receive from server
        local msg = self:receive_framed(self.tcp_socket)
        while msg do
            table.insert(messages, {
                address = self.remote_address,
                port = self.remote_port,
                data = msg
            })
            self.last_receive_time = socket.gettime()
            msg = self:receive_framed(self.tcp_socket)
        end
    end

    return messages
end

-- Receive from specific client
function Socket:receive_from_client(client_id)
    local client = self.tcp_clients[client_id]
    if not client or not client.socket then return nil end

    local msg = self:receive_framed(client.socket)
    if msg then
        client.last_receive = socket.gettime()
    end

    return msg
end

-- Receive framed message (with length prefix)
function Socket:receive_framed(sock)
    if not sock then return nil end

    -- First try to get length (4 bytes)
    local len_data, err, partial = sock:receive(4)

    if not len_data then
        if partial and #partial > 0 then
            -- Partial read, buffer it
            self.receive_buffer = self.receive_buffer .. partial
        end
        return nil
    end

    local len = string.unpack(">I4", len_data)
    if len > Socket.BUFFER_SIZE then
        -- Invalid length, skip
        return nil
    end

    -- Read message body
    local data, body_err = sock:receive(len)
    if data then
        self.stats.bytes_received = self.stats.bytes_received + 4 + len
        self.stats.packets_received = self.stats.packets_received + 1
        return data
    end

    return nil
end

-- Receive UDP data
function Socket:receive_udp()
    if not self.udp_socket then return nil end

    local data, addr_or_err, port = self.udp_socket:receivefrom()
    if data then
        self.stats.bytes_received = self.stats.bytes_received + #data
        self.stats.packets_received = self.stats.packets_received + 1
        return data, addr_or_err, port
    end

    return nil
end

-- Update (call each frame)
function Socket:update(dt)
    if not self.has_socket then return end

    local now = socket.gettime()

    -- Accept new connections (server)
    if self.state == Socket.STATE.LISTENING then
        local client_id, addr, port = self:accept()
        if client_id then
            Events.emit("CLIENT_CONNECTED", client_id, addr, port)
        end

        -- Check for client timeouts
        for client_id, client in pairs(self.tcp_clients) do
            if now - client.last_receive > Socket.TIMEOUT_THRESHOLD then
                self:disconnect_client(client_id)
            end
        end
    end

    -- Check for timeout (client)
    if self.state == Socket.STATE.CONNECTED then
        if now - self.last_receive_time > Socket.TIMEOUT_THRESHOLD then
            self:handle_error("Connection timeout")
        end
    end

    -- Heartbeat
    self.heartbeat_timer = self.heartbeat_timer + dt
    if self.heartbeat_timer >= Socket.HEARTBEAT_INTERVAL then
        self.heartbeat_timer = 0
        self:send_heartbeat()
    end
end

-- Send heartbeat
function Socket:send_heartbeat()
    if self.state == Socket.STATE.CONNECTED then
        -- Send ping packet (just timestamp)
        local ping = string.pack(">Bd", 0xFF, socket.gettime())
        self:send_tcp(ping)
    end
end

-- Handle error
function Socket:handle_error(err)
    if self.on_error then
        self.on_error(err)
    end

    self:disconnect()
end

-- Handle client error (server)
function Socket:handle_client_error(client_id, err)
    if err == "closed" or err == "timeout" then
        self:disconnect_client(client_id)
    end
end

-- Disconnect client (server)
function Socket:disconnect_client(client_id)
    local client = self.tcp_clients[client_id]
    if client then
        if client.socket then
            client.socket:close()
        end
        self.tcp_clients[client_id] = nil

        Events.emit("CLIENT_DISCONNECTED", client_id)

        if self.on_disconnect then
            self.on_disconnect(client_id)
        end
    end
end

-- Get client count
function Socket:get_client_count()
    local count = 0
    for _ in pairs(self.tcp_clients) do
        count = count + 1
    end
    return count
end

-- Disconnect
function Socket:disconnect()
    -- Close TCP
    if self.tcp_socket then
        self.tcp_socket:close()
        self.tcp_socket = nil
    end

    -- Close all client connections
    for client_id, client in pairs(self.tcp_clients) do
        if client.socket then
            client.socket:close()
        end
    end
    self.tcp_clients = {}

    -- Close UDP
    if self.udp_socket then
        self.udp_socket:close()
        self.udp_socket = nil
    end

    local was_connected = self.state == Socket.STATE.CONNECTED or
                          self.state == Socket.STATE.LISTENING

    self.state = Socket.STATE.DISCONNECTED

    if was_connected and self.on_disconnect then
        self.on_disconnect()
    end
end

-- Get connection state
function Socket:get_state()
    return self.state
end

-- Get statistics
function Socket:get_stats()
    return {
        state = self.state,
        bytes_sent = self.stats.bytes_sent,
        bytes_received = self.stats.bytes_received,
        packets_sent = self.stats.packets_sent,
        packets_received = self.stats.packets_received,
        clients = self:get_client_count(),
        latency = self.stats.latency
    }
end

-- Get local endpoint info
function Socket:get_local_endpoint()
    return self.local_address, self.local_port
end

-- Get remote endpoint info
function Socket:get_remote_endpoint()
    return self.remote_address, self.remote_port
end

-- Cleanup
function Socket:destroy()
    self:disconnect()
end

return Socket
