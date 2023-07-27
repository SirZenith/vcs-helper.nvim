local systems = require "vcs-helper.systems"
local panelpal = require "panelpal"
local selection_panel = require "panelpal.panels.selection_panel"

local SelectionPanel = selection_panel.SelectionPanel

local CONFIRM_SELECTIOIN = "Confirm"

local M = {}

M.records = {}
M.index = 0

local function on_confirm_selection(files)
    if #files == 0 then
        vim.notify("no file chosen.")
        return
    end

    local lines = {
        "Are you sure you want to commit chosen file(s)?",
        "",
    }
    for _, file in ipairs(files) do
        lines[#lines + 1] = "- " .. systems.path_simplify(file)
    end

    panelpal.ask_for_confirmation_with_popup(lines, function(ok)
        if not ok then
            vim.notify("commit canceled.")
            return
        end

        local msg = vim.fn.input("Commit message: ") or ""
        if msg == "" or msg:match("%s+") == msg then
            vim.notify("empty message, commit abort.")
            return
        end

        ok = panelpal.ask_for_confirmation(("Your commit message is `%s`"):format(msg))
        if not ok then
            vim.notify("commit abort.")
            return
        end

        local err = systems.commit(files, msg)
        if err then
            vim.notify(err)
        end
    end)
end

-- -----------------------------------------------------------------------------

local commit_panel = SelectionPanel:new {
    name = "vcs-commit",
    height = 15,
    multi_selection = true,
}

commit_panel:set_on_select(function(self, index)
    local len = #self.options
    -- the last item of options, is `Confirm`
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
        local local_status = r.local_status

        if local_status and local_status ~= " " then
            local path = systems.path_simplify(r.path)
            options[#options + 1] = local_status .. " " .. path
        end
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
