# nvim_ds_repl
### About **nvim_d(ata)s(cience)_repl** 
A quite simple newly created custom nvim REPL plugin for data scientist supported R and Python languages.
Most code sending action are inspired by Rstudio and Jupyter.
## Features
Sending semantic code block utilize Treesitter object.
Visual selections sending support.
send whole buffer.
## Usage
for lazy 
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


the plugin are based nvim-python-repl
