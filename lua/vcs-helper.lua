local systems = require "vcs-helper.systems"
local buf_op = require "vcs-helper.buf_op"

local DiffType = systems.DiffType

local diff_panel_namespace = "vschelper.diff"
local diff_panel_old_name = diff_panel_namespace .. ".old"
local diff_panel_new_name = diff_panel_namespace .. ".new"

local DIFF_FILE_TYPE = "vcs-helper-diff"

local M = {}

M.augroup_id = nil
M.buf_old = nil
M.buf_new = nil

---@param filename string
---@return string[]?
---@return string? err
local function read_file_lines(filename)
    local lines = {}
    local file, err = io.open(filename, "r")
    if not file then
        return nil, err
    end

    for line in file:lines() do
        lines[#lines + 1] = line
    end

    return lines
end

---@param lines string[]
---@param st integer
---@param ed integer
---@param buf_old integer
---@param buf_new integer
local function read_common_lines(lines, st, ed, buf_old, buf_new)
    if ed < st then return end

    local buffer = {}
    for i = st, ed do
        buffer[#buffer + 1] = lines[i]
    end
    buf_op.append_to_buf_with_highlight(buf_old, DiffType.common, buffer)
    buf_op.append_to_buf_with_highlight(buf_new, DiffType.common, buffer)
end

---@param filename string
---@param records DiffRecord[]
---@param buf_old integer
---@param buf_new integer
local function write_diff_record_to_buf(filename, records, buf_old, buf_new)
    vim.bo[buf_old].modifiable = true
    vim.bo[buf_new].modifiable = true

    vim.api.nvim_buf_set_lines(buf_old, 0, -1, true, {})
    vim.api.nvim_buf_set_lines(buf_new, 0, -1, true, {})

    local lines, err = read_file_lines(filename)
    if not lines then
        vim.notify(err)
        return
    end

    local line_input_index = 1
    for _, record in ipairs(records) do
        local linenumber = record.line

        read_common_lines(lines, line_input_index, linenumber - 1, buf_old, buf_new)

        local buffer_new = record.new
        local buffer_old = record.old
        local difftype = record.type
        buf_op.append_to_buf_with_highlight(buf_old, difftype, buffer_old)
        buf_op.append_to_buf_with_highlight(buf_new, difftype, buffer_new)

        local offset = difftype ~= DiffType.delete and #buffer_new or 0
        line_input_index = linenumber + offset
    end

    read_common_lines(lines, line_input_index, #lines, buf_old, buf_new)

    vim.bo[buf_old].modifiable = false
    vim.bo[buf_new].modifiable = false
end

---@return integer? buf_old
---@return integer? buf_new
local function open_diff_panel()
    local buf_old, win_old = buf_op.find_or_create_buf_with_name(diff_panel_old_name, false, true)
    local buf_new, win_new = buf_op.find_or_create_buf_with_name(diff_panel_new_name, false, true)
    if not (buf_old and buf_new) then
        return nil, nil
    end

    M.buf_old, M.buf_new = buf_old, buf_new

    for _, buf in ipairs { buf_old, buf_new } do
        local opt = vim.bo[buf]
        opt.buftype = "nofile"
        opt.filetype = DIFF_FILE_TYPE
    end

    if not (win_old and win_new) then
        vim.cmd "tabnew"
        win_old = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(win_old, buf_old)

        vim.cmd "rightbelow vsplit"
        win_new = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(win_new, buf_new)
    end

    return buf_old, buf_new
end

local function get_diff(data)
    local filename = data.args
    if not filename then return end

    local abs_filename = vim.fs.normalize(systems.to_abs_path(filename))

    systems.parse_diff(abs_filename)
    local records = systems.get_diff_record(abs_filename)
    if not records then
        vim.notify("no diff info found for file: " .. filename)
        return
    end

    local buf_old, buf_new = open_diff_panel()
    if not (buf_old and buf_new) then
        vim.notify("failed to create buf for diff content.")
        return
    end

    local err = write_diff_record_to_buf(abs_filename, records, buf_old, buf_new)
    if err then vim.notify(err) end
    -- vim.api.nvim_buf_set_lines(buf_old, 0, -1, true, vim.split(vim.inspect(records), "\n"))
    -- vim.api.nvim_buf_set_lines(buf_new, 0, -1, true, systems.get_diff_line(filename))
end

-- -----------------------------------------------------------------------------

local function sync_diff_compare_cursor()
    local buf_old, buf_new = M.buf_old, M.buf_new
    if not (buf_old and buf_new) then return end

    local cur_win = vim.api.nvim_get_current_win()
    local pos = vim.api.nvim_win_get_cursor(cur_win)

    for _, buf in ipairs { buf_old, buf_new } do
        local win = buf_op.find_win_with_buf(buf)
        if win then
            vim.api.nvim_win_set_cursor(win, pos)
        end
    end
end

local function setup_autocmd_for_buffer()
    for _, buf in ipairs { M.buf_old, M.buf_new } do
        vim.api.nvim_create_autocmd("CursorMoved", {
            group = M.augroup_id,
            buffer = buf,
            callback = function()
                sync_diff_compare_cursor()
            end
        })
    end
end

-- -----------------------------------------------------------------------------

function M.setup()
    systems.init()

    vim.api.nvim_create_user_command("Diff", get_diff, {
        desc = "parse git diff in current workspace",
        nargs = 1,
        complete = "file",
    })

    local augroup_id = vim.api.nvim_create_augroup("vcs-helper", { clear = true })
    M.augroup_id = augroup_id

    vim.api.nvim_create_autocmd("FileType", {
        group = augroup_id,
        pattern = DIFF_FILE_TYPE,
        callback = function()
            setup_autocmd_for_buffer()
        end,
    })
end

return M
