local selection_panel = require "panelpal.panels.selection_panel"

local systems = require "vcs-helper.systems"
local path_util = require "vcs-helper.util.path"

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
    local err = diff.show(info.path)
    if err then
        vim.notify(err)
    end

    M.cur_selection = index
end)

---@return integer? bufnr
function M.get_buffer()
    return status_panel:get_buffer()
end

function M.show()
    systems.parse_status(nil, function(err, records)
        if err or not records then
            vim.notify(err or "failed to get status", vim.log.levels.WARN)
            return
        end

        M.records = records

        local options = {}
        for i = 1, #records do
            local r = records[i]
            local path = path_util.path_simplify(r.path)
            options[#options + 1] = r.local_status .. " " .. path
        end

        status_panel.options = options
        status_panel:clear_selectioin()
        status_panel:update_options()
    end)
end

-- -----------------------------------------------------------------------------

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

-- -----------------------------------------------------------------------------

return M
