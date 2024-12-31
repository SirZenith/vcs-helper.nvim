local sys_base = require "vcs-helper.systems.base"
local util = require "vcs-helper.util"
local path_util = require "vcs-helper.util.path"
local str_util = require "vcs-helper.util.str"

local Header = sys_base.Header
local LineRangeConditioin = str_util.LineRangeCondition
local starts_with = str_util.starts_with

---@class vcs-helper.system.Git : vsc-helper.VcsSystem
local M = {}

-- ----------------------------------------------------------------------------

---@param pwd string
---@return string?
function M.find_root(pwd)
    if vim.fn.executable("git") == 0 then
        return
    end

    return path_util.find_root_by_keyfile(pwd, ".git")
end

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

---@param root_path string # path of repository root.
---@param diff_lines string[]
---@param st integer # starting index of file diff region.
---@param _ integer # ending index of file diff region (including).
---@return string
function M.get_file_path(root_path, diff_lines, st, _)
    local header_line = diff_lines[st + 3]
    local prefixed_path = header_line:match(M.HEADER_NEW_FILE_PATT) ---@type string

    for i = 1, #prefixed_path do
        if prefixed_path:sub(i, i) == "/" then
            prefixed_path = prefixed_path:sub(i + 1)
            break
        end
    end

    prefixed_path = prefixed_path:gsub("%s+$", "")

    local path = path_util.to_abs_path(root_path .. "/" .. prefixed_path)
    path = vim.fs.normalize(path)

    return path
end

---@return integer
function M.get_file_diff_header_len(_, _, _)
    return 4
end

-- -----------------------------------------------------------------------------
-- Status

local STATUS_LINE_PATT = "([ %?%a])([ %?%a]) (.+)"
local STATUS_PATH_PAIR_PATT = "(.+) %-> (.+)"

---@enum vcs-helper.system.git.StatusPrefix
local StatusPrefix = {
    nochange = " ",
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
---@return vcs-helper.StatusRecord?
function M.parse_status_line(line)
    local upstream_status, local_status, path_info = line:match(STATUS_LINE_PATT)
    if not (upstream_status and local_status and path_info) then
        return
    end

    local orig_path, path = path_info:match(STATUS_PATH_PAIR_PATT)
    path = path and path or path_info
    path = vim.fn.getcwd() .. "/" .. str_util.read_quoted_string(path)
    path = vim.fs.normalize(path)

    return {
        upstream_status = upstream_status,
        local_status = local_status,
        path = path,
        orig_path = orig_path and str_util.read_quoted_string(orig_path),
    }
end

-- -----------------------------------------------------------------------------
-- Commands

---@param root string # root path of repository
---@return string
function M.diff_cmd(root)
    local diff = vim.fn.system("git diff '" .. root .. "'")
    return diff
end

---@param root string # root path of repository
---@param callback fun(err?: string, result: string)
function M.status_cmd(root, callback)
    util.run_cmd("git", { "status", "-s", root }, function(result)
        if result.code == 0 then
            callback(nil, result.stdout)
            return
        end

        local err = result.stderr
        if err == "" then
            err = "failed to get repository status"
        end

        callback(err, "")
    end)
end

---@param files string[]
---@param msg string
---@param callback fun(err?: string)
---@return string? err
function M.commit_cmd(files, msg, callback)
    local cmd = "git"

    util.do_async_steps {
        function(next_step)
            local args = vim.list_extend({ "add" }, files)
            util.run_cmd(cmd, args, next_step)
        end,
        function(next_step, result)
            if result.code == 0 then
                next_step()
                return
            end

            local err = result.stderr
            if err == "" then
                err = "failed to stage files"
            end

            callback(err)
        end,
        function(next_step)
            local args = { "commit", "-m", msg }
            util.run_cmd(cmd, args, next_step)
        end,
        function(_, result)
            if result.code == 0 then
                callback()
                return
            end

            local err = result.stderr
            if err == "" then
                err = "files are staged but failed to commit"
            end

            callback(err)
        end,
    }
end

-- -----------------------------------------------------------------------------

return M
