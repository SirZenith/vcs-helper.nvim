---@meta

---@class vsc-helper.VcsSystem
--
---@field file_diff_range_cond vcs-helper.LineRangeCondition
---@field get_file_path fun(diff_lines: string[], st: integer, ed: integer): string
---@field get_file_diff_header_len fun(diff_lines: string[], st: integer, ed: integer): integer
--
---@field parse_status_line fun(line: string): StatusRecord
--
---@field diff_cmd fun(root: string): string
---@field status_cmd fun(root: string): string
---@field commit_cmd fun(files: string[], msg: string): string?
--
---@field find_root fun(pwd: string): string?

---@class vcs-helper.DiffRecord
---@field line integer # starting line number of this diff range.
---@field type vcs-helper.DiffType
---@field old string[] # lines of old file.
---@field new string[] # lines of working copy.

---@class StatusRecord
---@field upstream_status vcs-helper.StatusType
---@field local_status vcs-helper.StatusType
---@field path string
---@field orig_path string?
