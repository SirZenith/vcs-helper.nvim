local systems = require "vcs-helper.systems"

local M = {}

local function show_status()
    local records = systems.parse_status()
    vim.pretty_print(records)
end

function M.init()
    vim.api.nvim_create_user_command("Status", show_status, {
        desc = "show status of current repository."
    })
end

return M
