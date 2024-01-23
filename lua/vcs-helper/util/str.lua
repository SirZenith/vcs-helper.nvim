local M = {}

function M.starts_with(s, prefix)
    local len_s = #s
    local len_prefix = #prefix
    if len_s < len_prefix then
        return false
    end
    return s:sub(1, len_prefix) == prefix
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

-- ----------------------------------------------------------------------------

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

-- ----------------------------------------------------------------------------

return M
