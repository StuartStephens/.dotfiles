vim.pack.add { 'https://github.com/iamcco/markdown-preview.nvim' }
vim.fn['mkdp#util#install']()
vim.keymap.set('n', '<leader>md', '<cmd>MarkdownPreview<cr>', { desc = 'Markdown Preview' })
