local M = {}

M.HEADER_HUNK_PATT = "@@ %-(%d-),(%d-) %+(%d-),(%d-) @@"

---@class VcsSystem
--
---@field file_diff_range_cond LineRangeCondition
---@field get_file_path fun(diff_lines: string[], st: integer, ed: integer): string
---@field parse_diff_file fun(diff_lines: string[], st: integer, ed: integer)): string, DiffRecord[]
--
---@field parse_status fun(status_lines: string[]): StatusRecord[]
--
---@field diff_cmd fun(root: string): string
---@field status_cmd fun(root: string): string
---@field commit_cmd fun(files: string[], msg: string): string?
--
---@field find_root fun(pwd: string): string?

---@type VcsSystem?
M.active_system = nil
M.root_dir = "."

---@type {[string]: DiffRecord[]}
M.record_map = {}

function M.starts_with(s, prefix)
    local len_s = #s
    local len_prefix = #prefix
    if len_s < len_prefix then
        return false
    end
    return s:sub(1, len_prefix) == prefix
end

-- -----------------------------------------------------------------------------
-- Range extraction

---@class LineRangeCondition
---@field st_cond fun(lines: string[], index: integer): boolean
---@field ed_cond fun(lines: string[], index: integer, range_st: integer): boolean
local LineRangeCondition = {}
M.LineRangeCondition = LineRangeCondition

---@param st_cond fun(lines: string[], index: integer): boolean
---@param ed_cond fun(lines: string[], index: integer, range_st: integer): boolean
function LineRangeCondition:new(st_cond, ed_cond)
    self.__index = self

    local obj = {
        st_cond = st_cond,
        ed_cond = ed_cond,
    }

    return setmetatable(obj, self)
end

---@param lines string[]
---@param index integer
---@return integer? st
---@return integer? ed
function LineRangeCondition:get_line_range(lines, index)
    local len, st, ed = #lines, nil, nil
    local st_cond, ed_cond = self.st_cond, self.ed_cond
    for s = index, len do
        if st_cond(lines, s) then
            st = s

            for e = st, len do
                if ed_cond(lines, e, st) then
                    ed = e
                    break
                end
            end
        end

        if st and ed then break end
    end

    st = ed and st or nil

    return st, ed
end

-- -----------------------------------------------------------------------------
-- Utility

---@param path string
---@return boolean
function M.is_abs_path(path)
    if vim.fn.has("win32") then
        return path:match("%a:[/\\]") ~= nil
    else
        return path:sub(1, 1) == "/"
    end
end

---@param path string
---@return string?
function M.to_abs_path(path)
    if M.is_abs_path(path) then return path end

    local pwd = vim.fn.getcwd()
    pwd = vim.fs.normalize(pwd)
    path = vim.fs.normalize(path)

    local result_segments = vim.split(pwd, "/")
    local path_segments = vim.split(path, "/")

    for _, seg in ipairs(path_segments) do
        local white_st, white_ed = seg:match("%s+")
        if seg == ""
            or seg == "."
            or (white_st == 1 and white_ed == #seg)
        then
            -- pass
        elseif seg == ".." then
            local len = #result_segments
            if len == 1 then
                -- trying to get parent of root, illegal input path
                return nil
            end
            result_segments[len] = nil
        else
            result_segments[#result_segments + 1] = seg
        end
    end

    return table.concat(result_segments, "/")
end

local CHAR_ESCAPE_MAP = {
    ["a"] = "\a",
    ["b"] = "\b",
    ["e"] = "\027",
    ["f"] = "\012",
    ["n"] = "\n",
    ["r"] = "\r",
    ["t"] = "\t",
    ["v"] = "\v",
    ["\\"] = "\\",
    ["'"] = "'",
    ['"'] = '"',
    ["?"] = "?",
}

---@param str string
---@return string
function M.read_quoted_string(str)
    local _, content = str:match("%s*(['\"])(.*)%1%s*")
    if not content then
        return str
    end

    local buf = {}
    local is_escaping = false
    for i = 1, #content do
        local char = content:sub(i, i)

        local result
        if char == "\\" then
            is_escaping = true
        elseif is_escaping then
            result = CHAR_ESCAPE_MAP[char]
            is_escaping = false
        else
            result = char
        end

        buf[#buf + 1] = result
    end

    return table.concat(buf)
end

-- -------------------------------------------------------------------------------
-- Diff

---@enum Header
local Header = {
    old_file = "---",
    new_file = "+++",
    hunk = "@@"
}
M.Header = Header

---@enum LinePrefix
local DiffPrefix = {
    old = "-",
    new = "+",
    common = " "
}
M.LinePrefix = DiffPrefix

---@enum DiffType
local DiffType = {
    none = "DiffNone",
    common = "DiffCommon",
    delete = "DiffDelete",
    insert = "DiffInsert",
    change = "DiffChange",
}
M.DiffType = DiffType

M.hunk_diff_range_cond = LineRangeCondition:new(
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

        if sign == DiffPrefix.old then
            buffer_old[#buffer_old + 1] = line
        elseif sign == DiffPrefix.new then
            cur_line_num = cur_line_num + 1
            buffer_new[#buffer_new + 1] = line
        elseif sign == DiffPrefix.common then
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

---@param path string
function M.parse_diff(path)
    local abs_path = M.to_abs_path(path)
    local system = M.active_system
    if not (abs_path and system) then
        M.record_map = {}
        return
    end

    local diff = system.diff_cmd(abs_path)
    local diff_lines = vim.split(diff, "\n")
    local len, index = #diff_lines, 1
    local record_map = {}

    while index <= len do
        local st, ed = system.file_diff_range_cond:get_line_range(diff_lines, index)
        if not (st and ed) then break end

        local filename, records = system.parse_diff_file(diff_lines, st, ed)
        local abs_filename = M.to_abs_path(M.root_dir .. "/" .. filename)
        if abs_filename then
            record_map[abs_filename] = records
        end

        index = ed + 1
    end

    M.record_map = record_map
end

---@param filename string
---@return DiffRecord[]?
function M.get_diff_record(filename)
    local abs_filename = M.to_abs_path(filename)
    if not abs_filename then return end

    return M.record_map[abs_filename]
end

function M.get_diff_line(path)
    local abs_path = M.to_abs_path(path)
    local system = M.active_system
    if not (abs_path and system) then
        M.record_map = {}
        return
    end
    local diff = system.diff_cmd(abs_path)
    return vim.split(diff, "\n")
end

-- -----------------------------------------------------------------------------
-- Status

---@class StatusRecord
---@field upstream_status StatusType
---@field local_status StatusType
---@field path string
---@field orig_path string?

---@enum StatusType
local StatusType = {
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

---@param path? string
---@return StatusRecord[]
function M.parse_status(path)
    path = path or M.root_dir
    if not path then return {} end

    local abs_path = M.to_abs_path(path)
    local system = M.active_system
    if not (abs_path and system) then
        return {}
    end

    local status = system.status_cmd(abs_path)
    local status_lines = vim.split(status, "\n")
    return system.parse_status(status_lines)
end

-- -----------------------------------------------------------------------------
-- Commit

---@param files string[]
---@param msg string
---@return string? err
function M.commit(files, msg)
    local system = M.active_system
    if not system then
        return
    end

    return system.commit_cmd(files, msg)
end

-- -----------------------------------------------------------------------------

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
    M.root_dir = root and vim.fs.normalize(root)
end

return M
