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

vim.opt.wrap = true
vim.opt.linebreak = true

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
local function fugitive_branch()
  if vim.fn.exists '*FugitiveHead' ~= 1 then
    return ''
  end

  local ok, branch = pcall(vim.fn.FugitiveHead)
  if not ok or type(branch) ~= 'string' then
    return ''
  end

  return branch
end

local function current_title()
  local bufname = vim.api.nvim_buf_get_name(0)
  local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
  local title = ''

  if bufname:match '^fugitive://' then
    local branch = fugitive_branch()
    local branch_prefix = branch ~= '' and ('[' .. branch .. '] ') or ''
    local git_path = bufname:match '//[^/]+/(.+)$'

    if vim.bo.filetype == 'fugitive' then
      title = branch_prefix .. 'Git Status'
    elseif vim.bo.filetype == 'git' then
      title = branch_prefix .. 'Git Log'
    elseif git_path and git_path ~= '' then
      local filename = vim.fn.fnamemodify(git_path, ':t')
      if filename == '' then
        title = branch_prefix .. 'Git'
      else
        title = branch_prefix .. filename .. ' (git)'
      end
    else
      title = branch_prefix .. 'Git'
    end
  else
    local filename = vim.fn.expand '%:t'
    if filename == '' then
      filename = '[No Name]'
    end

    local modified = vim.bo.modified and ' [+]' or ''
    title = filename .. modified
  end

  if cwd ~= '' then
    title = title .. ' - ' .. cwd
  end

  return title
end

local function update_titles()
  local title = current_title()
  vim.opt.titlestring = title:gsub('%%', '%%%%')

  if os.getenv 'WEZTERM_PANE' and vim.fn.executable 'wezterm' == 1 then
    vim.system({ 'wezterm', 'cli', 'set-tab-title', title }, { text = true })
  end
end

local wezterm_title_group = vim.api.nvim_create_augroup('custom-wezterm-tab-title', { clear = true })

vim.api.nvim_create_autocmd({ 'VimEnter', 'BufEnter', 'BufFilePost', 'BufModifiedSet', 'DirChanged', 'FileType' }, {
  group = wezterm_title_group,
  callback = update_titles,
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
