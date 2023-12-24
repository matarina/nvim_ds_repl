# nvim_ds_repl
### About **nvim_d(ata)s(cience)_repl** 
A quite simple newly created custom nvim REPL plugin for data scientist supported R and Python languages.
Most code sending action are inspired by Rstudio and Jupyter.
## Features
#### Sending semantic code block utilize Treesitter object.
#### Visual selections sending support.
#### Send whole buffer.
## Usage
for lazy 
```
return {
    "petrichorma/nvim_ds_repl",
    dependencies = "nvim-treesitter",
    ft = {"python", "lua"}, 
    config = function()
        require("nvim_ds_repl").setup({
            vsplit = true,
        })
    end
    }

```
Keymaps
defult Keymaps:
```
--nvim_ds_repl plugins config--
vim.api.nvim_create_autocmd({"BufEnter", "BufWinEnter"}, {
  pattern = {"*.py","*.R",},
  callback = function()
	vim.keymap.set("n", '<CR>', function() 
        require('nvim_ds_repl').send_statement_definition() 
    end, {noremap = true})
	vim.keymap.set("v", '<CR>', function() 
        require('nvim_ds_repl').send_visual_to_repl() 
    end, {noremap = true})
	vim.keymap.set("n", '<leader>fa', function() 
        require('nvim_ds_repl').send_buffer_to_repl() 
    end, {noremap = true})
end})

```
the plugin are highly based [nvim-python-repl](https://github.com/geg2102/nvim-python-repl)
