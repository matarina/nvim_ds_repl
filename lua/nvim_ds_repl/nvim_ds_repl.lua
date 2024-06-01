local api = vim.api
local ts = vim.treesitter
local parsers = require("nvim-treesitter.parsers")

local M = {}

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

local term_open = function(filetype)
    connection = vim.fn.StartKernel(filetype)
    local function init_term_state(win, buf, chan)
        M.term = { chanid = chan, opened = 1, winid = win, bufid = buf }
    end
    local function reset_term_state()
        M.term = { chanid = nil, opened = 0, winid = nil, bufid = nil }
    end
    if M.term and M.term.chanid ~= nil then
        return
    end
    local orig_win = api.nvim_get_current_win()
    api.nvim_command("bo 60vne")
    local buf = api.nvim_get_current_buf()
    local win = api.nvim_get_current_win()
    local interpreter = 'jupyter console --existing ' .. connection
    local chan = vim.fn.termopen(interpreter, { on_exit = reset_term_state })
    init_term_state(win, buf, chan)
    vim.bo[buf].filetype = "term"
    api.nvim_set_current_win(orig_win)
end
--
--     orig_win = api.nvim_get_current_win()
--     if M.term.chanid ~= nil then
--         return
--     end
--     api.nvim_command("bo 60vne")
--     local buf = api.nvim_get_current_buf()
--     local win = api.nvim_get_current_win()
--     api.nvim_win_set_buf(win, buf)
--     local choice = ""
--     if filetype == "python" then
--         choice = 'ipython'
--     elseif filetype == "r" then
--         choice = 'radian'
--     end
--     local chan =
--         vim.fn.termopen(
--         choice,
--         { on_exit = function()
--                 M.term.chanid = nil
--                 M.term.opened = 0
--                 M.term.winid = nil
--                 M.term.bufid = nil
--             end
--         }
--     )
--     M.term.chanid = chan
--     vim.bo.filetype = "term"
--     M.term.opened = 1
--     M.term.winid = win
--     M.term.bufid = buf
--     api.nvim_set_current_win(orig_win)
-- end

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
    local function is_direct_child_of_root(node)
        local parser = parsers.get_parser()

        local tree = parser:parse()[1]
        local root = tree:root()
        for child in root:iter_children() do
            if child:id() == node:id() then
                return true
            end
        end
        return false
        end

    local status, result =
        pcall(
        function()
            local node = vim.treesitter.get_node()
            while node do
                if is_direct_child_of_root(node) then
                   local text = vim.treesitter.get_node_text(node, 0)
                   local start_row, start_col, end_row, end_col = vim.treesitter.get_node_range(node)
                   return {text, end_row}
                end
                node = node:parent() -- Move to the parent node
            end
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
        term_open(filetype)
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

M.send_buffer_to_repl = function(config)
    local filetype = vim.bo.filetype
    local message = construct_message_from_buffer()
    local concat_message = table.concat(message, "\n")
    send_message(filetype, concat_message, config)
end


M.get_envs = function()
    env_vars = vim.fn.KernelVars()
  local markdown_lines = vim.lsp.util.convert_input_to_markdown_lines(env_vars)
  local markdown_lines = vim.lsp.util.trim_empty_lines(markdown_lines)
  local win_height = vim.api.nvim_win_get_height(0)
  local win_width = vim.api.nvim_win_get_width(0)
  local height = math.floor(win_height * 80 / 100)
  local width = math.floor(win_width * 80 / 100)
  vim.lsp.util.open_floating_preview(markdown_lines, "markdown",{height = height, width = width} )
end


M.inspect = function()
   local inspect = vim.fn.JupyterInspect()
   local out = ""

  if inspect.status ~= "ok" then
    out = inspect.status
  elseif inspect.found ~= true then
    out = "_No information from kernel_"
  else
    local sections = vim.split(inspect.data["text/plain"], "\x1b%[0;31m")
    for _, section in ipairs(sections) do
      section = section
        -- Strip ANSI Escape code: https://stackoverflow.com/a/55324681
        -- \x1b is the escape character
        -- %[%d+; is the ANSI escape code for a digit color
        :gsub("\x1b%[%d+;%d+;%d+;%d+;%d+m", "")
        :gsub("\x1b%[%d+;%d+;%d+;%d+m", "")
        :gsub("\x1b%[%d+;%d+;%d+m", "")
        :gsub("\x1b%[%d+;%d+m", "")
        :gsub("\x1b%[%d+m", "")
        :gsub("\x1b%[H", "\t")
        -- Groups: name, 0 or more new line, content till end
        -- TODO: Fix for non-python kernel
        :gsub("^(Call signature):(%s*)(.-)\n$", "```python\n%3 # %1\n```")
        :gsub("^(Init signature):(%s*)(.-)\n$", "```python\n%3 # %1\n```")
        :gsub("^(Signature):(%s*)(.-)\n$",      "```python\n%3 # %1\n```")
        :gsub("^(String form):(%s*)(.-)\n$",    "```python\n%3 # %1\n```")
        :gsub("^(Docstring):(%s*)(.-)$",        "\n---\n```rst\n%3\n```")
        :gsub("^(Class docstring):(%s*)(.-)$",  "\n---\n```rst\n%3\n```")
        :gsub("^(File):(%s*)(.-)\n$",           "*%1*: `%3`\n")
        :gsub("^(Type):(%s*)(.-)\n$",           "*%1*: %3\n")
        :gsub("^(Length):(%s*)(.-)\n$",         "*%1*: %3\n")
        :gsub("^(Subclasses):(%s*)(.-)\n$",     "*%1*: %3\n")
      if section:match("%S") ~= nil and section:match("%S") ~= "" then
        -- Only add non-empty section
        out = out .. section
      end
    end
  end
  local markdown_lines = vim.lsp.util.convert_input_to_markdown_lines(out)
  local markdown_lines = vim.lsp.util.trim_empty_lines(markdown_lines)
  local win_height = vim.api.nvim_win_get_height(0)
  local win_width = vim.api.nvim_win_get_width(0)
  local height = math.floor(win_height * 80 / 100)
  local width = math.floor(win_width * 80 / 100)
  vim.lsp.util.open_floating_preview(markdown_lines, "markdown",{height = height, width = width})
end

return M
