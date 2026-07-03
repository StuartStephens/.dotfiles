vim.pack.add {
  'https://github.com/NickvanDyke/opencode.nvim',
  'https://github.com/folke/snacks.nvim',
}

require('snacks').setup {
  input = {},
  picker = {},
  terminal = { enabled = true },
  notifier = { top_down = false },
}

do
    local function pick_open_port()
      local tcp = vim.uv.new_tcp()
      if not tcp then
        return 4096
      end

      local bind_result = tcp:bind('127.0.0.1', 0)
      if bind_result ~= 0 and bind_result ~= true then
        tcp:close()
        return 4096
      end

      local sock = tcp:getsockname()
      tcp:close()
      if not sock or type(sock.port) ~= 'number' then
        return 4096
      end
      return sock.port
    end

    local opencode_port = pick_open_port()
    local opencode_cmd = string.format('opencode --port %d', opencode_port)
    local horizontal_terminal_opts = {
      split = 'below',
      height = math.max(12, math.floor(vim.o.lines * 0.35)),
    }

    -- ─── Status winbar ───────────────────────────────────────────────────────
    vim.api.nvim_set_hl(0, 'OpencodeWorking', { fg = '#4FA3FF', bold = true })
    vim.api.nvim_set_hl(0, 'OpencodeDone',    { fg = '#22C55E', bold = true })
    vim.api.nvim_set_hl(0, 'OpencodeError',   { fg = '#EF4444', bold = true })
    vim.api.nvim_set_hl(0, 'OpencodeWaiting', { fg = '#F59E0B', bold = true })
    vim.api.nvim_set_hl(0, 'OpencodeIdle',    { fg = '#888888' })

    local oc_status = nil  ---@type string?
    local oc_title  = nil  ---@type string?
    local oc_bufs   = {}   ---@type table<integer, true>

    local function is_default_oc_title(title)
      return title:match('^New session %- %d') ~= nil
        or title:match('^Child session %- %d') ~= nil
    end

    local function update_winbar()
      local icon, hl
      if oc_status == 'busy' then
        icon, hl = '●', 'OpencodeWorking'
      elseif oc_status == 'idle' then
        icon, hl = '✓', 'OpencodeDone'
      elseif oc_status == 'error' then
        icon, hl = '✗', 'OpencodeError'
      elseif oc_status == 'waiting' then
        icon, hl = '⏸', 'OpencodeWaiting'
      else
        icon, hl = '○', 'OpencodeIdle'
      end
      local label = (oc_title and oc_title ~= '') and oc_title or '…'
      local winbar = '%#' .. hl .. '# ' .. icon .. ' %#Normal#OC: ' .. label
      for bufnr in pairs(oc_bufs) do
        if vim.api.nvim_buf_is_valid(bufnr) then
          for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
            vim.api.nvim_set_option_value('winbar', winbar, { win = win })
          end
        else
          oc_bufs[bufnr] = nil
        end
      end
    end
    -- ─────────────────────────────────────────────────────────────────────────

    local function run_opencode_terminal_action(action, label)
      local ok, err = pcall(action)
      if ok then
        return
      end

      local message = tostring(err)
      if message:find('E444', 1, true) then
        vim.cmd 'new'
        local retried_ok, retried_err = pcall(action)
        if retried_ok then
          return
        end
        vim.notify(string.format('%s failed after retry: %s', label, retried_err), vim.log.levels.ERROR, { title = 'opencode.nvim' })
        return
      end

      vim.notify(string.format('%s failed: %s', label, message), vim.log.levels.ERROR, { title = 'opencode.nvim' })
    end

    local function toggle_opencode_terminal(opts, label)
      run_opencode_terminal_action(function()
        require('opencode.terminal').toggle(opencode_cmd, opts)
      end, label)
    end

    vim.g.opencode_opts = {
      server = {
        port = opencode_port,
        start = function()
          run_opencode_terminal_action(function()
            require('opencode.terminal').open(opencode_cmd)
          end, 'OpenCode terminal start')
        end,
        stop = function()
          run_opencode_terminal_action(function()
            require('opencode.terminal').close()
          end, 'OpenCode terminal stop')
        end,
        toggle = function()
          toggle_opencode_terminal(nil, 'OpenCode terminal toggle')
        end,
      },
    }

    -- Required for `vim.g.opencode_opts.auto_reload`
    vim.opt.autoread = true

    local scroll_group = vim.api.nvim_create_augroup('OpencodeTerminalScroll', { clear = true })
    vim.api.nvim_create_autocmd('TermOpen', {
      group = scroll_group,
      callback = function(args)
        local terminal_name = vim.api.nvim_buf_get_name(args.buf)
        if not terminal_name:find('opencode', 1, true) then
          return
        end

        -- Track this buffer for winbar updates
        oc_bufs[args.buf] = true
        vim.api.nvim_create_autocmd('BufDelete', {
          buffer = args.buf,
          once = true,
          callback = function() oc_bufs[args.buf] = nil end,
        })
        update_winbar()

        local function tmap(keys, command, desc)
          vim.keymap.set('t', keys, function()
            require('opencode').command(command)
          end, { buffer = args.buf, silent = true, desc = desc })
        end

        tmap('<C-M-u>', 'session.half.page.up', 'Messages half page up')
        tmap('<C-M-d>', 'session.half.page.down', 'Messages half page down')
        tmap('<M-u>', 'session.half.page.up', 'Messages half page up')
        tmap('<M-d>', 'session.half.page.down', 'Messages half page down')
        tmap('<M-k>', 'session.half.page.up', 'Messages half page up')
        tmap('<M-j>', 'session.half.page.down', 'Messages half page down')
        tmap('<PageUp>', 'session.page.up', 'Messages page up')
        tmap('<PageDown>', 'session.page.down', 'Messages page down')
      end,
    })

    -- Recommended/example keymaps
    vim.keymap.set({ 'n', 'x' }, '<leader>oa', function()
      require('opencode').ask('@this: ', { submit = true })
    end, { desc = 'Ask about this' })

    vim.keymap.set({ 'n', 'x' }, '<leader>os', function()
      require('opencode').select()
    end, { desc = 'Select prompt' })

    vim.keymap.set({ 'n', 'x' }, '<leader>o+', function()
      require('opencode').prompt '@this'
    end, { desc = 'Add this' })

    vim.keymap.set('n', '<leader>ot', function()
      require('opencode').toggle()
    end, { desc = 'Toggle embedded vertical' })

    vim.keymap.set('n', '<leader>oT', function()
      toggle_opencode_terminal(horizontal_terminal_opts, 'OpenCode terminal horizontal toggle')
    end, { desc = 'Toggle embedded horizontal' })

    vim.keymap.set('n', '<leader>oc', function()
      require('opencode').command()
    end, { desc = 'Select command' })

    vim.keymap.set('n', '<leader>on', function()
      require('opencode').command 'session.new'
    end, { desc = 'New session' })

    vim.keymap.set('n', '<leader>oi', function()
      require('opencode').command 'session.interrupt'
    end, { desc = 'Interrupt session' })

    vim.keymap.set('n', '<leader>oA', function()
      require('opencode').command 'agent.cycle'
    end, { desc = 'Cycle selected agent' })

    vim.keymap.set('n', '<S-C-u>', function()
      require('opencode').command 'session.half.page.up'
    end, { desc = 'Messages half page up' })

    vim.keymap.set('n', '<S-C-d>', function()
      require('opencode').command 'session.half.page.down'
    end, { desc = 'Messages half page down' })

    -- ─── opencode event → winbar ─────────────────────────────────────────────
    local oc_event_group = vim.api.nvim_create_augroup('OpencodeWinbar', { clear = true })

    vim.api.nvim_create_autocmd('User', {
      group = oc_event_group,
      pattern = { 'OpencodeEvent:session.status', 'OpencodeEvent:server.connected' },
      callback = function(args)
        local event = args.data and args.data.event
        if not event then return end
        if event.type == 'server.connected' then
          oc_status = 'idle'
        else
          local st = event.properties and event.properties.status and event.properties.status.type
          if st == 'busy' then
            oc_status = 'busy'
          elseif st == 'idle' then
            oc_status = 'idle'
          elseif st == 'error' then
            oc_status = 'error'
          end
        end
        update_winbar()
      end,
    })

    vim.api.nvim_create_autocmd('User', {
      group = oc_event_group,
      pattern = { 'OpencodeEvent:permission.asked', 'OpencodeEvent:question.asked' },
      callback = function()
        oc_status = 'waiting'
        update_winbar()
      end,
    })

    vim.api.nvim_create_autocmd('User', {
      group = oc_event_group,
      pattern = { 'OpencodeEvent:permission.replied', 'OpencodeEvent:question.replied', 'OpencodeEvent:question.rejected' },
      callback = function()
        -- Revert waiting state; the next session.status will set the real state
        if oc_status == 'waiting' then
          oc_status = 'busy'
          update_winbar()
        end
      end,
    })

    vim.api.nvim_create_autocmd('User', {
      group = oc_event_group,
      pattern = { 'OpencodeEvent:session.updated', 'OpencodeEvent:session.created' },
      callback = function(args)
        local event = args.data and args.data.event
        if not event then return end
        local title = event.properties and event.properties.info and event.properties.info.title
        if title and not is_default_oc_title(title) then
          oc_title = title
          update_winbar()
        end
      end,
    })

    vim.api.nvim_create_autocmd('User', {
      group = oc_event_group,
      pattern = { 'OpencodeEvent:server.instance.disposed' },
      callback = function()
        oc_status = nil
        oc_title  = nil
        update_winbar()
      end,
    })
    -- ─────────────────────────────────────────────────────────────────────────
end
