local api = vim.api
local systems = require "vcs-helper.systems"
local panelpal = require "panelpal"

local DiffType = systems.DiffType
local UpdateMethod = panelpal.PanelContentUpdateMethod

local diff_panel_namespace = "vschelper.diff"
local diff_panel_old_name = diff_panel_namespace .. ".old"
local diff_panel_new_name = diff_panel_namespace .. ".new"

local DIFF_FILE_TYPE = "vcs-helper-diff"

local M = {}

M.augroup_id = api.nvim_create_augroup("vcs-helper.command.diff", { clear = true })
M.buf_old = nil
M.buf_new = nil
M.records = nil

-- -----------------------------------------------------------------------------

local function sync_diff_compare_cursor()
    local buf_old, buf_new = M.buf_old, M.buf_new
    if not (buf_old and buf_new) then return end

    local cur_win = api.nvim_get_current_win()
    local pos = api.nvim_win_get_cursor(cur_win)

    for _, buf in ipairs { buf_old, buf_new } do
        local win = panelpal.find_win_with_buf(buf, false)
        if win then
            api.nvim_win_set_cursor(win, pos)
        end
    end
end

---@param buf integer
local function setup_autocmd_for_buffer(buf)
    api.nvim_create_autocmd("CursorMoved", {
        group = M.augroup_id,
        buffer = buf,
        callback = function()
            sync_diff_compare_cursor()
        end
    })
end

---@param buf integer
local function setup_keymap_for_buffer(buf)
    local opts = { noremap = true, silent = true, buffer = buf }
    vim.keymap.set("n", "<C-j>", M.next_diff, opts)
    vim.keymap.set("n", "<C-k>", M.prev_diff, opts)
end

---@param key string
---@param bufname string
local function get_buffer(key, bufname)
    local buf = M[key]
    if not buf or not api.nvim_buf_is_valid(buf) then
        buf = api.nvim_create_buf(false, true)
        api.nvim_buf_set_name(buf, bufname)

        vim.bo[buf].filetype = DIFF_FILE_TYPE
        setup_autocmd_for_buffer(buf)
        setup_keymap_for_buffer(buf)

        M[key] = buf
    end

    return buf
end

-- -----------------------------------------------------------------------------

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
    panelpal.write_to_buf_with_highlight(buf_old, DiffType.common, buffer, UpdateMethod.append)
    panelpal.write_to_buf_with_highlight(buf_new, DiffType.common, buffer, UpdateMethod.append)
end

---@param filename string
---@param records DiffRecord[]
function M.write_diff_record_to_buf(filename, records)
    local buf_old, buf_new = M.get_buffers()
    if not (buf_old and buf_new) then
        return "failed to create diff buffer"
    end

    vim.bo[buf_old].readonly = false
    vim.bo[buf_new].readonly = false

    api.nvim_buf_set_lines(buf_old, 0, -1, true, {})
    api.nvim_buf_set_lines(buf_new, 0, -1, true, {})

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
        panelpal.write_to_buf_with_highlight(buf_old, difftype, buffer_old, UpdateMethod.append)
        panelpal.write_to_buf_with_highlight(buf_new, difftype, buffer_new, UpdateMethod.append)

        local offset = difftype ~= DiffType.delete and #buffer_new or 0
        line_input_index = linenumber + offset
    end

    read_common_lines(lines, line_input_index, #lines, buf_old, buf_new)

    vim.bo[buf_old].readonly = true
    vim.bo[buf_new].readonly = true
end

---@param filename string
---@return DiffRecord[]?
---@return string abs_filename
function M.update_diff(filename)
    local abs_filename = vim.fs.normalize(systems.to_abs_path(filename))
    systems.parse_diff(abs_filename)
    local records = systems.get_diff_record(abs_filename)
    return records, abs_filename
end

-- return bufnr of buffers used for diff content.
---@return integer? buf_old
---@return integer? buf_new
function M.get_buffers()
    local buf_old = get_buffer("buf_old", diff_panel_old_name)
    local buf_new = get_buffer("buf_new", diff_panel_new_name)

    if buf_old * buf_new == 0 then
        return nil, nil
    else
        return buf_old, buf_new
    end
end

-- write diff content to diff buffers.
---@return string? err
function M.show_diff(filename)
    if not filename then
        error("no file name given")
    end

    local buf_old, buf_new = M.get_buffers()
    if not (buf_old and buf_new) then
        return "failed to create diff buffer"
    end

    M.records = nil
    local records, abs_filename = M.update_diff(filename)
    if not records then
        return "no diff info found for file: " .. filename
    end
    M.records = records

    local err = M.write_diff_record_to_buf(abs_filename, records)
    return err
end

-- -----------------------------------------------------------------------------

function M.next_diff()
    local records = M.records
    if not records then return end

    local cur_buf = vim.fn.bufnr()

    local buf_old, buf_new = M.get_buffers()
    if not (buf_old and buf_new) then
        return
    elseif cur_buf ~= buf_old and cur_buf ~= buf_new then
        return
    elseif not (vim.bo[buf_old].readonly and vim.bo[buf_new].readonly) then
        -- if thease buffers' content has been modified by this plugin,
        -- they should have been set to readonly.
        -- If they are not, then they are probably have not content.
        return
    end

    local cur_line = api.nvim_win_get_cursor(0)[1]
    local line_number
    local extra = 0
    for i = 1, #records do
        local r = records[i]

        local linenr = r.line + extra
        if linenr > cur_line then
            line_number = linenr
            break
        end

        if r.type == DiffType.delete then
            extra = extra + #r.new
        end
    end

    if not line_number then
        vim.notify("no next diff.")
    else
        api.nvim_win_set_cursor(0, {line_number, 0})
    end
end

function M.prev_diff()
    local records = M.records
    if not records then return end

    local cur_buf = vim.fn.bufnr()

    local buf_old, buf_new = M.get_buffers()
    if not (buf_old and buf_new) then
        return
    elseif cur_buf ~= buf_old and cur_buf ~= buf_new then
        return
    elseif not (vim.bo[buf_old].readonly and vim.bo[buf_new].readonly) then
        -- if thease buffers' content has been modified by this plugin,
        -- they should have been set to readonly.
        -- If they are not, then they are probably have not content.
        return
    end

    local cur_line = api.nvim_win_get_cursor(0)[1]
    local line_number
    local extra = 0
    for i = 1, #records do
        local r = records[i]

        local linenr = r.line + extra
        if linenr < cur_line then
            line_number = linenr
        else
            break
        end

        if r.type == DiffType.delete then
            extra = extra + #r.new
        end
    end

    if not line_number then
        vim.notify("no previous diff.")
    else
        api.nvim_win_set_cursor(0, {line_number, 0})
    end
end

-- -----------------------------------------------------------------------------

return M
