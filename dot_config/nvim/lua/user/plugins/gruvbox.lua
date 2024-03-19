return {
    "agrzeslak/gruvbox",
    branch = "new",
    priority = 1000,
    config = function()
        vim.g.gruvbox_italic = 1
        vim.g.gruvbox_italicize_comments = 0
        vim.g.gruvbox_bold = 1
        vim.g.gruvbox_sign_column = "bg0"
        vim.g.gruvbox_contrast_dark = "hard"
        vim.g.gruvbox_invert_selection = 0
        vim.g.gruvbox_color_column = "dark0"
        vim.g.gruvbox_cursorline = "dark0"
        vim.cmd([[colorscheme gruvbox]])
    end,
}
