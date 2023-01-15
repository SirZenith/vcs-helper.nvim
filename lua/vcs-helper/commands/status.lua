local systems = require "vcs-helper.systems"
local selection_panel = require "panelpal.panels.selection_panel"

local SelectionPanel = selection_panel.SelectionPanel

local M = {}

M.records = {}
M.cur_selection = 0

local status_panel = SelectionPanel:new {
    name = "vcs-status",
    height = 10,
}

status_panel:set_on_select(function(_, index)
    local diff = require "vcs-helper.commands.diff"

    local info = M.records[index]
    local path = vim.fn.getcwd() .. "/" .. info.path
    local err = diff.show_diff(path)
    if err then
        vim.notify(err)
    end

    M.cur_selection = index
end)

function M.select_prev()
    local index = M.cur_selection - 1
    if index < 1 then
        return
    end

    status_panel:select(index)
end

function M.select_next()
    local index = M.cur_selection + 1
    if index > #M.records then
        return
    end

    status_panel:select(index)
end

---@return integer? bufnr
function M.get_buffer()
    return status_panel:get_buffer()
end

function M.show_status()
    local records = systems.parse_status()
    M.records = records

    local options = {}
    for i = 1, #records do
        local r = records[i]
        options[#options + 1] = r.local_status .. " " .. r.path
    end

    status_panel.options = options
    status_panel:update_options()
end

return M
