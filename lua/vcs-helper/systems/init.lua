local sys_base = require "vcs-helper.systems.base"
local path_util = require "vcs-helper.util.path"

local M = {}

---@type vsc-helper.VcsSystem?
M.active_system = nil
M.root_dir = "."

---@type {[string]: vcs-helper.DiffRecord[]}
M.record_map = {}

-- -------------------------------------------------------------------------------
-- Diff

-- Run diff command on given path, analyze and save diff result.
---@param path string
function M.parse_diff(path)
    local abs_path = path_util.to_abs_path(path)
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

        local filename, records = sys_base.parse_diff_file(system, M.root_dir, diff_lines, st, ed)
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
    local abs_filename = path_util.to_abs_path(filename)
    if not abs_filename then return end

    abs_filename = vim.fs.normalize(abs_filename)

    return M.record_map[abs_filename]
end

-- Run diff command on given path, split diff output into lines.
---@param path string # target path
---@return string[]?
function M.get_diff_lines(path)
    local abs_path = path_util.to_abs_path(path)
    local system = M.active_system
    if not (abs_path and system) then
        return
    end
    local diff = system.diff_cmd(abs_path)
    return vim.split(diff, "\n")
end

-- -----------------------------------------------------------------------------
-- Status

---@param path? string
---@param callback fun(err?: string, records?: vcs-helper.StatusRecord[])
function M.parse_status(path, callback)
    path = path or M.root_dir
    if not path then return {} end

    local abs_path = path_util.to_abs_path(path)
    local system = M.active_system
    if not (abs_path and system) then
        return {}
    end

    system.status_cmd(abs_path, function(err, status)
        if err then
            callback(err)
            return
        end

        local status_lines = vim.split(status, "\n")
        local records = {}

        for i = 1, #status_lines do
            records[#records + 1] = system.parse_status_line(status_lines[i])
        end

        table.sort(records, function(a, b)
            return a.path < b.path
        end)

        callback(nil, records)
    end)
end

-- -----------------------------------------------------------------------------
-- Commit

---@param files string[]
---@param msg string
---@param callback fun(err?: string)
---@return string? err
function M.commit(files, msg, callback)
    local system = M.active_system
    if not system then return end

    return system.commit_cmd(files, msg, callback)
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
