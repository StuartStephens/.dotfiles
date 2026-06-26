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
    local opencode_cmd = string.format('NODE_TLS_REJECT_UNAUTHORIZED=0 opencode --port %d', opencode_port)

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

    vim.g.opencode_opts = {
      server = {
        port = opencode_port,
        start = function()
          run_opencode_terminal_action(function()
            require('opencode.terminal').start(opencode_cmd)
          end, 'OpenCode terminal start')
        end,
        stop = function()
          run_opencode_terminal_action(function()
            require('opencode.terminal').stop()
          end, 'OpenCode terminal stop')
        end,
        toggle = function()
          run_opencode_terminal_action(function()
            require('opencode.terminal').toggle(opencode_cmd)
          end, 'OpenCode terminal toggle')
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
    end, { desc = 'Toggle embedded' })

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
end
