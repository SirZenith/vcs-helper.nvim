local M = {}

---@param buf integer
---@return integer? winnr
function M.find_win_with_buf(buf)
    if not buf then
        return nil
    end

    local win

    local wins = vim.api.nvim_list_wins()
    for _, w in ipairs(wins) do
        local b = vim.api.nvim_win_get_buf(w)
        if b == buf then
            win = w
            break
        end
    end

    return win
end

---@param target string
---@return integer? bufnr
---@return integer? winnr
function M.find_buf_with_name(target)
    local buf, win

    local bufs = vim.api.nvim_list_bufs()
    for _, b in ipairs(bufs) do
        local fullname = vim.api.nvim_buf_get_name(b)
        local name = vim.fs.basename(fullname)
        if name == target then
            buf = b
            break
        end
    end

    win = M.find_win_with_buf(buf)

    return buf, win
end

---@param target string
---@param is_listed boolean
---@param is_scratch boolean
---@return integer? bufnr # return nil when failed to create new buffer.
---@return integer? winnr
function M.find_or_create_buf_with_name(target, is_listed, is_scratch)
    local buf, win = M.find_buf_with_name(target)

    if not buf then
        buf = vim.api.nvim_create_buf(is_listed, is_scratch)
        if buf == 0 then
            return nil
        end

        vim.api.nvim_buf_set_name(buf, target)
    end

    return buf, win
end

function M.append_to_buf_with_highlight(buf, hl_name, lines)
    local line_cnt = #lines
    if line_cnt == 0 then return end

    vim.api.nvim_buf_set_lines(buf, -1, -1, true, lines)

    local content_line_cnt = vim.api.nvim_buf_line_count(buf)
    local line_st = content_line_cnt - line_cnt

    for l = line_st, line_st + line_cnt do
        vim.api.nvim_buf_add_highlight(buf, 0, hl_name, l, 0, -1)
    end
end

return M
