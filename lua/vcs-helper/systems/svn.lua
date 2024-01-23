local sys_base = require "vcs-helper.systems.base"
local path_util = require "vcs-helper.util.path"
local str_util = require "vcs-helper.util.str"

local Header = sys_base.Header
local LineRangeCondition = str_util.LineRangeCondition

local starts_with = str_util.starts_with

---@class vcs-helper.system.Svn : vsc-helper.VcsSystem
local M = {}

-- ----------------------------------------------------------------------------

---@param pwd string
---@return string?
function M.find_root(pwd)
    if vim.fn.executable("svn") == 0 then
        return
    end

    return path_util.find_root_by_keyfile(pwd, ".svn")
end

-- -----------------------------------------------------------------------------

M.file_diff_range_cond = LineRangeCondition:new(
    function(lines, index)
        return index < #lines - 3
            and starts_with(lines[index], "Index: ")
            and lines[index + 1]:match("=+") ~= nil
    end,
    function(lines, index, st)
        local len = #lines
        if index <= st or index > len then
            return false
        elseif index == len then
            return true
        end

        return starts_with(lines[index + 1], "Index: ")
    end
)

---@param root_path string # path of svn root
---@param diff_lines string[]
---@param st integer # starting index of file diff region.
---@param ed integer # ending index of file diff region (including).
---@return string
function M.get_file_path(root_path, diff_lines, st, _)
    local line = diff_lines[st]
    return line:sub(#"Index: " + 1)
end

---@param diff_lines string[]
---@param st integer
---@param _ integer
---@return integer
function M.get_file_diff_header_len(diff_lines, st, _)
    local len = 2
    if starts_with(diff_lines[st + len], Header.old_file) then
        len = len + 1
    end
    if starts_with(diff_lines[st + len], Header.new_file) then
        len = len + 1
    end
    return len
end

-- -----------------------------------------------------------------------------

local STATUS_LINE_PATT = "([ ADMRCXI%?!~])([ MC])([ L])([ %+])([ S])([ KOTB])([ C]) (.+)"

---@param line string
---@return vcs-helper.StatusRecord?
function M.parse_status_line(line)
    local status, _, _, _, _, _, _, path = line:match(STATUS_LINE_PATT)
    if not (status and path) then return end

    path = vim.fs.normalize(path)

    return {
        local_status = status,
        path = str_util.read_quoted_string(path),
    }
end

-- -----------------------------------------------------------------------------

---@param root string # root path of repository
---@return string
function M.diff_cmd(root)
    return vim.fn.system("svn diff " .. root)
end

---@param root string # root path of repository
---@return string
function M.status_cmd(root)
    return vim.fn.system("svn status " .. root)
end

---@param files string[]
---@param msg string
---@return string? err
function M.commit_cmd(files, msg)
    local line = '"' .. table.concat(files, '" "') .. '"'
    local output = vim.fn.system('svn commit -m "' .. msg .. '" ' .. line)
    if vim.v.shell_error ~= 0 then
        vim.notify(output)
        return "failed to commit files"
    end
end

-- -----------------------------------------------------------------------------

return M
