local systems = require "vcs-helper.systems"
local line_range = require "vcs-helper.line_range"

local Header = systems.Header
local LineRangeConditioin = line_range.LineRangeCondition

local starts_with = systems.starts_with
local hunk_diff_range_cond = systems.hunk_diff_range_cond
local parse_diff_hunk = systems.parse_diff_hunk

local M = {}

M.HEADER_OLD_FILE_PATT = "%-%-%- (.+)\t?"
M.HEADER_NEW_FILE_PATT = "%+%+%+ (.+)\t?"

M.file_diff_range_cond = LineRangeConditioin:new(
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

---@param diff_lines string[]
---@param st integer # starting index of file diff region.
---@param _ integer # ending index of file diff region (including).
---@return string
function M.get_file_path(diff_lines, st, _)
    local header_line = diff_lines[st + 1]
    local prefixed_path = header_line:match(M.HEADER_NEW_FILE_PATT)

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
---@return string filename
---@return DiffRecord[] records
function M.parse_diff_file(diff_lines, st, ed)
    local len = #diff_lines
    ed = ed <= len and ed or len

    local filename = M.get_file_path(diff_lines, st, ed)

    local records = {}

    local index = st + 2
    while index <= ed do
        local s, e = hunk_diff_range_cond:get_line_range(diff_lines, index)
        if not (s and e) then break end

        local record = parse_diff_hunk(diff_lines, s, e)
        for _, r in ipairs(record) do
            records[#records + 1] = r
        end

        index = e + 1
    end

    return filename, records
end

---@param root string # root path of repository
---@return string[]
function M.diff_cmd(root)
    local diff = vim.fn.system("git diff " .. root)
    local diff_lines = vim.split(diff, "\n")
    return diff_lines
end

---@param pwd string
---@return string?
function M.find_root(pwd)
    if vim.fn.isdirectory(pwd .. "/.git") then
        return pwd
    end

    local root_dir
    for dir in vim.fs.parents(pwd) do
        if vim.fn.isdirectory(dir .. "/.git") == 1 then
            root_dir = dir
            break
        end
    end

    return root_dir
end

return M
