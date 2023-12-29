local panelpal = require "panelpal"

local api = vim.api
local systems = require "vcs-helper.systems"

local DiffType = systems.DiffType
local UpdateMethod = panelpal.PanelContentUpdateMethod

local M = {}

-- create a new array, mapping all empty line in input into some visible content.
---@param lines string[]
---@return string[]
local function map_empty_lines(lines)
    local buffer = {}
    for _, line in ipairs(lines) do
        table.insert(buffer, line ~= "" and line or "↩")
    end
    return buffer
end

-- read content as line array from give file
---@param filename string
---@return string[]?
---@return string? err
local function read_file_lines(filename)
    local lines = {}
    local file, err = io.open(filename, "r")
    if not file then
        return nil, err
    end

    for line in file:lines() do
        lines[#lines + 1] = line
    end

    return lines
end

-- write unchanged lines to buffer.
---@param lines string[]
---@param st integer
---@param ed integer
---@param buf_old integer
---@param buf_new integer
local function write_common_lines(lines, st, ed, buf_old, buf_new)
    if ed < st then return end

    local buffer = {}
    for i = st, ed do
        buffer[#buffer + 1] = lines[i]
    end
    panelpal.write_to_buf_with_highlight(buf_old, DiffType.common, buffer, UpdateMethod.append)
    panelpal.write_to_buf_with_highlight(buf_new, DiffType.common, buffer, UpdateMethod.append)
end

---@param filename string
---@param records vcs-helper.DiffRecord[]
---@param buf_old integer
---@param buf_new integer
function M.write_diff_record_to_buf(filename, records, buf_old, buf_new)
    api.nvim_buf_set_lines(buf_old, 0, -1, true, {})
    api.nvim_buf_set_lines(buf_new, 0, -1, true, {})

    local lines, err = read_file_lines(filename)
    if not lines then
        vim.notify(err or "")
        return
    end

    local line_input_index = 1
    for _, record in ipairs(records) do
        local linenumber = record.line

        write_common_lines(lines, line_input_index, linenumber - 1, buf_old, buf_new)

        local difftype = record.type
        local buffer_new = difftype == DiffType.insert and map_empty_lines(record.new) or record.new
        local buffer_old = difftype == DiffType.delete and map_empty_lines(record.old) or record.old
        panelpal.write_to_buf_with_highlight(buf_old, difftype, buffer_old, UpdateMethod.append)
        panelpal.write_to_buf_with_highlight(buf_new, difftype, buffer_new, UpdateMethod.append)

        local offset = difftype ~= DiffType.delete and #buffer_new or 0
        line_input_index = linenumber + offset
    end

    write_common_lines(lines, line_input_index, #lines, buf_old, buf_new)
end

return M
