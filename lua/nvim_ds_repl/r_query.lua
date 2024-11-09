-- query.lua

-- Require necessary modules
local api = vim.api
local http = require("socket.http")
local ltn12 = require("ltn12")
local cjson = require("cjson")
local M = {}

-- Helper function to send HTTP POST requests to the R server
local function make_request(request, port)
    local url = "http://127.0.0.1:" .. port
    local request_body = cjson.encode(request)
    local response_body = {}
    
    -- Perform the HTTP request
    local res, status_code, headers = http.request{
        url = url,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#request_body)
        },
        source = ltn12.source.string(request_body),
        sink = ltn12.sink.table(response_body)
    }
    
    -- Check if the request was successful
    if res ~= 1 or status_code ~= 200 then
        print("HTTP request failed with status code:", status_code)
        return nil
    end
    
    -- Concatenate the response body
    local response_str = table.concat(response_body)
    
    -- Decode the JSON response
    local success, response_json = pcall(cjson.decode, response_str)
    if not success then
        print("Error decoding JSON response:", response_json)
        return nil
    end
    
    return response_json
end

-- Function to display DataFrame as a neatly formatted table
local function display_dataframe(df_json)
    -- Decode the DataFrame JSON (assuming 'rows' orientation)
    local success, data = pcall(cjson.decode, df_json)
    if not success then
        print("Error decoding DataFrame JSON:", data)
        return
    end

    if type(data) ~= 'table' then
        print("Unexpected DataFrame format.")
        return
    end

    if #data == 0 then
        print("DataFrame is empty.")
        return
    end

    -- Extract headers from the first record
    local headers = {}
    for key, _ in pairs(data[1]) do
        table.insert(headers, key)
    end

    -- Calculate column widths
    local col_widths = {}
    for _, header in ipairs(headers) do
        col_widths[header] = #header
    end

    for _, row in ipairs(data) do
        for _, header in ipairs(headers) do
            local cell = tostring(row[header] or "")
            if #cell > col_widths[header] then
                col_widths[header] = #cell
            end
        end
    end

    -- Function to pad strings with spaces
    local function pad(str, width)
        return str .. string.rep(" ", width - #str)
    end

    -- Build the table lines
    local lines = {}

    -- Header row
    local header_line = "| "
    for _, header in ipairs(headers) do
        header_line = header_line .. pad(header, col_widths[header]) .. " | "
    end
    table.insert(lines, header_line)

    -- Separator
    local sep_line = "|"
    for _, header in ipairs(headers) do
        sep_line = sep_line .. string.rep("-", col_widths[header] + 2) .. "|"
    end
    table.insert(lines, sep_line)

    -- Data rows
    for _, row in ipairs(data) do
        local row_line = "| "
        for _, header in ipairs(headers) do
            local cell = tostring(row[header] or "")
            row_line = row_line .. pad(cell, col_widths[header]) .. " | "
        end
        table.insert(lines, row_line)
    end

        -- Create buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    -- Calculate window dimensions
    local total_width = 1  -- Starting width (for initial pipe)
    for _, width in pairs(col_widths) do
        total_width = total_width + width + 3  -- Add column width + 3 (for " | ")
    end

    -- Calculate window size (with maximum limits)
    local max_width = math.floor(vim.o.columns * 0.9)
    local max_height = math.floor(vim.o.lines * 0.8)
    local win_width = math.min(total_width, max_width)
    local win_height = math.min(#lines, max_height)

    -- Calculate position
    local row = math.floor((vim.o.lines - win_height) / 2)
    local col = math.floor((vim.o.columns - win_width) / 2)

    -- Window options
    local win_opts = {
        relative = 'editor',
        width = win_width,
        height = win_height,
        row = row,
        col = col,
        style = 'minimal',
        border = 'rounded',
        title = ' DataFrame ',
        title_pos = 'center',
        zindex = 50
    }

    -- Create window
    local win = vim.api.nvim_open_win(buf, true, win_opts)

    -- Set buffer options
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
    vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')

    -- Set window options
    vim.api.nvim_win_set_option(win, 'wrap', false)  -- Disable line wrapping
    vim.api.nvim_win_set_option(win, 'cursorline', true)
    vim.api.nvim_win_set_option(win, 'signcolumn', 'no')

    -- Keymaps
    local opts = { noremap = true, silent = true, buffer = buf }
    
    -- Close window
    vim.keymap.set('n', 'q', function() vim.api.nvim_win_close(win, true) end, opts)
    vim.keymap.set('n', '<Esc>', function() vim.api.nvim_win_close(win, true) end, opts)
    
    vim.keymap.set('n', 'h', '10zh', opts)  -- Scroll faster
    vim.keymap.set('n', 'l', '10zl', opts)

    -- Auto-close on buffer leave
    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = buf,
        callback = function()
            if vim.api.nvim_win_is_valid(win) then
                vim.api.nvim_win_close(win, true)
            end
        end,
    })

    -- Handle window resize
    vim.api.nvim_create_autocmd("VimResized", {
        buffer = buf,
        callback = function()
            if vim.api.nvim_win_is_valid(win) then
                local new_max_width = math.floor(vim.o.columns * 0.9)
                local new_max_height = math.floor(vim.o.lines * 0.8)
                local new_win_width = math.min(total_width, new_max_width)
                local new_win_height = math.min(#lines, new_max_height)
                
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

-- Function to display info string as plain text
local function display_info(info_str)
    -- Split the info string into lines for better formatting
    local content_lines = {}
    for line in info_str:gmatch("([^\n]*)\n?") do
        table.insert(content_lines, line)
    end

    -- Open a floating preview window with the plain text
    vim.lsp.util.open_floating_preview(content_lines, "markdown", { border = "rounded" })
end

-- Main handler to process received data based on type
local function HandleReceivedData(response)
    if response.status ~= "success" then
        print("Error from server:", response.message)
        return
    end

    local data_type = response.type
    local data = response.data

    if data_type == "dataframe" then
        display_dataframe(data)
    elseif data_type == "info" then
        display_info(data)
    else
        print("Unknown data type received:", data_type)
    end
end

-- Function to inspect a specific R object by name
function M.inspect(obj_name, port)
    local request = { type = "inspect", obj = obj_name }
    local response = make_request(request, port)
    if response then
        HandleReceivedData(response)
    else
        print("Failed to inspect object:", obj_name)
    end
end

-- Function to query and display all global environment variables
function M.query_global(port)
    local request = { type = "query_global" }
    local response = make_request(request, port)

    if response and response.status == "success" and response.global_env then
        local content_lines = {"**Global Environment Variables:**"}
        for _, var in ipairs(response.global_env) do
            table.insert(content_lines, string.format("**Name:** %s", var.name))
            table.insert(content_lines, string.format("**Type:** %s", var.type))
            table.insert(content_lines, string.format("**Class:** %s", table.concat(var.class, ", ")))
            table.insert(content_lines, string.format("**Length:** %s", tostring(var.length)))
            table.insert(content_lines, "**Detail:**")
            
            -- Handle both table and string types for 'structure'
            if type(var.structure) == "table" then
                for _, line in ipairs(var.structure) do
                    table.insert(content_lines, "    " .. line)
                end
            elseif type(var.structure) == "string" then
                for line in var.structure:gmatch("([^\n]*)\n?") do
                    table.insert(content_lines, "    " .. line)
                end
            end
            table.insert(content_lines, "------------------------------")
        end

        -- Open a floating preview window with the global variables information
        vim.lsp.util.open_floating_preview(content_lines, "markdown", { border = "rounded" })
    else
        print("Error in R server response:", response and response.message or "Unknown error")
    end
end

return M
