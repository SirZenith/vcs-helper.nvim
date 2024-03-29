local api = vim.api
local tabpage = require "panelpal.panels.tabpage"
local systems = require "vcs-helper.systems"
local commit = require "vcs-helper.commands.commit"
local diff = require "vcs-helper.commands.diff"
local status = require "vcs-helper.commands.status"
local str_util = require "vcs-helper.util.str"

local TabPage = tabpage.TabPage

local M = {}

---@param self TabPage
local function next_status_item(self)
    local buf_bottom_panel = self.bufnr_bottom_panel
    local buf_status = status.get_buffer()
    if buf_bottom_panel == buf_status then
        status.select_next()
    end
end

---@param self TabPage
local function prev_status_item(self)
    local buf_bottom_panel = self.bufnr_bottom_panel
    local buf_status = status.get_buffer()
    if buf_bottom_panel == buf_status then
        status.select_prev()
    end
end

M.tabpage = TabPage:new {
    keymap = {
        toggle_bottom_panel = "<leader><backspace>",
        ["<A-j>"] = next_status_item,
        ["<A-k>"] = prev_status_item,
    }
}

local tp = M.tabpage

function M.show_diff(args)
    local filename = str_util.read_quoted_string(args.fargs[1] or "")
    if filename == "" then
        M.show_status()
        return
    end

    local buf_old, buf_new = diff.get_buffers()
    if not (buf_old and buf_new) then
        vim.notify("failed to create diff buffers.")
        return
    end

    tp:show()
    tp:vsplit_into(2)
    tp:set_vsplit_buf(1, buf_old)
    tp:set_vsplit_buf(2, buf_new)

    diff.reset()
    local err = diff.show(filename)
    if err then
        vim.notify(err)
    end
end

function M.show_status()
    local buf_old, buf_new = diff.get_buffers()
    if not (buf_old and buf_new) then
        vim.notify("failed to create diff buffers.")
        return
    end

    local buf = status.get_buffer()
    if not buf then
        vim.notify("failed to create status buffer.")
        return
    end

    tp:show()
    tp:vsplit_into(2)
    tp:set_vsplit_buf(1, buf_old)
    tp:set_vsplit_buf(2, buf_new)

    local win = tp:show_bottom_panel(buf)
    if win then
        api.nvim_set_current_win(win)
    end

    diff.reset()
    status.show()
end

function M.show_commit()
    local buf_old, buf_new = diff.get_buffers()
    if not (buf_old and buf_new) then
        vim.notify("failed to create diff buffers.")
        return
    end

    local buf = commit.get_buffer()
    if not buf then
        vim.notify("failed to create status buffer.")
        return
    end

    tp:show()
    tp:vsplit_into(2)
    tp:set_vsplit_buf(1, buf_old)
    tp:set_vsplit_buf(2, buf_new)

    local win = tp:show_bottom_panel(buf)
    if win then
        api.nvim_set_current_win(win)
    end

    diff.reset()
    commit.show()
end

function M.init()
    local create_cmd = api.nvim_create_user_command

    -- Diff
    create_cmd("VcsDiff", M.show_diff, {
        desc = "parse git diff in current workspace",
        nargs = "?",
        complete = "file",
    })

    -- Status
    create_cmd("VcsStatus", M.show_status, {
        desc = "show status of current repository."
    })

    create_cmd("VcsStatusNext", status.select_next, {
        desc = "select next item in status list."
    })

    create_cmd("VcsStatusPrev", status.select_prev, {
        desc = "select previous item in status list."
    })

    -- Commit
    create_cmd("VcsCommit", M.show_commit, {
        desc = "show current status, choose file for commit.",
    })
end

return M
