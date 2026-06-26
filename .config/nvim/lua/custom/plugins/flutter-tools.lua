vim.pack.add {
  'https://github.com/akinsho/flutter-tools.nvim',
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/stevearc/dressing.nvim',
}

require('flutter-tools').setup {}
vim.lsp.document_color.enable()
vim.lsp.config('dartls', {})
vim.lsp.enable 'dartls'

if vim.fn.executable 'tree-sitter' == 1 then
  require('nvim-treesitter').install 'dart'
end
