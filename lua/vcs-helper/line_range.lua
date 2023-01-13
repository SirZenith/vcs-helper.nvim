local M = {}

---@class LineRangeCondition
---@field st_cond fun(lines: string[], index: integer): boolean
---@field ed_cond fun(lines: string[], index: integer, range_st: integer): boolean
local LineRangeCondition = {}
M.LineRangeCondition = LineRangeCondition

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

return M
