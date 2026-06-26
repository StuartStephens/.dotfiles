vim.pack.add { 'https://github.com/stevearc/oil.nvim' }
require('oil').setup {
  view_options = {
    show_hidden = true,
  },
}

vim.keymap.set('n', '<leader>i', '<cmd>Oil<CR>', { desc = 'O[i]l' })
