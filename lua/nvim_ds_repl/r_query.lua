local M = {}
local function json_encode(payload)
    local encoder = vim.json and vim.json.encode or vim.fn.json_encode
    return pcall(encoder, payload)
end

local function json_decode(payload)
    local decoder = vim.json and vim.json.decode or vim.fn.json_decode
    return pcall(decoder, payload)
end

-- Helper function to make HTTP requests using vim.loop
local function make_request(request, port, callback)
    local client = vim.loop.new_tcp()
    
    -- Prepare request data
    local ok, request_body = json_encode(request)
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
                    local ok, response_json = json_decode(response_body)
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
    -- Create new buffer
    local buf = vim.api.nvim_create_buf(false, true)
    
    -- Process content (handle both string and table input)
    local content_lines = type(content) == "string" 
        and vim.split(content:gsub("\\n", "\n"), "\n", { plain = true })
        or content
    
    -- Set buffer content
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content_lines)
    
    -- Calculate dimensions
    local max_width = 0
    for _, line in ipairs(content_lines) do
        max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
    end
    
    -- Add padding and set window dimensions
    local padding = 4
    local win_width = math.min(max_width + padding, math.floor(vim.o.columns * 0.9))
    local win_height = math.min(#content_lines, math.floor(vim.o.lines * 0.8))
    
    -- Ensure minimum dimensions
    win_width = math.max(win_width, 40)
    win_height = math.max(win_height, 3)
    
    -- Window configuration
    local win_opts = {
        relative = 'editor',
        width = win_width,
        height = win_height,
        row = math.floor((vim.o.lines - win_height) / 2),
        col = math.floor((vim.o.columns - win_width) / 2),
        style = 'minimal',
        border = borderline or 'rounded',
        title = ' Info ',
        title_pos = 'center',
        zindex = 100
    }
    
    -- Create window
    local win = vim.api.nvim_open_win(buf, true, win_opts)
    
    -- Set buffer options
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
    vim.api.nvim_buf_set_option(buf, 'filetype', syntax or 'text')
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    
    -- Window styling
    vim.api.nvim_set_hl(0, 'FloatBorder', { fg = '#89b4fa', bg = '#000000' })
    vim.api.nvim_set_hl(0, 'NormalFloat', { bg = '#000000' })
    vim.api.nvim_win_set_option(win, 'winhighlight', 'Normal:NormalFloat,FloatBorder:FloatBorder')
    
    -- Window options
    vim.api.nvim_win_set_option(win, 'wrap', true)
    vim.api.nvim_win_set_option(win, 'cursorline', true)
    vim.api.nvim_win_set_option(win, 'winblend', 0)

    -- Key mappings
    local opts = { noremap = true, silent = true, buffer = buf }
    vim.keymap.set('n', 'q', function() vim.api.nvim_win_close(win, true) end, opts)
    vim.keymap.set('n', '<Esc>', function() vim.api.nvim_win_close(win, true) end, opts)
    vim.keymap.set('n', '<C-c>', function() vim.api.nvim_win_close(win, true) end, opts)
    
    -- Enhanced scrolling
    vim.keymap.set('n', '<C-d>', '<C-d>zz', opts)
    vim.keymap.set('n', '<C-u>', '<C-u>zz', opts)
    vim.keymap.set('n', '<C-f>', '<C-f>zz', opts)
    vim.keymap.set('n', '<C-b>', '<C-b>zz', opts)
    vim.keymap.set('n', 'j', 'gj', opts)
    vim.keymap.set('n', 'k', 'gk', opts)
    vim.keymap.set('n', 'h', '10h', opts)
    vim.keymap.set('n', 'l', '10l', opts)

    -- Autocommands
    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = buf,
        callback = function()
            if vim.api.nvim_win_is_valid(win) then
                vim.api.nvim_win_close(win, true)
            end
        end,
    })

    vim.api.nvim_create_autocmd("VimResized", {
        buffer = buf,
        callback = function()
            if vim.api.nvim_win_is_valid(win) then
                -- Recalculate dimensions
                local new_win_width = math.min(max_width + padding, math.floor(vim.o.columns * 0.9))
                local new_win_height = math.min(#content_lines, math.floor(vim.o.lines * 0.8))
                
                new_win_width = math.max(new_win_width, 40)
                new_win_height = math.max(new_win_height, 3)
                
                vim.api.nvim_win_set_config(win, {
                    relative = 'editor',
                    width = new_win_width,
                    height = new_win_height,
                    row = math.floor((vim.o.lines - new_win_height) / 2),
                    col = math.floor((vim.o.columns - new_win_width) / 2)
                })
            end
        end,
    })

    return buf, win
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

