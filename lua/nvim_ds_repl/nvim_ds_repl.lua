local api = vim.api
local ts = vim.treesitter
local parsers = require("nvim-treesitter.parsers")

M = {}

M.term = {
    opened = 0,
    winid = nil,
    bufid = nil,
    chanid = nil
}

local visual_selection_range = function()
    local _, start_row, start_col, _ = unpack(vim.fn.getpos("'<"))
    local _, end_row, end_col, _ = unpack(vim.fn.getpos("'>"))
    if start_row < end_row or (start_row == end_row and start_col <= end_col) then
        return start_row - 1, start_col - 1, end_row - 1, end_col
    else
        return end_row - 1, end_col - 1, start_row - 1, start_col
    end
end

local term_open = function(filetype, config)
    orig_win = api.nvim_get_current_win()
    if M.term.chanid ~= nil then
        return
    end
    if config.vsplit then
        api.nvim_command("bo 60vne")
    else
        api.nvim_command("split")
    end
    local buf = api.nvim_get_current_buf()
    local win = api.nvim_get_current_win()
    api.nvim_win_set_buf(win, buf)
    local choice = ""
    if filetype == "python" then
        choice = config.spawn_command.python
    elseif filetype == "r" then
        choice = config.spawn_command.r
    end
    local chan =
        vim.fn.termopen(
        choice,
        {
            on_exit = function()
                M.term.chanid = nil
                M.term.opened = 0
                M.term.winid = nil
                M.term.bufid = nil
            end
        }
    )
    M.term.chanid = chan
    vim.bo.filetype = "term"
    M.term.opened = 1
    M.term.winid = win
    M.term.bufid = buf
    api.nvim_set_current_win(orig_win)
end

local construct_message_from_selection = function(start_row, start_col, end_row, end_col)
    local bufnr = api.nvim_get_current_buf()
    if start_row ~= end_row then
        local lines = api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
        lines[1] = string.sub(lines[1], start_col + 1)
        if #lines == end_row - start_row then
            lines[#lines] = string.sub(lines[#lines], 1, end_col)
        end
        return lines
    else
        local line = api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1]
        return line and {string.sub(line, start_col + 1, end_col)} or {}
    end
end

local construct_message_from_buffer = function()
    local bufnr = api.nvim_get_current_buf()
    local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return lines
end

local semantic_message_construct = function()
    local line = api.nvim_get_current_line()
    local current_pos = api.nvim_win_get_cursor(0)
    local total_lines = api.nvim_buf_line_count(0)

    if line:match("^%s*$") then
        while current_pos[1] < total_lines do
            api.nvim_win_set_cursor(0, {current_pos[1] + 1, 0})
            current_pos = api.nvim_win_get_cursor(0)
            line = api.nvim_get_current_line()
            if not line:match("^%s*$") then
                break
            end
        end
    end
    local function inspect_nodes()
        local parser = parsers.get_parser()

        local tree = parser:parse()[1]
        local root = tree:root()
        local unique_types = {}

        for child in root:iter_children() do
            local type = child:type()
            if not unique_types[type] then
                unique_types[type] = true
            end
            unique_types["comment"] = true
        end

        return unique_types
    end

    local function type_exists(unique_types, type_to_check)
        return unique_types[type_to_check] ~= nil
    end

    local unique_child_types = inspect_nodes()

    local status, result =
        pcall(
        function()
            local node = vim.treesitter.get_node()
            while true do
                if type_exists(unique_child_types, node:type()) then
                    break
                else
                    node = node:parent()
                end
            end
            local text = vim.treesitter.get_node_text(node, 0)
            local start_row, start_col, end_row, end_col = vim.treesitter.get_node_range(node)
            return {text, end_row}
        end
    )

    if status then
        return result
    end
end

local MoveCursorToNextLine = function(end_row)
    local current_line, current_col = unpack(api.nvim_win_get_cursor(0))
    local total_lines = api.nvim_buf_line_count(0)

    if current_line + 1 < total_lines then
        if end_row ~= nil then
            api.nvim_win_set_cursor(0, {end_row + 2, 0})
        else
            api.nvim_win_set_cursor(0, {current_line + 1, 0})
        end
    end
end

local send_message = function(filetype, message, config)
    if M.term.opened == 0 then
        term_open(filetype, config)
        vim.wait(500)
    end
    if filetype == "python" then
        message = api.nvim_replace_termcodes("<esc>[200~" .. message .. "<cr><esc>[201~", true, false, true)
    elseif filetype == "r" then
        message = api.nvim_replace_termcodes("<esc>[200~" .. message .. "<esc>[201~", true, false, true)
    end
    message = api.nvim_replace_termcodes(message .. "<cr>", true, false, true)
    if M.term.chanid ~= nil then
        api.nvim_chan_send(M.term.chanid, message)
        api.nvim_win_set_cursor(M.term.winid, {api.nvim_buf_line_count(M.term.bufid), 0})
    end
end

M.send_statement_definition = function(config)
    local filetype = vim.bo.filetype
    local result = semantic_message_construct()
    if result == nil then
        print("Input empty string.")
    else
        local message, end_row = unpack(result)
        send_message(filetype, message, config)
        MoveCursorToNextLine(end_row)
    end
end

M.send_visual_to_repl = function(config)
    local filetype = vim.bo.filetype
    local start_row, start_col, end_row, end_col = visual_selection_range()
    local message = construct_message_from_selection(start_row, start_col, end_row, end_col)
    local concat_message = table.concat(message, "\n")
    send_message(filetype, concat_message, config)
    MoveCursorToNextLine()
end

M.send_buffer_to_repl = function(config)
    local filetype = vim.bo.filetype
    local message = construct_message_from_buffer()
    local concat_message = table.concat(message, "\n")
    send_message(filetype, concat_message, config)
end

return M
