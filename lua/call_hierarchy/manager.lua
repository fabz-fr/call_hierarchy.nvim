local log = require('log')

local Manager = {
    calltree_buffer = nil,
    calltree_window = nil,
    preview_buf = nil,
    preview_window = nil,
    locations = {},
    previous_win = nil, -- Previous neovim window, where cursor was. This variable is used to open the preview buffer in the last window used !
    dummy_buffer = nil, -- dummy buffer used to fill calltree windows during their creation
    process_done = true,
}

-- --------------------------------------------------------------------------------------
-- Close the window but keep the buffer in place
-- --------------------------------------------------------------------------------------
local function close_calltree()
    -- Check if windows and buffer are here and deleted them if needed
    if Manager.calltree_window then
        vim.api.nvim_win_close(Manager.calltree_window, true)
        Manager.calltree_window = nil
    end
    if Manager.preview_window then
        vim.api.nvim_win_close(Manager.preview_window, true)
        Manager.preview_window = nil
    end
end

-- --------------------------------------------------------------------------------------
-- Remove buffer and windows
-- Check calltree window doesn't exists, if they exists, remove them, and create it again
-- --------------------------------------------------------------------------------------
local function remove_calltree_window()
    -- Check if windows and buffer are here and deleted them if needed
    if Manager.calltree_window then
        vim.api.nvim_win_close(Manager.calltree_window, true)
        Manager.calltree_window = nil
    end
    if Manager.preview_window then
        vim.api.nvim_win_close(Manager.preview_window, true)
        Manager.preview_window = nil
    end
    if Manager.calltree_buffer then
        vim.api.nvim_buf_delete(Manager.calltree_buffer, { force = true })
        Manager.calltree_buffer = nil
    end
    if Manager.preview_buf then
        vim.api.nvim_buf_delete(Manager.preview_buf, { force = true })
        Manager.preview_buf = nil
    end
end

-- --------------------------------------------------------------------------------------
-- Hide the calltree floating window. To do this, remove the windows but keep the buffers in place
-- --------------------------------------------------------------------------------------
local function create_calltree_window()
    if Manager.calltree_window then
        vim.api.nvim_win_close(Manager.calltree_window, true)
        Manager.calltree_window = nil
    end
    if Manager.preview_window then
        vim.api.nvim_win_close(Manager.preview_window, true)
        Manager.preview_window = nil
    end
end

