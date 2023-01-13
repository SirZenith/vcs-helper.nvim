local line_range = require "vcs-helper.line_range"
local buf_op = require "vcs-helper.buf_op"

local LineRangeConditioin = line_range.LineRangeCondition

local diff_panel_namespace = "vschelper.diff"
local diff_panel_old_name = diff_panel_namespace .. ".old"
local diff_panel_new_name = diff_panel_namespace .. ".new"

local function starts_with(s, prefix)
    local len_s = #s
    local len_prefix = #prefix
    if len_s < len_prefix then
        return false
    end
    return s:sub(1, len_prefix) == prefix
end

---@enum Header
local Header = {
    old_file = "---",
    new_file = "+++",
    hunk = "@@"
}

---@enum LinePrefix
local LinePrefix = {
    old = "-",
    new = "+",
    common = " "
}

---@enum DiffType
local DiffType = {
    none = "DiffNone",
    common = "DiffCommon",
    delete = "DiffDelete",
    insert = "DiffInsert",
    change = "DiffChange",
}

local HEADER_OLD_FILE_PATT = "%-%-%- (.+)\t?"
local HEADER_NEW_FILE_PATT = "%+%+%+ (.+)\t?"
local HEADER_HUNK_PATT = "@@ %-(%d-),(%d-) %+(%d-),(%d-) @@"

local file_diff_range_cond = LineRangeConditioin:new(
    function(lines, index)
        return starts_with(lines[index], Header.old_file)
            and index < #lines
            and starts_with(lines[index + 1], Header.new_file)
    end,
    function(lines, index, st)
        if index <= st then return false end

        if index == #lines then
            return true
        else
            return starts_with(lines[index + 1], Header.old_file)
        end
    end
)

local hunk_diff_range_cond = LineRangeConditioin:new(
    function(lines, index)
        return index < #lines
            and lines[index]:match(HEADER_HUNK_PATT) ~= nil
    end,
    function(lines, index, st)
        if index <= st then return false end

        if index == #lines then
            return true
        else
            return lines[index + 1]:match(HEADER_HUNK_PATT) ~= nil
        end
    end
)

-- -----------------------------------------------------------------------------

