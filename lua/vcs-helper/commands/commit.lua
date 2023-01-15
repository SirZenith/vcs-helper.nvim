local systems = require "vcs-helper.systems"
local panelpal = require "panelpal"
local selection_panel = require "panelpal.panels.selection_panel"

local SelectionPanel = selection_panel.SelectionPanel

local CONFIRM_SELECTIOIN = "Confirm"

local M = {}

M.records = {}

local function show_diff_info(index)
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
end

local function on_confirm_selection(files)
    if #files == 0 then
        vim.notify("no file chosen.")
        return
    end

    local prompt = "Are you sure you want to commit chosen file(s)?"
    local ok = panelpal.ask_for_confirmation(prompt)
    if not ok then return end

    local msg = vim.fn.input("Commit message: ") or ""
    local white_st, white_ed = msg:find("%s+")
    if msg == "" or (white_st == 1 and white_ed == #msg) then
        vim.notify("empty message, commit abort.")
        return
    end

    local err = systems.commit(files, msg)
    if err then
        vim.notify(err)
    end
end

---@param self SelectionPanel
---@param index integer
local function on_select_commit_item(self, index)
    local len = #self.options
    if index < len then
        show_diff_info(index)
    else
        local files = {}
        for i in pairs(self.selected) do
            local r = M.records[i]
            files[#files + 1] = r and r.path
        end

        on_confirm_selection(files)
    end
end

---@param self SelectionPanel
---@param index integer
local function check_commit_item_selection(self, index)
    local option = self.options[index]
    return option and option ~= ""
end

local commit_panel = SelectionPanel:new {
    name = "vcs-commit",
    height = 15,
    multi_selection = true,
    on_select_callback = on_select_commit_item,
    selection_checker = check_commit_item_selection,
}

function M.update_status()
    local records = systems.parse_status()
    M.records = records

    local options = {}
    for i = 1, #records do
        local r = records[i]
        options[#options + 1] = r.local_status .. " " .. r.path
    end

    for _ = 1, 2 do
        options[#options + 1] = ""
    end
    options[#options + 1] = CONFIRM_SELECTIOIN

    commit_panel.options = options
end

function M.open_commit_panel(in_new_tab)
    if in_new_tab then
        vim.cmd "tabnew"
    end

    commit_panel:clear_selectioin()
    commit_panel:show()
end

function M.show_commit()
    M.update_status()
    M.open_commit_panel(true)
end

function M.init()
    vim.api.nvim_create_user_command("VcsCommit", M.show_commit, {
        desc = "show current status, choose file for commit.",
    })
end

return M
