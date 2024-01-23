local str_util = require "vcs-helper.util.str"

local M = {}

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

    if str_util.starts_with(path, pwd) then
        path = "." .. path:sub(#pwd + 1)
    elseif str_util.starts_with(path, repo_root) then
        path = "{repo-root}" .. path:sub(#repo_root + 1)
    end

    return path
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



return M
