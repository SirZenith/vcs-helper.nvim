local systems = require "vcs-helper.systems"
local panelpal = require "panelpal"
local selection_panel = require "panelpal.panels.selection_panel"

local SelectionPanel = selection_panel.SelectionPanel

local starts_with = systems.starts_with

local CONFIRM_SELECTIOIN = "Confirm"

local M = {}

M.records = {}
M.index = 0

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

-- -----------------------------------------------------------------------------

local commit_panel = SelectionPanel:new {
    name = "vcs-commit",
    height = 15,
    multi_selection = true,
}

commit_panel:set_on_select(function(self, index)
    local len = #self.options
    if index < len then
        local diff = require "vcs-helper.commands.diff"

        local info = M.records[index]
        local err = diff.show(info.path)
        if err then
            vim.notify(err)
        end
    else
        local files = {}
        for i in pairs(self.selected) do
            local r = M.records[i]
            files[#files + 1] = r and r.path
        end

        on_confirm_selection(files)
    end
end)

commit_panel:set_selection_checker(function(self, index)
    local option = self.options[index]
    return option and option ~= ""
end)

-- -----------------------------------------------------------------------------

---@return integer? bufnr
function M.get_buffer()
    return commit_panel:get_buffer()
end

function M.show()
    local records = systems.parse_status()
    M.records = records

    local options = {}
    for i = 1, #records do
        local r = records[i]
        local path = r.path
        local cwd = vim.fs.normalize(vim.fn.getcwd())
        if starts_with(path, cwd) then
            path = "." .. path:sub(#cwd + 1)
        end
        options[#options + 1] = r.local_status .. " " .. path
    end

    for _ = 1, 2 do
        options[#options + 1] = ""
    end
    options[#options + 1] = CONFIRM_SELECTIOIN

    commit_panel.options = options
    commit_panel:clear_selectioin()
    commit_panel:update_options()
end

-- -----------------------------------------------------------------------------

return M
