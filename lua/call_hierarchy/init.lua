

local M = {}

M.default_opts = { }

function M.setup(opts)
	require('call_hierarchy.manager').setup(opts)
end
--
return M
