local M = {}
local repl = require("nvim_ds_repl.nvim_ds_repl")


function M.send_statement_definition()
    repl.send_statement_definition(M)
end

function M.send_visual_to_repl()
    vim.cmd('execute "normal \\<ESC>"')
    repl.send_visual_to_repl(M)
end

function M.send_buffer_to_repl()
    repl.send_buffer_to_repl(M)
end

function M.get_envs()
    repl.get_envs(M)
end

function M.inspect()
    repl.inspect(M)
end

return M
