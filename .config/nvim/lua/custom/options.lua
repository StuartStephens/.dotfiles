-- set termguicolors to enable highlight groups
vim.opt.termguicolors = true

-- Kickstart stuff?
vim.opt.guicursor = ''

vim.opt.nu = true
vim.opt.relativenumber = true

vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

vim.opt.smartindent = true

vim.opt.wrap = false

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv 'HOME' .. '/.vim/undodir'
vim.opt.undofile = true

vim.opt.hlsearch = false
vim.opt.incsearch = true

vim.opt.termguicolors = true

vim.opt.scrolloff = 12
vim.opt.signcolumn = 'yes'
vim.opt.isfname:append '@-@'

vim.opt.updatetime = 50

-- vim.opt.colorcolumn = '80'

vim.opt.title = true
vim.opt.titlestring = [[%{expand('%:t') == '' ? '[No Name]' : expand('%:t')}%{&modified ? ' [+]' : ''} - %{fnamemodify(getcwd(), ':t')}]]

local function set_wezterm_tab_title()
  if not os.getenv 'WEZTERM_PANE' or vim.fn.executable 'wezterm' ~= 1 then
    return
  end

  local filename = vim.fn.expand '%:t'
  if filename == '' then
    filename = '[No Name]'
  end

  local modified = vim.bo.modified and ' [+]' or ''
  local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
  local title = filename .. modified

  if cwd ~= '' then
    title = title .. ' - ' .. cwd
  end

  vim.system({ 'wezterm', 'cli', 'set-tab-title', title }, { text = true })
end

local wezterm_title_group = vim.api.nvim_create_augroup('custom-wezterm-tab-title', { clear = true })

vim.api.nvim_create_autocmd({ 'VimEnter', 'BufEnter', 'BufFilePost', 'BufModifiedSet', 'DirChanged' }, {
  group = wezterm_title_group,
  callback = set_wezterm_tab_title,
})

vim.api.nvim_create_autocmd('VimLeavePre', {
  group = wezterm_title_group,
  callback = function()
    if os.getenv 'WEZTERM_PANE' and vim.fn.executable 'wezterm' == 1 then
      vim.system({ 'wezterm', 'cli', 'set-tab-title', '' }, { text = true })
    end
  end,
})

-- Neorg settings --
vim.opt.foldmethod = 'indent'
vim.opt.foldlevelstart = 1
vim.opt.conceallevel = 1
vim.opt.concealcursor = 'nc'

-- Neovim config for inline hints
vim.lsp.inlay_hint.enable(true)