local function add_diff_record(record, index, buffer_old, buffer_new)
    local len_old, len_new = #buffer_old, #buffer_new
    if len_old == 0 and len_new == 0 then
        return false
    end

    local smaller = math.min(len_old, len_new)
    if smaller > 0 then
        local old, new = {}, {}
        for i = 1, smaller do
            old[#old + 1] = buffer_old[i]
            new[#new + 1] = buffer_new[i]
        end

        record[#record + 1] = {
            line = index, type = DiffType.change,
            old = old, new = new
        }
    end

    local delete_st = smaller + 1
    if delete_st <= len_old then
        local old, new = {}, {}
        for i = delete_st, len_old do
            old[#old + 1] = buffer_old[i]
            new[#new + 1] = ""
        end

        record[#record + 1] = {
            line = index + smaller, type = DiffType.delete,
            old = old, new = {}
        }
    end

    local insert_st = smaller + 1
    if insert_st <= len_new then
        local old, new = {}, {}
        for i = insert_st, len_new do
            old[#old + 1] = ""
            new[#new + 1] = buffer_new[i]
        end

        record[#record + 1] = {
            line = index + smaller, type = DiffType.insert,
            old = old, new = new,
        }
    end

    return true
end

local function parse_diff_hunk(diff_lines, st, ed)
    local _, _, new_st, _ = diff_lines[st]:match(HEADER_HUNK_PATT)

    local diff_record = {}
    local buffer_old, buffer_new = {}, {}

    local last_common_index = new_st
    local new_offset = 0

    for index = 1, ed - st + 1 do
        local line = diff_lines[st + 1 + index]
        local sign = line:sub(1, 1)

        if sign == LinePrefix.old then
            buffer_old[#buffer_old + 1] = line:sub(2)
        elseif sign == LinePrefix.new then
            new_offset = new_offset + 1
            buffer_new[#buffer_new + 1] = line:sub(2)
        elseif sign == LinePrefix.common then
            if add_diff_record(
                diff_record, last_common_index + 1,
                buffer_old, buffer_new
            ) then
                buffer_old, buffer_new = {}, {}
            end

            new_offset = new_offset + 1
            last_common_index = new_st + new_offset
        else
            break
        end
    end

    return diff_record
end

---@param header_line string
local function get_file_path(header_line)
    local prefixed_path = header_line:match(HEADER_NEW_FILE_PATT)
    for i = 1, #prefixed_path do
        if prefixed_path:sub(i, i) == "/" then
            prefixed_path = prefixed_path:sub(i + 1)
            break
        end
    end
    return prefixed_path
end

---@param diff_lines string[]
---@param st integer
---@param ed integer
local function parse_diff_file(diff_lines, st, ed)
    local len = #diff_lines
    ed = ed <= len and ed or len

    local filename = get_file_path(diff_lines[st + 1])
    local diff_records = {}

    local index = st + 2
    while index <= ed do
        local s, e = hunk_diff_range_cond:get_line_range(diff_lines, index)
        if not (s and e) then break end

        local record = parse_diff_hunk(diff_lines, s, e)
        for _, r in ipairs(record) do
            diff_records[#diff_records + 1] = r
        end

        index = e + 1
    end

    return filename, diff_records
end

---@param diff_lines string[]
local function parse_diff(diff_lines)
    local len, index = #diff_lines, 1
    local diff_record = {}

    while index <= len do
        local st, ed = file_diff_range_cond:get_line_range(diff_lines, index)
        if not (st and ed) then break end

        local filename, records = parse_diff_file(diff_lines, st, ed)
        diff_record[filename] = records

        index = ed + 1
    end

    return diff_record
end

local function make_compare_lines(filename, records)
    local lines = {}
    local file, err = io.open(filename, "r")
    if not file then
        return nil, nil, err
    end

    for line in file:lines() do
        lines[#lines + 1] = line
    end

    local old, new = {}, {}
    local line_input_index = 1
    for _, record in ipairs(records) do
        local linenumber = record.line

        for i = line_input_index, linenumber - 1 do
            local line = lines[i]
            old[#old + 1] = line
            new[#new + 1] = line
        end

        local buffer_old = record.old or {}
        local buffer_new = record.new or {}
        local larger = math.max(#buffer_old, #buffer_new)

        for i = 1, larger do
            old[#old + 1] = buffer_old[i] or ""
            new[#new + 1] = buffer_new[i] or ""
        end

        line_input_index = linenumber + #buffer_new
    end

    for i = line_input_index, #lines do
        local line = lines[i]
        old[#old + 1] = line
        new[#new + 1] = line
    end

    return old, new
end

local function write_diff_record_to_buf(buf_old, buf_new, filename, records)
    vim.api.nvim_buf_set_lines(buf_old, 0, -1, true, {})
    vim.api.nvim_buf_set_lines(buf_new, 0, -1, true, {})

    local lines = {}
    local file, err = io.open(filename, "r")
    if not file then
        return err
    end

    for line in file:lines() do
        lines[#lines + 1] = line
    end

    local buffer
    local line_input_index = 1
    for _, record in ipairs(records) do
        local linenumber = record.line

        buffer = {}
        for i = line_input_index, linenumber - 1 do
            buffer[#buffer + 1] = lines[i]
        end
        buf_op.append_to_buf_with_highlight(buf_old, DiffType.common, buffer)
        buf_op.append_to_buf_with_highlight(buf_new, DiffType.common, buffer)

        local buffer_new = record.new
        local buffer_old = record.old

        local difftype = record.type
        local hl_old, hl_new
        if difftype == DiffType.insert then
            hl_old, hl_new = DiffType.none, DiffType.insert
        elseif difftype == DiffType.delete then
            hl_old, hl_new = DiffType.delete, DiffType.none
        else
            hl_old, hl_new = DiffType.change, DiffType.change
        end

        buf_op.append_to_buf_with_highlight(buf_old, hl_old, buffer_old)
        buf_op.append_to_buf_with_highlight(buf_new, hl_new, buffer_new)

        line_input_index = linenumber + #buffer_new
    end

    buffer = {}
    for i = line_input_index, #lines do
        buffer[#buffer + 1] = lines[i]
    end
    buf_op.append_to_buf_with_highlight(buf_old, DiffType.common, buffer)
    buf_op.append_to_buf_with_highlight(buf_new, DiffType.common, buffer)
end

local function get_diff(data)
    local filename = data.args
    if not filename then
        return
    end

    local diff = vim.fn.system("git diff ..")
    local diff_lines = vim.split(diff, "\n")

    local record_map = parse_diff(diff_lines)

    local buf_old, win_old = buf_op.find_or_create_buf_with_name(diff_panel_old_name, false, true)
    local buf_new, win_new = buf_op.find_or_create_buf_with_name(diff_panel_new_name, false, true)
    if not (buf_old and buf_new) then
        error("failed to create buf for diff content.")
    end

    vim.bo[buf_old].buftype = "nofile"
    vim.bo[buf_new].buftype = "nofile"

    if not (win_old and win_new) then
        vim.cmd "tabnew"
        win_old = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(win_old, buf_old)

        vim.cmd "rightbelow vsplit"
        win_new = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(win_new, buf_new)
    end

    vim.bo[buf_old].modifiable = true
    vim.bo[buf_new].modifiable = true

    local records = record_map[filename]
    if not records then
        return
    end

    local err = write_diff_record_to_buf(buf_old, buf_new, "../" .. filename, records)
    if err then
        print(err)
    end

    vim.bo[buf_old].modifiable = false
    vim.bo[buf_new].modifiable = false
end

vim.api.nvim_create_user_command("Diff", get_diff, {
    desc = "parse git diff in current workspace",
    nargs = 1,
})
