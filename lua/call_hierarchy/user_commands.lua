local M = {}

function M.setup(opts)
	require('hlpatterns.highlight_manager').setup(opts)

	local function get_highlight_manager() 
		return require('hlpatterns.highlight_manager')
	end

	-- @user command to delete all patterns 
	-- @param opts : string pattern to highlight
	vim.api.nvim_create_user_command(
		'HlpatternsDeleteAll',
		function()
			get_highlight_manager().delete_all_highlights()
		end,
		{ nargs = 0, desc = 'Delete all highlights' }
	)

	-- @user command Delete an highlight, all if no parameter is supplied
	-- @param opts : integer value representing the index (and not its ID) of the Highlight in the list
	vim.api.nvim_create_user_command(
		'HlpatternsDelete',
		function(opts)
			if next(opts.fargs) == nil then
				get_highlight_manager().delete_all_highlights()
			else
				arg_list = {}
				for _, param in ipairs(opts.fargs) do
					table.insert(arg_list, tonumber(param))
				end
				get_highlight_manager().delete(arg_list)
			end

		end,
		{ nargs = "*", desc = '' }
	)

	-- -- @user command to add highlight on a user defined pattern
	-- -- @param opts : string pattern to highlight
	-- vim.api.nvim_create_user_command(
	-- 	'HlpatternsAdd',
	-- 	function(opts)
	-- 		get_highlight_manager().highlight_custom(opts.args)
	-- 	end,
	-- 	{ nargs = 1, desc = 'Highlight a pattern' }
	-- )

	-- @user command to add highlight on a user defined pattern
	-- @param opts : string pattern to highlight
	vim.api.nvim_create_user_command(
		'HlpatternsAdd',
		function(opts)
			-- local size = #opts.fargs
			-- if size ~= 3 then
			-- 	print("Error: args should be <pattern> <bgcolor> <fgcolor>")
			-- 	return
			-- end

			local pattern = opts.fargs[1]
			local label   = opts.fargs[2]
			local bgcolor = opts.fargs[3]
			local fgcolor = opts.fargs[4]

			get_highlight_manager().highlight_custom(pattern, label, bgcolor, fgcolor)
		end,
		{ nargs = "*", desc = 'Highlight a pattern with custom highlight param are <pattern> <bgcolor> <fgcolor>' }
	)

	-- @user command to list all highlight patterns enable
	-- @param opts : string pattern to highlight
	vim.api.nvim_create_user_command(
		'HlpatternsList',
		function(opts)
			get_highlight_manager().list()
		end,
		{ nargs = 0, desc = 'List highlighted patterns' }
	)
end

return M
