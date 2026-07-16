vim.pack.add {
  'https://github.com/akinsho/flutter-tools.nvim',
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/stevearc/dressing.nvim',
}

require('flutter-tools').setup {}
-- Note: flutter-tools automatically handles dartls LSP setup
-- Tree-sitter dart parser will auto-install when opening .dart files
