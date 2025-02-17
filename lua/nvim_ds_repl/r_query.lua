-- r_query.lua
local cjson = require("cjson")
local M = {}

-- Helper function to make HTTP requests using vim.loop
local function make_request(request, port, callback)
    local client = vim.loop.new_tcp()
    
    -- Prepare request data
    local ok, request_body = pcall(cjson.encode, request)
    if not ok then
        vim.schedule(function()
            vim.notify("Failed to encode request to JSON", vim.log.levels.ERROR)
        end)
        return
    end

    local http_request = table.concat({
        string.format("POST / HTTP/1.1"),
        string.format("Host: 127.0.0.1:%d", port),
        "Content-Type: application/json",
        string.format("Content-Length: %d", #request_body),
        "",
        request_body
    }, "\r\n")

    client:connect("127.0.0.1", port, function(err)
        if err then
            vim.schedule(function()
                vim.notify("Connection failed: " .. tostring(err), vim.log.levels.ERROR)
            end)
            client:close()
            return
        end

        client:write(http_request)
        client:read_start(function(err, chunk)
            if err then
                vim.schedule(function()
                    vim.notify("Read error: " .. tostring(err), vim.log.levels.ERROR)
                end)
                client:close()
                return
            end

            if chunk then
                -- Parse HTTP response
                local response_body = chunk:match("\r\n\r\n(.+)$")
                if response_body then
                    local ok, response_json = pcall(cjson.decode, response_body)
                    if ok then
                        vim.schedule(function()
                            callback(response_json)
                        end)
                    else
                        vim.schedule(function()
                            vim.notify("Failed to parse JSON response", vim.log.levels.ERROR)
                        end)
                    end
                end
                client:close()
            end
        end)
    end)
end

local function display_content(content, syntax, borderline)
    vim.api.nvim_set_hl(0, 'FloatBorder', { fg = '#FFFFFF', bg = '#000000' })

    -- Convert content to lines if it's a string
    local content_lines = type(content) == "string" 
        and vim.split(content_lines:gsub("\\n", "\n"), "\n", { plain = true })
        or content

    local win_width = vim.api.nvim_get_option("columns")
    local win_height = vim.api.nvim_get_option("lines")

    local max_content_width = 0
    for _, line in ipairs(content_lines) do
        max_content_width = math.max(max_content_width, vim.fn.strdisplaywidth(line))
    end

    local width = math.min(max_content_width + 2, math.floor(win_width * 0.8))
    local height = math.min(#content_lines, math.floor(win_height * 0.8))

    local row = math.floor((win_height - height) / 2)
    local col = math.floor((win_width - width) / 2)

    local bufnr, winid = vim.lsp.util.open_floating_preview(content_lines, syntax or "plaintext", {
        border = borderline or "rounded",
        focusable = true,
        wrap = false,
        zindex = 100,
        sidescrolloff = 0,
        virtualedit = "onemore",
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
    })

    if not winid or not vim.api.nvim_win_is_valid(winid) then
        vim.notify("Failed to create floating window", vim.log.levels.ERROR)
        return
    end

    vim.api.nvim_set_current_win(winid)
    vim.api.nvim_win_set_option(winid, 'winhl', 'Normal:Normal,FloatBorder:FloatBorder,FloatTitle:FloatTitle')

    local opts = { noremap = true, silent = true, buffer = bufnr }
    vim.keymap.set('n', 'q', function() vim.api.nvim_win_close(winid, true) end, opts)
    vim.keymap.set('n', '<Esc>', function() vim.api.nvim_win_close(winid, true) end, opts)
    vim.keymap.set('n', 'h', '10h', opts)
    vim.keymap.set('n', 'l', '10l', opts)
end



local function HandleReceivedData(response)
    if not response then
        vim.notify("No response received from the server.", vim.log.levels.ERROR)
        return
    end

    if response.status ~= "success" then
        vim.notify("Error from server: " .. (response.message or "unknown error"), vim.log.levels.ERROR)
        return
    end

    local data_type = response.type
    local data = response.data

    if data_type == "info" then
        local content = vim.split(data, "\\n")
        display_content(content, "plaintext")
    else
        vim.notify("Unknown data type received: " .. data_type, vim.log.levels.ERROR)
    end
end

function M.inspect(obj_name, port)
    local request = { type = "inspect", obj = obj_name }
    make_request(request, port, HandleReceivedData)
end



return M


