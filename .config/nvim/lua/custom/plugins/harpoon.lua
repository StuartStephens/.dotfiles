vim.pack.add {
  'https://github.com/ThePrimeagen/harpoon',
  'https://github.com/nvim-lua/plenary.nvim',
}

require('harpoon').setup {}
local mark = require 'harpoon.mark'
local ui = require 'harpoon.ui'

vim.keymap.set('n', '<leader>pa', mark.add_file, { desc = 'Har[p]oon [A]dd' })
vim.keymap.set('n', '<leader>pm', ui.toggle_quick_menu, { desc = 'Har[p]oon [M]enu' })
vim.keymap.set('n', '<C-e>', ui.toggle_quick_menu, { desc = 'Harpoon menu' })

vim.keymap.set('n', '<C-y>', function()
  ui.nav_file(1)
end)
vim.keymap.set('n', '<C-t>', function()
  ui.nav_file(2)
end)
vim.keymap.set('n', '<C-m>', function()
  ui.nav_file(3)
end)
vim.keymap.set('n', '<C-s>', function()
  ui.nav_file(4)
end)
