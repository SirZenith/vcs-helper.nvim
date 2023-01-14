local systems = require "vcs-helper.systems"

local Header = systems.Header
local LineRangeConditioin = systems.LineRangeCondition

local starts_with = systems.starts_with
local hunk_diff_range_cond = systems.hunk_diff_range_cond
local parse_diff_hunk = systems.parse_diff_hunk

local M = {}

-- -----------------------------------------------------------------------------
-- Diff

M.HEADER_OLD_FILE_PATT = "%-%-%- (.+)\t?"
M.HEADER_NEW_FILE_PATT = "%+%+%+ (.+)\t?"

M.file_diff_range_cond = LineRangeConditioin:new(
    function(lines, index)
        local len = #lines
        return index < len - 4
            and starts_with(lines[index + 0], "diff --git")
            and starts_with(lines[index + 1], "index ")
            and starts_with(lines[index + 2], Header.old_file)
            and starts_with(lines[index + 3], Header.new_file)
    end,
    function(lines, index, st)
        local len = #lines
        if index <= st or index > len then
            return false
        elseif index == len then
            return true
        end

        return starts_with(lines[index + 1], "diff --git")
    end
)

---@param diff_lines string[]
---@param st integer # starting index of file diff region.
---@param _ integer # ending index of file diff region (including).
---@return string
function M.get_file_path(diff_lines, st, _)
    local header_line = diff_lines[st + 3]
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

    local index = st + 4
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

-- -----------------------------------------------------------------------------
-- Status

local STATUS_LINE_PATT = "([ %?%a])([ %?%a]) (.+)"
local STATUS_PATH_PAIR_PATT = "(.+) %-> (.+)"

---@enum GitStatusPrefix
local StatusPrefix = {
    modify = "M",
    typechange = "T",
    add = "A",
    delete = "D",
    rename = "R",
    copy = "C",
    update = "U",
    untrack = "?",
    ignore = "!"
}

---@param line string
---@return StatusRecord?
function M.parse_status_line(line)
    local upstream_status, local_status, path_info = line:match(STATUS_LINE_PATT)
    if not (upstream_status and local_status and path_info) then
        return
    end

    local orig_path, path = path_info:match(STATUS_PATH_PAIR_PATT)
    path = path and path or path_info

    return {
        upstream_status = upstream_status,
        local_status = local_status,
        path = systems.read_quoted_string(path),
        orig_path = orig_path and systems.read_quoted_string(orig_path),
    }
end

---@param status_lines string[]
---@return StatusRecord[]
function M.parse_status(status_lines)
    local records = {}

    for i = 1, #status_lines do
        records[#records+1] = M.parse_status_line(status_lines[i])
    end

    return records
end

-- -----------------------------------------------------------------------------
-- Commands

---@param root string # root path of repository
---@return string
function M.diff_cmd(root)
    local diff = vim.fn.system("git diff " .. root)
    return diff
end

---@param root string # root path of repository
function M.status_cmd(root)
    local status = vim.fn.system("git status -s " .. root)
    return status
end

---@param files string[]
---@param msg string
---@return string? err
function M.commit_cmd(files, msg)
    local line = '"' .. table.concat(files, '" "') .. '"'
    local add_cmd = "git add " .. line
    vim.fn.system(add_cmd)
    if vim.v.shell_error ~= 0 then
        return "failed to stage files"
    end

    vim.fn.system('git commit -m "' .. msg .. '"')
    if vim.v.shell_error ~= 0 then
        return "files are staged but failed to commit"
    end
end

-- -----------------------------------------------------------------------------

---@param pwd string
---@return string?
function M.find_root(pwd)
    if vim.fn.executable("git") == 0 then
        return
    end

    if vim.fn.isdirectory(pwd .. "/.git") == 1 then
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
