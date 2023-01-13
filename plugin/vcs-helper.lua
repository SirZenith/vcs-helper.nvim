if vim.g.loaded_vcs_helper then
    return
end
vim.g.loaded_vcs_helper = true

-- setup modules
require("vcs-helper").setup()
