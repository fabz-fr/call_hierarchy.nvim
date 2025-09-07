
local WindowHandler = {
    calltree_window = nil,
    preview_window = nil,
    calltree_buffer = nil,
    preview_bufferfer = nil,

}

-- --------------------------------------------------------------------------------------
-- Close the window but keep the buffer in place
-- --------------------------------------------------------------------------------------
function WindowHandler.close()
    -- Check if windows and buffer are here and deleted them if needed
    if WindowHandler.calltree_window then
        vim.api.nvim_win_close(WindowHandler.calltree_window, true)
        WindowHandler.calltree_window = nil
    end
    if WindowHandler.preview_window then
        vim.api.nvim_win_close(WindowHandler.preview_window, true)
        WindowHandler.preview_window = nil
    end
end

-- --------------------------------------------------------------------------------------
-- Remove buffer and windows
-- Check calltree window doesn't exists, if they exists, remove them, and create it again
-- --------------------------------------------------------------------------------------
function WindowHandler.remove()
    -- Check if windows and buffer are here and deleted them if needed
    if WindowHandler.calltree_window then
        vim.api.nvim_win_close(WindowHandler.calltree_window, true)
        WindowHandler.calltree_window = nil
    end
    if WindowHandler.preview_window then
        vim.api.nvim_win_close(WindowHandler.preview_window, true)
        WindowHandler.preview_window = nil
    end
    if WindowHandler.calltree_buffer then
        vim.api.nvim_buf_delete(WindowHandler.calltree_buffer, { force = true })
        WindowHandler.calltree_buffer = nil
    end
    if WindowHandler.preview_bufferfer then
        vim.api.nvim_buf_delete(WindowHandler.preview_bufferfer, { force = true })
        WindowHandler.preview_bufferfer = nil
    end
end

-- --------------------------------------------------------------------------------------
-- Hide the calltree floating window. To do this, remove the windows but keep the buffers in place
-- --------------------------------------------------------------------------------------
function WindowHandler.create()
    if WindowHandler.calltree_window then
        vim.api.nvim_win_close(WindowHandler.calltree_window, true)
        WindowHandler.calltree_window = nil
    end
    if WindowHandler.preview_window then
        vim.api.nvim_win_close(WindowHandler.preview_window, true)
        WindowHandler.preview_window = nil
    end
end

