---@meta

---@class vcs-helper.DiffRecord
---@field line integer # starting line number of this diff range.
---@field type vcs-helper.DiffType
---@field old string[] # lines of old file.
---@field new string[] # lines of working copy.

---@class vcs-helper.StatusRecord
---@field upstream_status vcs-helper.StatusType
---@field local_status vcs-helper.StatusType
---@field path string
---@field orig_path string?

-- ----------------------------------------------------------------------------

---@class vsc-helper.VcsSystem
---@field file_diff_range_cond vcs-helper.LineRangeCondition
local VcsSystem = {}

-- ----------------------------------------------------------------------------

-- Try to find root directory of current VCS. If no proper root directory is
-- found, `nil` will be returned.
---@param pwd string # current working directory
---@return string?
function VcsSystem.find_root(pwd)
end

-- ----------------------------------------------------------------------------

-- Get path of file which the given diff is for.
---@param root_path string # path of repository root.
---@param diff_lines string[] # lines of diff content.
---@param st integer # starting index of file diff region.
---@param ed integer # ending index of file diff region (inclusive).
---@return string file_path
function VcsSystem.get_file_path(root_path, diff_lines, st, ed)
end

-- Get number of header lines in diff content.
---@param diff_lines string[] # lines of diff content.
---@param st integer # starting index of file diff region.
---@param ed integer # ending index of file diff region (inclusive).
---@return integer
function VcsSystem.get_file_diff_header_len(diff_lines, st, ed)
end

-- ----------------------------------------------------------------------------

-- Translate a file status line into status record table.
---@param line string
---@return vcs-helper.StatusRecord?
function VcsSystem.parse_status_line(line)
end

-- ----------------------------------------------------------------------------

-- Run diff command on given root directory.
---@param root string
---@return string cmd_result
---@return string? err
function VcsSystem.diff_cmd(root)
end

-- Run status command on given root directory.
---@param root string
---@param callback fun(err?: string, result: string)
function VcsSystem.status_cmd(root, callback)
end

-- Commit file(s) with given message.
---@param files string[]
---@param msg string
---@param callback fun(err?: string)
function VcsSystem.commit_cmd(files, msg, callback)
end
