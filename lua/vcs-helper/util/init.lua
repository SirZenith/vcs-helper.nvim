local loop = vim.uv or vim.loop

local M = {}

---@class vcs-helper.RunCmdResult
---@field code integer
---@field signal integer
---@field stdout string
---@field stderr string

---@param cmd string
---@param args string[]
---@param callback fun(result: vcs-helper.RunCmdResult)
---@return userdata handle
---@return integer pid
function M.run_cmd(cmd, args, callback)
    local stdout = loop.new_pipe()
    local stderr = loop.new_pipe()

    local out_buffer = {} ---@type string[]
    local err_buffer = {} ---@type string[]

    local handle, pid = loop.spawn(
        cmd,
        {
            args = args,
            stdio = { nil, stdout, stderr }
        },
        vim.schedule_wrap(function(code, signal)
            callback {
                code = code,
                signal = signal,
                stdout = table.concat(out_buffer),
                stderr = table.concat(err_buffer),
            }
        end)
    )

    loop.read_start(stdout, function(err, data)
        if err then return end
        out_buffer[#out_buffer + 1] = data
    end)

    loop.read_start(stderr, function(err, data)
        if err then return end
        err_buffer[#err_buffer + 1] = data
    end)

    return handle, pid
end

---@alias vcs-helper.util.AsyncStepFunc fun(next_step: fun(...: any), ...: any)

-- Accept a list of step function, each of them will be call with a handle
-- function `next_step` as first argument. After step function finish its work
-- it should calls `next_step`, all arguments passed to `next_step` will be
-- passed on to next step function as extra arguments.
---@param steps vcs-helper.util.AsyncStepFunc[]
function M.do_async_steps(steps)
    local step_index = 0

    local next_step
    next_step = function(...)
        step_index = step_index + 1

        local step_func = steps[step_index]
        if not step_func then return end

        step_func(next_step, ...)
    end

    next_step()
end

return M
