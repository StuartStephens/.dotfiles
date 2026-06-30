vim.pack.add { 'https://github.com/tpope/vim-fugitive' }
vim.keymap.set('n', '<leader>G', '<cmd>vertical G<cr>', { desc = '[G]it Fugitive' })
vim.keymap.set('n', '<leader>g', '<cmd>belowright split | G<cr>', { desc = '[g]it Fugitive horizontal' })
