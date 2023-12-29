local M = {}

M.HEADER_HUNK_PATT = "@@ %-(%d-),(%d-) %+(%d-),(%d-) @@"

---@type vsc-helper.VcsSystem?
M.active_system = nil
M.root_dir = "."

---@type {[string]: vcs-helper.DiffRecord[]}
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

-- Representing grouping condition of lines of text, can be used to slice lines
-- into several chunks.
---@class vcs-helper.LineRangeCondition
---@field st_cond fun(lines: string[], index: integer): boolean
---@field ed_cond fun(lines: string[], index: integer, range_st: integer): boolean
local LineRangeCondition = {}
M.LineRangeCondition = LineRangeCondition

-- Creates new line range condition with given condition function.
-- Each condition function will be called with lines array and index of current
-- position.
-- Condition function is free to look forward or backward to determine if current
-- line is a valid rankge start/end.
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

-- Given lines array and position index, returns next range closest to current
-- position.
-- Returned range is inclusive on both end, if no range is found, both `st` and
-- `ed` would be `nil`.
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
    return path:match("%a:[/\\]") ~= nil
        or path:sub(1, 1) == "/"
end

---@param path string
---@return string?
function M.to_abs_path(path)
    if M.is_abs_path(path) then return path end

    local pwd = vim.fs.normalize(vim.fn.getcwd())
    path = vim.fs.normalize(path)

    local result_segments = vim.split(pwd, "/")
    local path_segments = vim.split(path, "/")
    if #path_segments == 0 then
        path_segments = { path }
    end

    for _, seg in ipairs(path_segments) do
        if seg == ""
            or seg == "."
            or seg:match("%s+") == seg
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

---@param path string
---@return string
function M.path_simplify(path)
    path = vim.fs.normalize(path)
    local pwd = vim.fs.normalize(vim.fn.getcwd())
    local repo_root = M.root_dir

    if M.starts_with(path, pwd) then
        path = "." .. path:sub(#pwd + 1)
    elseif M.starts_with(path, repo_root) then
        path = "{repo-root}" .. path:sub(#repo_root + 1)
    end

    return path
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

---@param path string
---@return boolean
function M.path_exists(path)
    return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

---@param pwd string
---@param target string
function M.find_root_by_keyfile(pwd, target)
    if M.path_exists(pwd .. "/" .. target) then
        return pwd
    end

    local root_dir
    for dir in vim.fs.parents(pwd) do
        if M.path_exists(dir .. "/" .. target) then
            root_dir = dir
            break
        end
    end

    return root_dir
end

-- -------------------------------------------------------------------------------
-- Diff

local DIFF_EOF_NEW_LINE = "EOF NEWLINE"

---@enum vcs-helper.Header
local Header = {
    old_file = "---",
    new_file = "+++",
    hunk = "@@"
}
M.Header = Header

---@enum vcs-helper.LinePrefix
local DiffPrefix = {
    old = "-",
    new = "+",
    common = " ",
    no_newline_at_eof = "\\",
}
M.LinePrefix = DiffPrefix

---@enum vcs-helper.DiffType
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
    local _, _, new_st_line_number, new_line_cnt = diff_lines[st]:match(M.HEADER_HUNK_PATT)

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
        elseif DiffPrefix.no_newline_at_eof then
            -- pass
        else
            break
        end

        if last_sign == DiffPrefix.no_newline_at_eof then
            if sign == DiffPrefix.old then
                buffer_old[#buffer_old + 1] = DIFF_EOF_NEW_LINE
            elseif sign == DiffPrefix.new then
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

---@param diff_lines string[]
---@param st integer
---@param ed integer
---@return string filename
---@return vcs-helper.DiffRecord[] records
function M.parse_diff_file(diff_lines, st, ed)
    local system = M.active_system
    if not system then return "", {} end

    local len = #diff_lines
    ed = ed <= len and ed or len

    local filename = system.get_file_path(diff_lines, st, ed)
    filename = vim.fs.normalize(M.to_abs_path(filename))

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

---@param path string
function M.parse_diff(path)
    local abs_path = M.to_abs_path(path)
    local system = M.active_system
    if not (abs_path and system) then
        return
    end

    local diff = system.diff_cmd(abs_path)
    local diff_lines = vim.split(diff, "\n")
    local len, index = #diff_lines, 1

    while index <= len do
        local st, ed = system.file_diff_range_cond:get_line_range(diff_lines, index)
        if not (st and ed) then break end

        local filename, records = M.parse_diff_file(diff_lines, st, ed)
        if filename then
            M.record_map[filename] = records
        end

        index = ed + 1
    end
end

function M.clear_diff_records()
    M.record_map = {}
end

---@param filename string
---@return vcs-helper.DiffRecord[]?
function M.get_diff_record(filename)
    local abs_filename = M.to_abs_path(filename)
    if not abs_filename then return end

    abs_filename = vim.fs.normalize(abs_filename)

    return M.record_map[abs_filename]
end

function M.get_diff_line(path)
    local abs_path = M.to_abs_path(path)
    local system = M.active_system
    if not (abs_path and system) then
        return
    end
    local diff = system.diff_cmd(abs_path)
    return vim.split(diff, "\n")
end

-- -----------------------------------------------------------------------------
-- Status

---@enum vcs-helper.StatusType
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
    local records = {}

    for i = 1, #status_lines do
        records[#records + 1] = system.parse_status_line(status_lines[i])
    end

    table.sort(records, function(a, b)
        return a.path < b.path
    end)

    return records
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
        svn = require "vcs-helper.systems.svn",
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
