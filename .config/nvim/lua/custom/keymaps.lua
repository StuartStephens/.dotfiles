local opts = { noremap = true, silent = true }
local keymap = vim.keymap.set

-- ============================================================
-- AUTO-CENTERING ON VERTICAL MOTIONS
-- ============================================================
-- When enabled, every vertical motion is followed by `zz`,
-- keeping the cursor line vertically centered at all times.
--
-- Toggle : <leader>tz  (on by default)
-- Manual : zz          (always works regardless of toggle state)

local auto_center = {
  enabled = true,

  -- Only activate for files longer than this many lines.
  -- Files at or below this count are left untouched.
  min_lines = 50,

  -- Filetypes where auto-centering is never applied.
  -- Key = filetype string, value = true.
  -- Uncomment examples below to enable:
  excluded_ft = {
    -- gitcommit = true,
    -- help      = true,
    -- oil       = true,
    -- qf        = true,
  },
}

local function should_center()
  if not auto_center.enabled then return false end
  if auto_center.excluded_ft[vim.bo.filetype] then return false end
  if vim.api.nvim_buf_line_count(0) <= auto_center.min_lines then return false end
  return true
end

--- Expr keymap helper — appends `zz` to a motion string when centering is active.
--- Use for motions that don't need count awareness (G, gg, %, }, {, etc.)
local function zc(motion)
  return function()
    if should_center() then return motion .. 'zz' end
    return motion
  end
end

--- Count-aware variant for j / k.
local function zc_count(motion)
  return function()
    local cnt = vim.v.count
    local key = cnt > 0 and (cnt .. motion) or motion
    if should_center() then return key .. 'zz' end
    return key
  end
end

local expr_opts = { noremap = true, silent = true, expr = true }

-- Exit file
keymap('n', '<leader>bd', ':bd<CR>', { desc = '[B]uffer [D]elete' })

-- Line motions
keymap('n', 'j', zc_count 'j', expr_opts)
keymap('n', 'k', zc_count 'k', expr_opts)

-- File-level jumps
keymap('n', 'G', zc 'G', expr_opts)
keymap('n', 'gg', zc 'gg', expr_opts)

-- Paragraph motions
keymap('n', '}', zc '}', expr_opts)
keymap('n', '{', zc '{', expr_opts)

-- Section motions (language/treesitter dependent — no-op if not bound)
keymap('n', '[[', zc '[[', expr_opts)
keymap('n', ']]', zc ']]', expr_opts)

-- Match jump (may feel sudden in HTML/XML — add to excluded_ft if needed)
keymap('n', '%', zc '%', expr_opts)

-- Search motions — preserve zv (open folds) alongside centering
keymap('n', 'n', function()
  if should_center() then return 'nzzzv' end
  return 'n'
end, expr_opts)
keymap('n', 'N', function()
  if should_center() then return 'Nzzzv' end
  return 'N'
end, expr_opts)

-- Word-under-cursor search
keymap('n', '*', zc '*', expr_opts)
keymap('n', '#', zc '#', expr_opts)

-- Half/full page scrolls
keymap('n', '<C-d>', zc '<C-d>', expr_opts)
keymap('n', '<C-u>', zc '<C-u>', expr_opts)
keymap('n', '<C-f>', zc '<C-f>', expr_opts)
keymap('n', '<C-b>', zc '<C-b>', expr_opts)

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

-- Toggle auto-centering
keymap('n', '<leader>tz', function()
  auto_center.enabled = not auto_center.enabled
  local state = auto_center.enabled and 'enabled' or 'disabled'
  vim.notify('Auto-center ' .. state, vim.log.levels.INFO)
end, { noremap = true, silent = true, desc = '[T]oggle [Z]enter' })

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

-- SSH agent — load key into the systemd user agent from inside nvim.
-- The socket path is always /run/user/<uid>/ssh-agent.socket (matches rc.xsh).
vim.api.nvim_create_user_command('SshLogin', function()
  local uid = vim.trim(vim.fn.system 'id -u')
  vim.env.SSH_AUTH_SOCK = '/run/user/' .. uid .. '/ssh-agent.socket'
  local out = vim.trim(vim.fn.system 'ssh-add -t 8h ~/.ssh/id_ed25519 2>&1')
  vim.notify(out, vim.log.levels.INFO)
end, { desc = 'Load SSH key into agent' })
