local line_range = require "vcs-helper.line_range"

local LineRangeConditioin = line_range.LineRangeCondition

local M = {}

M.HEADER_HUNK_PATT = "@@ %-(%d-),(%d-) %+(%d-),(%d-) @@"

---@enum Header
local Header = {
    old_file = "---",
    new_file = "+++",
    hunk = "@@"
}
M.Header = Header

---@enum LinePrefix
local LinePrefix = {
    old = "-",
    new = "+",
    common = " "
}
M.LinePrefix = LinePrefix

---@enum DiffType
local DiffType = {
    none = "DiffNone",
    common = "DiffCommon",
    delete = "DiffDelete",
    insert = "DiffInsert",
    change = "DiffChange",
}
M.DiffType = DiffType

function M.starts_with(s, prefix)
    local len_s = #s
    local len_prefix = #prefix
    if len_s < len_prefix then
        return false
    end
    return s:sub(1, len_prefix) == prefix
end

M.hunk_diff_range_cond = LineRangeConditioin:new(
    function(lines, index)
        return index < #lines
            and lines[index]:match(M.HEADER_HUNK_PATT) ~= nil
    end,
    function(lines, index, st)
        if index <= st then return false end

        if index == #lines then
            return true
        else
            return lines[index + 1]:match(M.HEADER_HUNK_PATT) ~= nil
        end
    end
)


---@class VcsSystem
---@field file_diff_range_cond LineRangeCondition
---@field get_file_path fun(diff_lines: string[], st: integer, ed: integer): string
---@field parse_diff_file fun(diff_lines: string[], st: integer, ed: integer)): string, DiffRecord[]
---@field find_root fun(pwd: string): string?
---@field diff_cmd fun(root: string): string[]

---@type VcsSystem?
M.active_system = nil
M.root_dir = "."

---@type {[string]: DiffRecord[]}
M.record_map = {}

-- -----------------------------------------------------------------------------

---@class DiffRecord
---@field line integer # starting line number of this diff range.
---@field type DiffType
---@field old string[] # lines of old file.
---@field new string[] # lines of working copy.

---@param list DiffRecord[]
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
            old[#old + 1] = buffer_old[i]
            new[#new + 1] = ""
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
            old[#old + 1] = ""
            new[#new + 1] = buffer_new[i]
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
---@return DiffRecord[]
function M.parse_diff_hunk(diff_lines, st, ed)
    local _, _, new_st_line_number, _ = diff_lines[st]:match(M.HEADER_HUNK_PATT)

    local records = {}
    local buffer_old, buffer_new = {}, {}

    -- current line number in current working copy
    local cur_line_num = new_st_line_number - 1
    local last_common_line_num = cur_line_num

    -- skip hunk header then loop through hunk content
    for index = st + 1, ed do
        local diff_line = diff_lines[index]
        local sign = diff_line:sub(1, 1)
        local line = diff_line:sub(2)

        if sign == LinePrefix.old then
            buffer_old[#buffer_old + 1] = line
        elseif sign == LinePrefix.new then
            cur_line_num = cur_line_num + 1
            buffer_new[#buffer_new + 1] = line
        elseif sign == LinePrefix.common then
            cur_line_num = cur_line_num + 1

            local line_num = last_common_line_num + 1
            if M.add_diff_record(
                records, line_num, buffer_old, buffer_new
            ) then
                buffer_old, buffer_new = {}, {}
            end

            last_common_line_num = cur_line_num
        else
            break
        end
    end

    return records
end

---@return {[string]: DiffRecord[]} record_map
function M.parse_diff()
    local system = M.active_system
    if not system then
        M.record_map = {}
        return M.record_map
    end

    local diff_lines = system.diff_cmd(M.root_dir)
    local len, index = #diff_lines, 1
    local record_map = {}

    while index <= len do
        local st, ed = system.file_diff_range_cond:get_line_range(diff_lines, index)
        if not (st and ed) then break end

        local filename, records = system.parse_diff_file(diff_lines, st, ed)
        print(filename, records)
        record_map[filename] = records

        index = ed + 1
    end

    M.record_map = record_map

    return record_map
end

function M.get_diff_line()
    local system = M.active_system
    if not system then
        return {} 
    end
    return system.diff_cmd(M.root_dir)
end

---@param filename string
---@return DiffRecord[]?
function M.get_diff_record(filename)
    return M.record_map[filename]
end

function M.init()
    local systems = {
        git = require "vcs-helper.systems.git",
    }

    local sys, root
    local pwd = vim.fn.getcwd()
    for _, system in pairs(systems) do
        root = system.find_root(pwd)
        if root then
            sys = system
            break
        end
    end

    M.active_system = sys
    M.root_dir = root
end

return M
