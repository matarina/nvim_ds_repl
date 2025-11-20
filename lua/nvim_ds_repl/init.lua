local api, ts = vim.api, vim.treesitter
local uv = vim.loop
local parsers = require 'nvim-treesitter.parsers'
local r_query = require("nvim_ds_repl.r_query")
local python_query = require("nvim_ds_repl.python_query")

local M = {}
local M = {
    term = {opened = 0, winid = 0, bufid = 0, chanid = 0},
}





-- Function to get an available port
local function get_available_port()
    local server = assert(uv.new_tcp())
    assert(server:bind("127.0.0.1", 0))
    local ok, addr = pcall(server.getsockname, server)
    server:close()
    assert(ok and addr and addr.port, "Failed to acquire available port")
    return addr.port
end

-- Get two available port numbers, ensuring they are not equal
M.port1 = get_available_port()
M.port2 = get_available_port()

while M.port2 == M.port1 do
    M.port2 = get_available_port()
end



local function get_plugin_path()
    local runtime_paths = vim.api.nvim_list_runtime_paths()
    for _, path in ipairs(runtime_paths) do
        if path:match("nvim_ds_repl$") then
            return path
        end
    end
end





local function open_floating_window(content_lines)
    local width = math.floor(vim.o.columns * 0.8)
    local height = math.min(#content_lines, math.floor(vim.o.lines * 0.8))
    local row, col = math.floor((vim.o.lines - height) / 2), math.floor((vim.o.columns - width) / 2)
    local bufid = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(bufid, 0, -1, false, content_lines)
    api.nvim_open_win(bufid, true, {
        relative = 'editor', width = width, height = height, row = row, col = col,
        style = 'minimal', border = 'rounded'
    })
end

local function get_python_cmd()
    local function format_py(bin)
        return string.format("%s -m IPython", vim.fn.shellescape(bin))
    end

    if vim.g.nvim_ds_repl_python_cmd and #vim.g.nvim_ds_repl_python_cmd > 0 then
        return vim.g.nvim_ds_repl_python_cmd
    end

    if vim.g.python3_host_prog and vim.fn.executable(vim.g.python3_host_prog) == 1 then
        return format_py(vim.g.python3_host_prog)
    end

    local py = vim.fn.exepath("python3")
    if py ~= nil and #py > 0 then
        return format_py(py)
    end

    return "ipython"
end

function M.open_terminal()
    local filetype, bufid = vim.bo.filetype, vim.api.nvim_create_buf(false, true)
    vim.cmd("botright 60vsplit")
    vim.api.nvim_win_set_buf(0, bufid)
    local winid = vim.api.nvim_get_current_win()

    vim.loop.os_setenv("PORT_R", M.port1)
    vim.loop.os_setenv("PORT_HGD", M.port2)
    local term_cmd = ({
        r = "radian -q --no-restore --no-save --profile " .. get_plugin_path() .. "/R/server_init.R ",
        python = get_python_cmd() .. " -i " .. get_plugin_path() .. "/python/server_init.py " .. M.port1
    })[filetype]


    if term_cmd then
        local chanid = vim.fn.termopen(term_cmd)
        M.term = {opened = 1, winid = winid, bufid = bufid, chanid = chanid}
    else
        print("Filetype not supported")
    end
    vim.opt_local.number = false


end


local function send_message(filetype, message)
    if M.term.opened == 0 then
        M.open_terminal()
        vim.wait(500)
    end

    local prefix = api.nvim_replace_termcodes("<esc>[200~", true, false, true)
    local suffix = api.nvim_replace_termcodes("<esc>[201~", true, false, true)

    if filetype == "r" then
        api.nvim_chan_send(M.term.chanid, prefix .. message .. suffix .. "\n")
    elseif filetype == "python" then
        local line_count = select(2, message:gsub("\n", "\n")) + 1
        if line_count > 1 then
            api.nvim_chan_send(M.term.chanid, prefix .. message .. suffix .. "\n\n")
        else
            api.nvim_chan_send(M.term.chanid, prefix .. message .. suffix .. "\n")
        end
    else
        print("Filetype not supported")
        return
    end

    vim.api.nvim_win_set_cursor(M.term.winid, {vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(M.term.winid)), 0})