-- --------------------------------------------------------------------------------------
-- Update preview content
-- --------------------------------------------------------------------------------------
local function update_preview(uri, line, character)
    if not Manager.preview_window then
        log.error("Error: no callhierarchy window to use : ", Manager.preview_window)
        return
    end

    -- Load the actual file buffer
    local target_buf = vim.uri_to_bufnr(uri)

    if not vim.api.nvim_buf_is_loaded(target_buf) then
        vim.fn.bufload(target_buf)
        vim.api.nvim_buf_call(target_buf, function()
            vim.cmd("doautocmd BufRead")
end)
    end

    -- Set the actual file buffer in the preview window
    vim.api.nvim_win_set_buf(Manager.preview_window, target_buf)

    -- Position cursor on target line
    if vim.api.nvim_win_is_valid(Manager.preview_window) then
        local total_lines = vim.api.nvim_buf_line_count(target_buf)
        if line >= 1 and line <= total_lines then
            vim.api.nvim_win_set_cursor(Manager.preview_window, {line, character})

            -- Center the view around the target line
            vim.api.nvim_win_call(Manager.preview_window, function()
                vim.cmd("normal! zz")
            end)
        end
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
local function open_floating_window()
    -- Create a dummy buffer, unused, non modifiable, and not listed in buffer list
    if Manager.dummy_buffer == nil then
        Manager.dummy_buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_option(Manager.dummy_buffer, "modifiable", false)
    end

    local calltree_buffer = Manager.dummy_buffer
    local preview_buffer = Manager.dummy_buffer

    if Manager.calltree_window or Manager.preview_window then
        log.debug("Floating windows already present. Nothing to do")
        return
    end

    if Manager.preview_buf == nil then
        Manager.preview_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines( Manager.preview_buf, 0, -1, false, {})
        vim.api.nvim_buf_set_option(Manager.preview_buf, "bufhidden", "hide")
        vim.api.nvim_buf_set_option(Manager.preview_buf, "modifiable", false)
        vim.api.nvim_buf_set_option(Manager.preview_buf, "readonly", true)
    end

    if Manager.calltree_buffer == nil then
        Manager.calltree_buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines( Manager.calltree_buffer, 0, -1, false, {})
        vim.api.nvim_buf_set_option(Manager.calltree_buffer, "bufhidden", "hide")
        vim.api.nvim_buf_set_option(Manager.calltree_buffer, "filetype", "callhierarchy")
        vim.api.nvim_buf_set_option(Manager.calltree_buffer, "modifiable", false)
        vim.api.nvim_buf_set_option(Manager.calltree_buffer, "readonly", true)
    end

    Manager.previous_win = vim.api.nvim_get_current_win()

    local total_width             = math.floor(vim.o.columns * 0.7)
    local total_height            = math.floor(vim.o.lines * 0.7)
    local row                     = math.floor((vim.o.lines - total_height) / 2)
    local col                     = math.floor((vim.o.columns - total_width) / 2)
    local left_width              = math.floor(total_width * 0.4)
    local right_width             = total_width - left_width - 1

    Manager.calltree_window = vim.api.nvim_open_win(Manager.calltree_buffer, true, {
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

    Manager.preview_window  = vim.api.nvim_open_win(Manager.preview_buf, false, {
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

    vim.api.nvim_win_set_option(Manager.calltree_window, "cursorline", true)
    vim.api.nvim_win_set_option(Manager.preview_window, "number", true)
    vim.api.nvim_win_set_option(Manager.preview_window, "cursorline", true)

    -- When windows are created, Add keymap to the window
    -- <CR> : Open the file in neovim default last buffer location
    -- q    : remove calltree
    -- <Esc>: remove calltree
    -- on cursor move : update preview window
    -- Jump to location

    vim.keymap.set("n", "<CR>", function()
        local uri = nil
        local line = nil
        local char = nil

        local buffer_line = vim.api.nvim_win_get_cursor(0)[1]
        local str = vim.api.nvim_buf_get_lines(0, buffer_line - 1, buffer_line, false)[1]
        local filename, lineno_str = str:match("%(([^:]+):(%d+)%)")
        local lineno = tonumber(lineno_str)

        for i, it in ipairs(Manager.locations) do

            if it.caller_filename == filename then
                for _, jt in ipairs(Manager.locations[i].calls_location) do
                    if lineno == jt.start.line then
                        uri = it.caller_uri
                        line = jt.start.line
                        char = jt.start.character
                        break
                    end
                end
            end
        end

        if not uri then
            log.error("Couldn't find location", uri)
            return
        end

        close_calltree()

        local target_win = Manager.previous_win
        if target_win and vim.api.nvim_win_is_valid(target_win) then
            vim.api.nvim_set_current_win(target_win)
        else
            local wins = vim.api.nvim_list_wins()
            log.info("windows are ", vim.inspect(wins))
            for _, win in ipairs(wins) do
                if vim.api.nvim_win_get_config(win).relative == "" then
                    vim.api.nvim_set_current_win(win)
                    break
                end
            end
        end

        local clients = vim.lsp.get_active_clients({bufnr = 0})
        local client = clients[1]
        local encoding = client and client.offset_encoding or "utf-16"

        local location_link = {
                uri = uri,
                range = {
                    start = { line = line - 1, character = 0 }, -- The target line is 1 more (dunno why)
                    ["end"] = { line = line - 1, character = 0 } -- The target line is 1 more (dunno why)
                }
            }
        

        log.info("location link : ", location_link)

        vim.lsp.util.jump_to_location(location_link, encoding)
    end, { buffer = buf, desc = "Jump to location" })

    -- Close window
    vim.keymap.set("n", "q", close_calltree, { buffer = buf, desc = "Close window" })
    vim.keymap.set("n", "<Esc>", close_calltree, { buffer = buf, desc = "Close window" })

    -- Set up autocmd to update preview on any cursor movement
    local function preview_on_cursor_move()
        local uri = nil
        local line = nil
        local char = nil
        local buffer_line = vim.api.nvim_win_get_cursor(0)[1]
        local str = vim.api.nvim_buf_get_lines(0, buffer_line - 1, buffer_line, false)[1]

        local filename, lineno_str = str:match("%(([^:]+):(%d+)%)")
        local lineno = tonumber(lineno_str)

        for i, it in ipairs(Manager.locations) do

            if it.caller_filename == filename then
                for _, jt in ipairs(Manager.locations[i].calls_location) do
                    if lineno == jt.start.line then
                        uri = it.caller_uri
                        line = jt.start.line
                        char = jt.start.character
                        break
                    end
                end
            end
        end

        if uri == nil then
            log.error("uri not found:", uri)
            return
        end

        update_preview(uri, line, char)
    end

    -- Crée un groupe d'autocommandes dédié qui sera nettoyé à chaque appel
    local augroup = vim.api.nvim_create_augroup("CallHierarchyPreview", { clear = true })

    -- Crée l'autocommande à l'intérieur de ce groupe
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = augroup,
        buffer = Manager.calltree_buffer, -- = buf,
        callback = preview_on_cursor_move,
    })

end

-- --------------------------------------------------------------------------------------
-- Check the incoming calls where cursor currently is
-- returns a structure containing :
-- { {
--     caller_filename = "change.c",
--     caller_fullpath = "/home/fabien/Documents/test/neovim/src/nvim/change.c",
--     caller_funcname = "changed_common",
--     caller_location = {
--       start = { character = 13, line = 235 },
--       stop  = { character = 26, line = 235 }
--     },
--     calls_location = { {
--         start = { character = 21, line = 363 },
--         stop  = { character = 33, line = 363 }
--       }, {
--         start = { character = 16, line = 367 },
--         stop  = { character = 28, line = 367 }
--       } }
--   }, ... }
-- --------------------------------------------------------------------------------------
local function process_incoming_calls()
    local params = vim.lsp.util.make_position_params(0, 'utf-8')
    local locations = {}

    Manager.process_done = false

    vim.lsp.buf_request(0, "textDocument/prepareCallHierarchy", params, function(err, items)
        if err or not items or vim.tbl_isempty(items) then
            log.error("No call hierarchy items found")
            Manager.process_done = true
            return locations
        end

        local item = items[1]

        vim.lsp.buf_request(0, "callHierarchy/incomingCalls", { item = item }, function(err2, calls)
            if err2 or not calls or vim.tbl_isempty(calls) then
                log.error("No incoming calls found")
                Manager.process_done = true
                return locations
            end

            log.info("Get incoming calls")

            for _, call in ipairs(calls) do
                local callee             = item.name
                local caller             = call.from
                local caller_filename    = vim.fn.fnamemodify(vim.uri_to_fname(caller.uri), ":t")
                local caller_fullpath    = vim.uri_to_fname(caller.uri)
                local caller_funcname    = caller.name
                local caller_uri         = caller.uri
                local caller_location    = {
                    {
                        start = {
                            line      = caller.range.start.line + 1, -- line is one before the corresponding line
                            character = caller.range.start.character + 1 -- start character is one before the start of the pattern
                        },
                        stop = {
                            line      = caller.range["end"].line + 1,
                            character = caller.range["end"].character
                        },
                    },
                }

                local calls_location = {}
                for _, calls in ipairs(call.fromRanges) do
                    local loc = {
                        start = {
                            line = calls.start.line + 1,
                            character = calls.start.character + 1
                        },
                        stop = {
                            line = calls["end"].line + 1,
                            character = calls["end"].character
                        }
                    }
                    table.insert(calls_location, loc)
                end

                table.insert(locations, {
                    callee             = callee,
                    caller_filename    = caller_filename,
                    caller_fullpath    = caller_fullpath,
                    caller_funcname    = caller_funcname,
                    caller_uri         = caller_uri,
                    caller_location    = caller_location,
                    calls_location     = calls_location,
                })
            end

            -- log.error("location is ", vim.inspect(locations))
            -- Callback are asynchronous, value must be set in config struct
            Manager.locations = locations
            Manager.process_done = true
        end)
    end)
end


-- --------------------------------------------------------------------------------------
-- Update calltree buffer with new values, from CallHierarchy.locations
-- --------------------------------------------------------------------------------------
local function update_calltree()
    local buffer_content = {}

    if Manager.locations == nil then
        log.error("Error Call hierarchy is empty nothing to update")
        return
    end

    if Manager.calltree_buffer == nil then
        log.error("Error calltree buffer should exist")
        return
    end


    -- Format calltree buffer content
    for _, it in ipairs(Manager.locations) do
        local caller_filename = it.caller_filename
        local caller_funcname = it.caller_funcname
        for _, jt in ipairs(it.calls_location) do
            table.insert(buffer_content, 
            string.format("·%s (%s:%s)", caller_funcname, caller_filename, jt.start.line))
        end
    end

    -- fill calltree buffer
    vim.api.nvim_buf_set_option(Manager.calltree_buffer, "modifiable", true)
    vim.api.nvim_buf_set_option(Manager.calltree_buffer, "readonly", false)
    -- Clear buffer to show updated content
    vim.api.nvim_buf_set_lines(Manager.calltree_buffer, 0, -1, false, {})
    vim.api.nvim_buf_set_lines(Manager.calltree_buffer, 0, -1, false, buffer_content)
    vim.api.nvim_buf_set_option(Manager.calltree_buffer, "modifiable", false)
    vim.api.nvim_buf_set_option(Manager.calltree_buffer, "readonly", true)

    -- Set preview window
    vim.api.nvim_win_set_cursor(Manager.calltree_window, {1, 0})
    -- if #CallHierarchy.locations > 0 then
    --     -- -- Get file Uri based on filename
    --     -- local first_line = vim.api.nvim_buf_get_lines(CallHierarchy.calltree_buffer, 0, 1, false)[1]
    --     --
    --     -- -- Extrait le nom de fichier et la ligne avec une expression régulière
    --     -- local filename, lineno = first_line:match("%(([^:]+):(%d+)%)")
    --
    --     -- update_preview(CallHierarchy.locations[1].caller_uri, CallHierarchy.locations[1].calls_location[1].start.line, CallHierarchy.locations[1].calls_location[1].start.character)
    --
    -- end
end

-- --------------------------------------------------------------------------------------
-- Create the calltree window.
-- Check calltree window doesn't exists, if they exists, remove them, and create it again
-- --------------------------------------------------------------------------------------
local function show_incoming_calls()

    -- Start the the process of getting incoming calls
    process_incoming_calls()

    -- Wait for process to be finished (TODO needs to be reworked)
    vim.wait(1000, function()
        return Manager.process_done == true
    end, 10)

    -- If process failed, just display error
    if Manager.process_done == false then
        log.error("Error: Coudn't get incoming calls")
        return
    end

    -- Remove calltree window
    remove_calltree_window()

    -- Create a new calltree window to display new informations
    open_floating_window()

    -- Update calltree window with new information
    update_calltree()
end

-- -- Global keymaps
-- vim.keymap.set("n", "<leader>ci", show_incoming_calls, { desc = "Show incoming calls" })
vim.keymap.set("n", "<leader>ci", show_incoming_calls, { desc = "Show incoming calls" })

vim.api.nvim_create_user_command("ShowIncomingCalls", function()
    show_incoming_calls()
end, {})

-- vim.keymap.set("n", "<leader>tc", toggle_call_hierarchy, { desc = "Toggle call hierarchy" })
--
-- -- Autocommand to clean up when closing Neovim
-- vim.api.nvim_create_autocmd("VimLeavePre", {
--     callback = cleanup_window,
-- })

function Manager.setup(opts)

end

-- Export for modular usage if needed
return Manager
