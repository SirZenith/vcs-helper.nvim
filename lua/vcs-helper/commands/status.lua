local systems = require "vcs-helper.systems"
local selection_panel = require "panelpal.selection_panel"

local SelectionPanel = selection_panel.SelectionPanel

local M = {}

M.records = {}
M.cur_selection = 0

---@param _ SelectionPanel
---@param index integer
local function on_select_status_item(_, index)
    local diff = require "vcs-helper.commands.diff"

    local info = M.records[index]
    local path = vim.fn.getcwd() .. "/" .. info.path
    local abs_path = systems.to_abs_path(path)
    if not abs_path then
        return
    end

    local records, abs_filename = diff.update_diff(abs_path)
    if not records then
        vim.notify("no diff info found for file: " .. path)
        return
    end

    diff.open_diff_panel(abs_filename, records, false)
    M.cur_selection = index
end

local status_panel = SelectionPanel:new {
    name = "vcs-status",
    height = 10,
    on_select_callback = on_select_status_item,
}

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

function M.update_status()
    local records = systems.parse_status()
    M.records = records

    local options = {}
    for i = 1, #records do
        local r = records[i]
        options[#options+1] = r.local_status .. " " .. r.path
    end

    status_panel.options = options
end

---@param in_new_tab boolean
function M.open_status_panel(in_new_tab)
    if in_new_tab then
        vim.cmd "tabnew"
    end

    status_panel:show()
end

function M.show_status()
    M.update_status()
    M.open_status_panel(true)
end

function M.init()
    vim.api.nvim_create_user_command("VcsStatus", M.show_status, {
        desc = "show status of current repository."
    })

    vim.api.nvim_create_user_command("VcsStatusNext", M.select_next, {
        desc = "select next item in status list."
    })

    vim.api.nvim_create_user_command("VcsStatusPrev", M.select_prev, {
        desc = "select previous item in status list."
    })
end

return M