-- --------------------------------------------------------------------------------------
-- Check if calltree windows exist, if not create them.
-- Check if buffer exist, if not create them
--
-- There are two uses cases : 
--  Windows and buffers don't exist. they shall be created (At first use or when a new calltree is asked)
--  Window are removed, but buffer still exist with preivous data, Thus, window should be created and fullfilled with buffer (at any other use)
-- --------------------------------------------------------------------------------------
function WindowHandler.open_floating_window()
    -- Create a dummy buffer, unused, non modifiable, and not listed in buffer list
    if WindowHandler.dummy_buffer == nil then
        WindowHandler.dummy_buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_option(WindowHandler.dummy_buffer, "modifiable", false)
    end

    local calltree_buffer = WindowHandler.dummy_buffer
    local preview_bufferfer = WindowHandler.dummy_buffer

    if WindowHandler.calltree_window or WindowHandler.preview_window then
        log.debug("Floating windows already present. Nothing to do")
        return
    end

    if WindowHandler.preview_buffer == nil then
        WindowHandler.preview_buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines( WindowHandler.preview_buffer, 0, -1, false, {})
        vim.api.nvim_buf_set_option(WindowHandler.preview_buffer, "bufhidden", "hide")
        vim.api.nvim_buf_set_option(WindowHandler.preview_buffer, "modifiable", false)
        vim.api.nvim_buf_set_option(WindowHandler.preview_buffer, "readonly", true)
    end

    if WindowHandler.calltree_buffer == nil then
        WindowHandler.calltree_buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines( WindowHandler.calltree_buffer, 0, -1, false, {})
        vim.api.nvim_buf_set_option(WindowHandler.calltree_buffer, "bufhidden", "hide")
        vim.api.nvim_buf_set_option(WindowHandler.calltree_buffer, "filetype", "callhierarchy")
        vim.api.nvim_buf_set_option(WindowHandler.calltree_buffer, "modifiable", false)
        vim.api.nvim_buf_set_option(WindowHandler.calltree_buffer, "readonly", true)
    end

    WindowHandler.previous_win = vim.api.nvim_get_current_win()

    local total_width             = math.floor(vim.o.columns * 0.7)
    local total_height            = math.floor(vim.o.lines * 0.7)
    local row                     = math.floor((vim.o.lines - total_height) / 2)
    local col                     = math.floor((vim.o.columns - total_width) / 2)
    local left_width              = math.floor(total_width * 0.4)
    local right_width             = total_width - left_width - 1

    WindowHandler.calltree_window = vim.api.nvim_open_win(WindowHandler.calltree_buffer, true, {
        relative = "editor",
        width = left_width,
        height = total_height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " Call Hierarchy ",
        title_pos = "center",
    })

    WindowHandler.preview_window  = vim.api.nvim_open_win(WindowHandler.preview_buffer, false, {
        relative = "editor",
        width = right_width,
        height = total_height,
        row = row,
        col = col + left_width + 1,
        -- style = "minimal",
        border = "rounded",
        title = " Preview ",
        title_pos = "center",
    })

    vim.api.nvim_win_set_option(WindowHandler.calltree_window, "cursorline", true)
    vim.api.nvim_win_set_option(WindowHandler.preview_window, "number", true)
    vim.api.nvim_win_set_option(WindowHandler.preview_window, "cursorline", true)

    -- When windows are created, Add keymap to the window
    -- <CR> : Open the file in neovim default last buffer location
    -- q    : remove calltree
    -- <Esc>: remove calltree
    -- on cursor move : update preview window
    -- Jump to location

    -- vim.keymap.set("n", "<CR>", function()
    --     local uri = nil
    --     local line = nil
    --     local char = nil
    --
    --     local buffer_line = vim.api.nvim_win_get_cursor(0)[1]
    --     local str = vim.api.nvim_buf_get_lines(0, buffer_line - 1, buffer_line, false)[1]
    --     local filename, lineno_str = str:match("%(([^:]+):(%d+)%)")
    --     local lineno = tonumber(lineno_str)
    --
    --     for i, it in ipairs(WindowHandler.locations) do
    --
    --         if it.caller_filename == filename then
    --             for _, jt in ipairs(WindowHandler.locations[i].calls_location) do
    --                 if lineno == jt.start.line then
    --                     uri = it.caller_uri
    --                     line = jt.start.line
    --                     char = jt.start.character
    --                     break
    --                 end
    --             end
    --         end
    --     end
    --
    --     if not uri then
    --         log.error("Couldn't find location", uri)
    --         return
    --     end
    --
    --     close_calltree()
    --
    --     local target_win = WindowHandler.previous_win
    --     if target_win and vim.api.nvim_win_is_valid(target_win) then
    --         vim.api.nvim_set_current_win(target_win)
    --     else
    --         local wins = vim.api.nvim_list_wins()
    --         log.info("windows are ", vim.inspect(wins))
    --         for _, win in ipairs(wins) do
    --             if vim.api.nvim_win_get_config(win).relative == "" then
    --                 vim.api.nvim_set_current_win(win)
    --                 break
    --             end
    --         end
    --     end
    --
    --     local clients = vim.lsp.get_active_clients({bufnr = 0})
    --     local client = clients[1]
    --     local encoding = client and client.offset_encoding or "utf-16"
    --
    --     local location_link = {
    --             uri = uri,
    --             range = {
    --                 start = { line = line - 1, character = 0 }, -- The target line is 1 more (dunno why)
    --                 ["end"] = { line = line - 1, character = 0 } -- The target line is 1 more (dunno why)
    --             }
    --         }
    --
    --
    --     log.info("location link : ", location_link)
    --
    --     vim.lsp.util.jump_to_location(location_link, encoding)
    -- end, { buffer = buf, desc = "Jump to location" })

    -- Close window
    vim.keymap.set("n", "q", WindowHandler.close, { buffer = buf, desc = "Close window" })
    vim.keymap.set("n", "<Esc>", WindowHandler.close, { buffer = buf, desc = "Close window" })

    -- -- Set up autocmd to update preview on any cursor movement
    -- local function preview_on_cursor_move()
    --     local uri = nil
    --     local line = nil
    --     local char = nil
    --     local buffer_line = vim.api.nvim_win_get_cursor(0)[1]
    --     local str = vim.api.nvim_buf_get_lines(0, buffer_line - 1, buffer_line, false)[1]
    --
    --     local filename, lineno_str = str:match("%(([^:]+):(%d+)%)")
    --     local lineno = tonumber(lineno_str)
    --
    --     for i, it in ipairs(WindowHandler.locations) do
    --
    --         if it.caller_filename == filename then
    --             for _, jt in ipairs(WindowHandler.locations[i].calls_location) do
    --                 if lineno == jt.start.line then
    --                     uri = it.caller_uri
    --                     line = jt.start.line
    --                     char = jt.start.character
    --                     break
    --                 end
    --             end
    --         end
    --     end
    --
    --     if uri == nil then
    --         log.error("uri not found:", uri)
    --         return
    --     end
    --
    --     update_preview(uri, line, char)
    -- end

    -- -- Crée un groupe d'autocommandes dédié qui sera nettoyé à chaque appel
    -- local augroup = vim.api.nvim_create_augroup("CallHierarchyPreview", { clear = true })

    -- -- Crée l'autocommande à l'intérieur de ce groupe
    -- vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    --     group = augroup,
    --     buffer = WindowHandler.calltree_buffer, -- = buf,
    --     callback = preview_on_cursor_move,
    -- })

end

return WindowHandler
