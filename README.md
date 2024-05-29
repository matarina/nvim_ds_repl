# nvim_ds_repl
### About **nvim_d(ata)s(cience)_repl** 
A quite simple newly created custom nvim REPL(Read–eval–print loop) plugin for data scientist supported R and Python languages.
Most code sending action pattern was inspired by Rstudio and Jupyter.
## Features
#### Sending semantic code block utilize Treesitter object.
#### Visual selections sending.
#### Sending whole buffer.
## Usage
for Lazy package manager: 
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
## TODO
#### 1> plot in line via x11 forward or kitty protocal
#### 2> Variable inspect panel
the plugin are highly based [nvim-python-repl](https://github.com/geg2102/nvim-python-repl)
