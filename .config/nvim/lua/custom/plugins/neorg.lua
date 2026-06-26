vim.pack.add {
  { src = 'https://github.com/nvim-neorg/neorg', version = vim.version.range '*' },
  'https://github.com/nvim-neorg/lua-utils.nvim',
  'https://github.com/pysan3/pathlib.nvim',
  'https://github.com/nvim-neotest/nvim-nio',
  'https://github.com/MunifTanjim/nui.nvim',
}

local notes_workspace = vim.env.NEORG_HOME or '~/Neorg'
local neorg_ready = false

local function find_parser_path(lang)
  local runtime_paths = vim.api.nvim_get_runtime_file('parser/' .. lang .. '.so', true)
  if #runtime_paths > 0 then
    return runtime_paths[1]
  end

  local data = vim.fn.stdpath 'data'
  local candidates = {
    vim.fs.joinpath(data, 'site', 'parser', lang .. '.so'),
    vim.fs.joinpath(data, 'site', 'pack', 'core', 'opt', 'nvim-treesitter', 'parser', lang .. '.so'),
    vim.fs.joinpath(data, 'lazy', 'nvim-treesitter', 'parser', lang .. '.so'),
  }

  for _, path in ipairs(candidates) do
    if vim.uv.fs_stat(path) then
      return path
    end
  end
end

local function ensure_neorg_parsers()
  local missing = {}

  for _, lang in ipairs { 'norg', 'norg_meta' } do
    local parser_path = find_parser_path(lang)
    if not parser_path then
      table.insert(missing, lang)
    else
      local ok, err = pcall(vim.treesitter.language.add, lang, { path = parser_path })
      if not ok then
        vim.notify(string.format('Failed to register %s parser: %s', lang, tostring(err)), vim.log.levels.ERROR)
        return false
      end
    end
  end

  if #missing > 0 then
    vim.notify('Neorg parser files are missing: ' .. table.concat(missing, ', '), vim.log.levels.ERROR)
    return false
  end

  return true
end

for _, workspace in ipairs { notes_workspace} do
  local expanded = vim.fn.expand(workspace)
  if vim.fn.isdirectory(expanded) == 0 then
    vim.fn.mkdir(expanded, 'p')
  end
end

local function setup_neorg()
  if neorg_ready then
    return true
  end

  if not ensure_neorg_parsers() then
    return false
  end

  local ok, neorg = pcall(require, 'neorg')
  if not ok then
    vim.notify('Failed to load Neorg: ' .. tostring(neorg), vim.log.levels.ERROR)
    return false
  end

  neorg.setup {
    load = {
      ['core.defaults'] = {},
      ['core.concealer'] = {},
      ['core.integrations.treesitter'] = {
        config = {
          configure_parsers = false,
          warn_missing_parsers = false,
        },
      },
      ['core.esupports.indent'] = {
        config = {
          format_on_escape = false,
        },
      },
      ['core.dirman'] = {
        config = {
          workspaces = {
            notes = notes_workspace,
          },
          default_workspace = 'notes',
          index = 'index.norg',
        },
      },
      ['core.qol.todo_items'] = {},
      ['core.export'] = {},
      ['core.export.markdown'] = {
        config = {
          extensions = {
            'todo-items-basic',
            'todo-items-pending',
            'todo-items-extended',
            'definition-lists',
            'metadata',
            'mathematics',
          },
        },
      },
    },
  }

  if vim.fn.exists ':NeorgWorkspaceAdd' == 0 then
    vim.api.nvim_create_user_command('NeorgWorkspaceAdd', function(opts)
      if #opts.fargs ~= 2 then
        vim.notify('Usage: NeorgWorkspaceAdd <name> <path>', vim.log.levels.ERROR)
        return
      end

      local name = opts.fargs[1]
      local path = vim.fn.expand(opts.fargs[2])
      local dirman = require('neorg').modules.get_module 'core.dirman'

      if not dirman then
        vim.notify('Neorg dirman module is unavailable', vim.log.levels.ERROR)
        return
      end

      local added = dirman.add_workspace(name, path)
      if not added then
        vim.notify(string.format("Neorg workspace '%s' already exists", name), vim.log.levels.WARN)
      end

      dirman.open_workspace(name)
    end, {
      desc = 'Add and open a Neorg workspace',
      nargs = '+',
      complete = 'dir',
    })
  end

  if vim.fn.exists ':NeorgExportToMarkdown' == 0 then
    vim.api.nvim_create_user_command('NeorgExportToMarkdown', function(opts)
      local destination = opts.args
      if destination == '' then
        destination = vim.fn.expand '%:p:r'
        destination = destination .. '.md'
      else
        destination = vim.fn.expand(destination)
      end

      local escaped = vim.fn.fnameescape(destination)
      vim.cmd('Neorg export to-file ' .. escaped .. ' markdown')
      vim.notify('Neorg exported to ' .. destination)
    end, {
      desc = 'Export current .norg file to markdown',
      nargs = '?',
      complete = 'file',
    })
  end

  neorg_ready = true
  return true
end

local function call_neorg_command(command)
  return function()
    if setup_neorg() then
      vim.cmd(command)
    end
  end
end

local function feed_neorg_plug(plug)
  return function()
    if not setup_neorg() then
      return
    end

    local keys = vim.api.nvim_replace_termcodes(plug, true, false, true)
    vim.api.nvim_feedkeys(keys, 'm', false)
  end
end

local function cycle_or_create_todo()
  if not setup_neorg() then
    return
  end

  local line = vim.api.nvim_get_current_line()
  if not line:match '^%s*[%-%~%*%>%$%^]+%s' then
    local indent, content = line:match '^(%s*)(.*)$'
    local replacement = indent .. '- '

    if content ~= '' then
      replacement = replacement .. content
    end

    vim.api.nvim_set_current_line(replacement)
  end

  local keys = vim.api.nvim_replace_termcodes('<Plug>(neorg.qol.todo-items.todo.task-cycle)', true, false, true)
  vim.api.nvim_feedkeys(keys, 'm', false)
end

setup_neorg()

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'norg',
  callback = function()
    setup_neorg()

    -- Neorg-local readability settings (additive, no global overrides)
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true
    vim.opt_local.textwidth = 0
    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = 'nc'
  end,
})

vim.keymap.set('n', '<leader>ni', call_neorg_command 'Neorg index', { desc = 'Neorg index' })
vim.keymap.set('n', '<leader>nn', feed_neorg_plug '<Plug>(neorg.dirman.new-note)', { desc = 'Neorg new note' })
vim.keymap.set('n', '<leader>nw', call_neorg_command 'Neorg workspace notes', { desc = 'Neorg notes workspace' })
vim.keymap.set('n', '<leader>nt', cycle_or_create_todo, { desc = 'Neorg cycle/create todo' })
vim.keymap.set('n', '<leader>ne', call_neorg_command 'NeorgExportToMarkdown', { desc = 'Neorg export markdown' })
vim.keymap.set('n', '<leader>nr', call_neorg_command 'Neorg return', { desc = 'Neorg return' })
