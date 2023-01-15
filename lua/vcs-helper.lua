local M = {}

function M.setup()
    local modules = {
        [1] = require "vcs-helper.systems",
        [2] = require "vcs-helper.commands",
    }

    for i = 1, #modules do
        modules[i].init()
    end
end

return M
