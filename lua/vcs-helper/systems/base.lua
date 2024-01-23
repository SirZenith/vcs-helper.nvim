local path_util = require "vcs-helper.util.path"
local str_util = require "vcs-helper.util.str"

local LineRangeCondition = str_util.LineRangeCondition

local M = {}

---@enum vcs-helper.Header
M.Header = {
    old_file = "---",
    new_file = "+++",
    hunk = "@@"
}

---@enum vcs-helper.DiffType
local DiffType = {
    none = "DiffNone",
    common = "DiffCommon",
    delete = "DiffDelete",
    insert = "DiffInsert",
    change = "DiffChange",
}
M.DiffType = DiffType

---@enum vcs-helper.DiffLinePrefix
local DiffLinePrefix = {
    old = "-",
    new = "+",
    common = " ",
    no_newline_at_eof = "\\",
}
M.DiffLinePrefix = DiffLinePrefix

---@enum vcs-helper.StatusType
M.StatusType = {
    modify = "StatusModify",
    typechange = "StatusTypeChange",
    add = "StatusAdd",
    delete = "StatusDelete",
    rename = "StatusRename",
    copy = "StatusCopy",
    update = "StatusUpdate",
    untrack = "StatusUntrack",
    ignore = "StatusIgnore",
}

-- ----------------------------------------------------------------------------

local DIFF_EOF_NEW_LINE = "EOF NEWLINE"
local HEADER_HUNK_PATT = "@@ %-(%d-),(%d-) %+(%d-),(%d-) @@"

M.hunk_diff_range_cond = LineRangeCondition:new(
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

---@param list vcs-helper.DiffRecord[]
---@param line_num integer # line number in working copy where this diff range starts.
---@param buffer_old string[] # modified lines in old file.
---@param buffer_new string[] # modified lines in working copy.
---@return boolean # indicating we do have at least one new record appended.
function M.add_diff_record(list, line_num, buffer_old, buffer_new)
    local dirty = false

    local len_old, len_new = #buffer_old, #buffer_new
    if len_old == 0 and len_new == 0 then
        return dirty
    end

    local smaller = math.min(len_old, len_new)
    if smaller > 0 then
        local old, new = {}, {}
        for i = 1, smaller do
            old[#old + 1] = buffer_old[i]
            new[#new + 1] = buffer_new[i]
        end

        list[#list + 1] = {
            line = line_num, type = DiffType.change,
            old = old, new = new
        }

        dirty = true
    end

    -- old file contains more lines, this is deletion.
    local delete_st = smaller + 1
    if delete_st <= len_old then
        local old, new = {}, {}
        for i = delete_st, len_old do
            local line = buffer_old[i]
            old[#old + 1] = line
            new[#new + 1] = line:gsub("[^%s]", "╴")
        end

        list[#list + 1] = {
            line = line_num + smaller, type = DiffType.delete,
            old = old, new = new,
        }

        dirty = true
    end

    -- new file contains more lines, this is insertion.
    local insert_st = smaller + 1
    if insert_st <= len_new then
        local old, new = {}, {}
        for i = insert_st, len_new do
            local line = buffer_new[i]
            old[#old + 1] = line:gsub("[^%s]", "─")
            new[#new + 1] = line
        end

        list[#list + 1] = {
            line = line_num + smaller, type = DiffType.insert,
            old = old, new = new,
        }

        dirty = true
    end

    return dirty
end

---@param diff_lines string[]
---@param st integer # starting index of target hunk region in diff_lines.
---@param ed integer # ending index of target hunk region in diff_lines (including).
---@return vcs-helper.DiffRecord[]
function M.parse_diff_hunk(diff_lines, st, ed)
    local _, _, new_st_line_number, new_line_cnt = diff_lines[st]:match(HEADER_HUNK_PATT)

    local records = {}
    local buffer_old, buffer_new = {}, {}

    -- current line number in current working copy
    local cur_line_num = new_st_line_number - 1
    local last_common_line_num = cur_line_num
    local ed_line_num = new_st_line_number + new_line_cnt - 1
    local last_sign = nil

    -- skip hunk header then loop through hunk content
    for index = st + 1, ed do
        local diff_line = diff_lines[index]
        local sign = diff_line:sub(1, 1)
        local line = diff_line:sub(2)

        if sign == DiffLinePrefix.old then
            buffer_old[#buffer_old + 1] = line
        elseif sign == DiffLinePrefix.new then
            cur_line_num = cur_line_num + 1
            buffer_new[#buffer_new + 1] = line
        elseif sign == DiffLinePrefix.common then
            cur_line_num = cur_line_num + 1

            local line_num = last_common_line_num + 1
            if M.add_diff_record(
                records, line_num, buffer_old, buffer_new
            ) then
                buffer_old, buffer_new = {}, {}
            end

            last_common_line_num = cur_line_num
        elseif DiffLinePrefix.no_newline_at_eof then
            -- pass
        else
            break
        end

        if last_sign == DiffLinePrefix.no_newline_at_eof then
            if sign == DiffLinePrefix.old then
                buffer_old[#buffer_old + 1] = DIFF_EOF_NEW_LINE
            elseif sign == DiffLinePrefix.new then
                buffer_new[#buffer_new + 1] = DIFF_EOF_NEW_LINE
            end
        end

        last_sign = sign
    end

    if last_common_line_num < ed_line_num then
        M.add_diff_record(
            records, last_common_line_num + 1, buffer_old, buffer_new
        )
    end

    return records
end

---@param system vsc-helper.VcsSystem
---@param root_path string
---@param diff_lines string[]
---@param st integer
---@param ed integer
---@return string filename
---@return vcs-helper.DiffRecord[] records
function M.parse_diff_file(system, root_path, diff_lines, st, ed)
    local len = #diff_lines
    ed = ed <= len and ed or len

    print(system, root_path, diff_lines, st, ed)

    local filename = system.get_file_path(root_path, diff_lines, st, ed)
    filename = vim.fs.normalize(path_util.to_abs_path(filename))

    local records = {}

    local index = st + system.get_file_diff_header_len(diff_lines, st, ed)
    while index <= ed do
        local s, e = M.hunk_diff_range_cond:get_line_range(diff_lines, index)
        if not (s and e) then break end

        local record = M.parse_diff_hunk(diff_lines, s, e)
        for _, r in ipairs(record) do
            records[#records + 1] = r
        end

        index = e + 1
    end

    return filename, records
end

-- ----------------------------------------------------------------------------

return M
