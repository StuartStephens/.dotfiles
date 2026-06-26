local opts = { noremap = true, silent = true }
local keymap = vim.keymap.set

-- Exit file
keymap('n', '<leader>bd', ':bd<CR>', { desc = '[B]uffer [D]elete' })

-- Vertical Movement with centering
keymap('n', '<C-d>', '<C-d>zz', opts)
keymap('n', '<C-u>', '<C-u>zz', opts)
keymap('n', '}', '}zz', opts)
keymap('n', '{', '{zz', opts)
keymap('n', 'n', 'nzzzv', opts)
keymap('n', 'N', 'Nzzzv', opts)

-- Resize with arrows
keymap('n', '<C-Up>', ':resize -2<CR>', opts)
keymap('n', '<C-Down>', ':resize +2<CR>', opts)
keymap('n', '<C-Left>', ':vertical resize -2<CR>', opts)
keymap('n', '<C-Right>', ':vertical resize +2<CR>', opts)

-- Navigate buffers
keymap('n', '<S-l>', ':bnext<CR>', opts)
keymap('n', '<S-h>', ':bprevious<CR>', opts)

-- Move text up and down
keymap('n', '<A-j>', ':m .+1<CR>==', opts)
keymap('n', '<A-k>', ':m .-2<CR>==', opts)
keymap('v', '<A-j>', ":m '>+1<CR>gv=gv", opts)
keymap('v', '<A-k>', ":m '<-2<CR>gv=gv", opts)
keymap('x', '<A-j>', ":m '>+1<CR>gv=gv", opts)
keymap('x', '<A-k>', ":m '<-2<CR>gv=gv", opts)

-- Insert --
-- Press jk fast to exit insert mode
keymap('i', 'jk', '<ESC>', opts)
keymap('i', 'kj', '<ESC>', opts)

-- Visual --
-- Press jk fast to exit visual mode
keymap('v', 'jk', '<ESC>', opts)
keymap('v', 'kj', '<ESC>', opts)

-- Stay in indent mode
keymap('v', '<', '<gv^', opts)
keymap('v', '>', '>gv^', opts)

-- Paste without yanking in visual mode
keymap('v', 'p', '"_dP', opts)

-- Visual Block --
-- Move text up and down
keymap('x', 'J', ":m '>+1<CR>gv=gv", opts)
keymap('x', 'K', ":m '<-2<CR>gv=gv", opts)

-- Quickfix Step File
keymap('n', '<M-n>', ':cnext<CR>', opts)
keymap('n', '<M-p>', ':cprev<CR>', opts)

-- Toggle diagnostics visibility
keymap('n', '<leader>td', function()
  local config = vim.diagnostic.config()
  if config.virtual_text == false and config.signs == false and config.underline == false then
    -- Diagnostics are currently disabled, enable them
    vim.diagnostic.config({
      virtual_text = true,
      signs = true,
      underline = true,
    })
  else
    -- Diagnostics are currently enabled, disable them
    vim.diagnostic.config({
      virtual_text = false,
      signs = false,
      underline = false,
    })
  end
end, { desc = '[T]oggle [D]iagnostics' })

-- Restart LSP
keymap('n', '<leader>lr', ':LspRestart<CR>', { desc = '[L]SP [R]estart' })
