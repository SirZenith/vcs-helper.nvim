local panelpal = require "panelpal"
local selection_panel = require "panelpal.panels.selection_panel"

local systems = require "vcs-helper.systems"
local util = require "vcs-helper.util"
local path_util = require "vcs-helper.util.path"

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
        lines[#lines + 1] = "- " .. path_util.path_simplify(file)
    end

    util.do_async_steps {
        function(next_step)
            panelpal.ask_for_confirmation_with_popup(lines, next_step)
        end,
        function(next_step, ok)
            if not ok then
                vim.notify("commit canceled.")
            else
                vim.ui.input({ prompt = "Commit message: " }, next_step)
            end
        end,
        function(next_step, msg)
            if
                not msg
                or msg == ""
                or msg:match("%s+") == msg
            then
                vim.notify("empty message, commit abort.")
                return
            end

            local prompt = ("Your commit message is `%s`"):format(msg)
            local ok = panelpal.ask_for_confirmation(prompt)
            if not ok then
                vim.notify("commit abort.")
            else
                systems.commit(files, msg, next_step)
            end
        end,
        function(_, err)
            if err then
                vim.notify(err, vim.log.levels.WARN)
            else
                vim.notify("commit complete")
            end
        end,
    }
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
    systems.parse_status(nil, function(err, parsed_records)
        if err or not parsed_records then
            vim.notify(err or "failed to get status", vim.log.levels.WARN)
            return
        end
        local records = {}
        for i = 1, #parsed_records do
            local r = parsed_records[i]
            local local_status = r.local_status

            if local_status and local_status ~= " " then
                records[#records + 1] = r
            end
        end
        M.records = records

        local options = {}
        for i = 1, #records do
            local r = records[i]
            local path = path_util.path_simplify(r.path)
            options[#options + 1] = r.local_status .. " " .. path
        end

        for _ = 1, 2 do
            options[#options + 1] = ""
        end
        options[#options + 1] = CONFIRM_SELECTIOIN

        commit_panel.options = options
        commit_panel:clear_selectioin()
        commit_panel:update_options()
    end)
end

-- -----------------------------------------------------------------------------

return M
