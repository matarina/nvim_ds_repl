# About nvim_ds_repl

Introducing nvim_ds_repl, a custom nvim (Neovim) plugin designed as a REPL (Read–Eval–Print Loop) specifically tailored for data scientists. Optimized for Python and R, it theoretically supports any language that has an available Jupyter kernel. Inspired by the functionality of Rstudio and Jupyter, the plugin provides a seamless code-sending experience.

## Demo Video
https://youtu.be/G24Dg-npRVE
## Features

#### Intelligent Code Block Transmission: Utilizes Treesitter to send semantic code blocks.
#### Flexible Code Sending: Choose to send visual selections or entire buffer contents with ease.
#### Environment Inspection: Inspect variables and view current variables in the environment.


### Development

As of May 2024, nvim_ds_repl has been rebuilt using pynvim, leading to rapid feature evolution. Suggestions and feedback are highly appreciated and can be sent to maxiaowei2020@foxmail.com.

## Usage

For those using the Lazy package manager, include:
```
return {
    "petrichorma/nvim_ds_repl",
    requires = "nvim-treesitter",
}
```

## Default Keymaps Configuration

Here's how to set up default keymaps for the nvim_ds_repl plugin:

-- Configuration for nvim_ds_repl plugin --
```
vim.api.nvim_create_autocmd({"BufEnter", "BufWinEnter"}, {
  pattern = {"*.py", "*.R"},
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
    vim.api.nvim_set_keymap('n', '<leader>pp', "<cmd>lua require('nvim_ds_repl').get_envs()<CR>", {noremap = true, silent = true})
    vim.api.nvim_set_keymap('n', '<leader>pj', "<cmd>lua require('nvim_ds_repl').inspect()<CR>", {noremap = true, silent = true})
  end
})
```


### To-Do

    Inline Plotting: Enable inline plotting through X11 forwarding, possibly via the Kitty terminal (or similar protocols).
    The plugin is based on [nvim-python-repl](https://github.com/geg2102/nvim-python-repl).