end

local function move_cursor_to_next_line(end_row)
    local target_line = end_row + 2
    if target_line <= vim.api.nvim_buf_line_count(0) then
        vim.api.nvim_win_set_cursor(0, {target_line, 0})
    end
end




local function handle_cursor_move()
    local row = api.nvim_win_get_cursor(0)[1]
    local comment_char = vim.bo.filetype == "cpp" and "//" or "#"
    while row <= api.nvim_buf_line_count(0) do
        local line = api.nvim_buf_get_lines(0, row - 1, row, false)[1]
        local col = line:find("%S")

        -- Skip empty lines or comment lines
        if not col or line:sub(col, col + (#comment_char - 1)) == comment_char then
            row = row + 1
            local success, err =
                pcall(
                function()
                    api.nvim_win_set_cursor(0, {row, 0})
                end
            )
        else
            local cursor_pos = api.nvim_win_get_cursor(0)
            local current_col = cursor_pos[2] + 1

            -- If cursor is already on a non-whitespace character, do nothing
            local char_under_cursor = line:sub(current_col, current_col)
            if not char_under_cursor:match("%s") then
                break
            end

            -- Find nearest non-whitespace characters backward and forward
            local backward_pos, forward_pos
            for i = current_col - 1, 1, -1 do
                if not line:sub(i, i):match("%s") then
                    backward_pos = i
                    break
                end
            end

            for i = current_col + 1, #line do
                if not line:sub(i, i):match("%s") then
                    forward_pos = i
                    break
                end
            end

            -- Calculate distances and move cursor
            local backward_dist = backward_pos and (current_col - backward_pos) or math.huge
            local forward_dist = forward_pos and (forward_pos - current_col) or math.huge

            if backward_dist < forward_dist then
                api.nvim_win_set_cursor(0, {row, backward_pos - 1})
            elseif forward_dist <= backward_dist then
                api.nvim_win_set_cursor(0, {row, forward_pos - 1})
            end

            break
        end
    end
end




function M.send_statement_definition()
    handle_cursor_move()
    local parser = parsers.get_parser(0)
    local root = parser:parse()[1]:root()
    local node = vim.treesitter.get_node()

    local current_winid = vim.api.nvim_get_current_win()

    local function find_and_return_node()
        local function immediate_child(node)
            for child in root:iter_children() do
                if child:id() == node:id() then
                    return true
                end
            end
            return false
        end

        while node and not immediate_child(node) do
            node = node:parent()
        end

        return node, current_winid
    end

    local node, winid = find_and_return_node()
    if not node then
        print("No valid node found!")
        return
    end

    local ok, msg = pcall(vim.treesitter.get_node_text, node, 0)

    if not ok then
        print("Error getting node text!")
        return
    end

    local end_row = select(3, node:range())
    if msg then
        send_message(vim.bo.filetype, msg)
    end
    vim.api.nvim_set_current_win(winid)
    move_cursor_to_next_line(end_row)
end




local function get_visual_selection()
    local start_pos, end_pos = vim.fn.getpos("v"), vim.fn.getcurpos()
    local start_line, end_line, start_col, end_col = start_pos[2], end_pos[2], start_pos[3], end_pos[3]
    if start_line > end_line then
        start_line, end_line = end_line, start_line
        start_col, end_col = end_col, start_col
    end
    local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

    lines[1] = string.sub(lines[1], start_col, -1)
    if #lines == 1 then
        lines[#lines] = string.sub(lines[#lines], 1, end_col - start_col + 1)
    else
        lines[#lines] = string.sub(lines[#lines], 1, end_col)
    end

    return table.concat(lines, '\n'), end_line
end

function M.send_visual_to_repl()
    local current_winid = vim.api.nvim_get_current_win()
    local msg, end_row = get_visual_selection()
    send_message(vim.bo.filetype, msg)
    vim.api.nvim_set_current_win(current_winid)
    move_cursor_to_next_line(end_row)
    vim.api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
end


function M.inspect()
    node = vim.treesitter.get_node()
    obj  = ts.get_node_text(node, 0)
    if vim.bo.filetype == "r" then
        r_query.inspect(obj, M.port1)
    else
        python_query.inspect(obj, M.port1)
    end
end


return M
