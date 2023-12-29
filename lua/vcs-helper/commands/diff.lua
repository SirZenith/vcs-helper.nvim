local panelpal = require "panelpal"

local api = vim.api
local systems = require "vcs-helper.systems"
local ui_diff_util = require "vcs-helper.ui_utils.diff"

local DiffType = systems.DiffType

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
---@param records vcs-helper.DiffRecord[]
function M.write_diff_record_to_buf(filename, records)
    local buf_old, buf_new = M.get_buffers()
    if not (buf_old and buf_new) then
        return "failed to create diff buffer"
    end

    vim.bo[buf_old].readonly = false
    vim.bo[buf_new].readonly = false

    ui_diff_util.write_diff_record_to_buf(filename, records, buf_old, buf_new)

    vim.bo[buf_old].readonly = true
    vim.bo[buf_new].readonly = true
end

---@param filename string
---@return vcs-helper.DiffRecord[]?
---@return string abs_filename
function M.update_diff(filename)
    local abs_filename = vim.fs.normalize(systems.to_abs_path(filename))
    local records = systems.get_diff_record(abs_filename)
    if not records then
        systems.parse_diff(abs_filename)
        records = systems.get_diff_record(abs_filename)
    end
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
function M.show(filename)
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

function M.reset()
    systems.clear_diff_records()

    local buf_old, buf_new = M.get_buffers()
    for _, buf in ipairs { buf_old, buf_new } do
        vim.bo[buf].readonly = false
        panelpal.clear_buffer_contnet(buf)
        vim.bo[buf].readonly = true
    end
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
        -- If they are not, then they are probably have no content.
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
        api.nvim_win_set_cursor(0, { line_number, 0 })
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
        -- If they are not, then they are probably have no content.
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
        api.nvim_win_set_cursor(0, { line_number, 0 })
    end
end

-- -----------------------------------------------------------------------------

return M
