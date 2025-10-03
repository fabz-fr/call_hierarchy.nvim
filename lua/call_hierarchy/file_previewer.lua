local log = require('log')

local FilePreviewer = {
    file_window = nil,
    preview_window = nil,
    file_buffer = nil,
    preview_buffer = nil,
    height_size = 1,
    width_size = 1,
    preview_size = 0.7,

-- loaded_files is composed of
-- - format
-- - location_link
--     - uri
--     - range
--         - start
--             - line
--             - character
--         - ["end"] 
--             - line
--             - character
    loaded_files = nil, -- Contains file information in an array of tables

    process_cb = nil
}


-- --------------------------------------------------------------------------------------
-- File Preview migh process file in recursive mode. It means that file structure containg subfiles
-- - File1
--      - File1_A
--      - File1_B
-- - File2
-- - File3
--      -File3_A
--  ...
--
--  @param data: Data containing the data structure
--  @param id: the line number were the command was executed
--  @return: The data of the matched file
-- --------------------------------------------------------------------------------------
local function process_file(data, id)
    for i, it in ipairs(data) do
        if id == 1 then
            return it, id
        end

        id = id - 1

        if it.subcalls ~= nil then
            local retval, retid = process_file(it.subcalls, id)
            if retval ~= nil then
                return retval, retid
            else
                id = retid
            end
        end
    end
    return nil, id
end



-- --------------------------------------------------------------------------------------
-- Close the window but keep the buffer in place
-- --------------------------------------------------------------------------------------
function FilePreviewer.close()
    -- Check if windows and buffer are here and deleted them if needed
    if FilePreviewer.file_window then
        vim.api.nvim_win_close(FilePreviewer.file_window, true)
        FilePreviewer.file_window = nil
    end
    if FilePreviewer.preview_window then
        vim.api.nvim_win_close(FilePreviewer.preview_window, true)
        FilePreviewer.preview_window = nil
    end
end

-- --------------------------------------------------------------------------------------
-- Remove buffer and windows
-- Check calltree window doesn't exists, if they exists, remove them, and create it again
-- --------------------------------------------------------------------------------------
function FilePreviewer.remove()
    -- Check if windows and buffer are here and deleted them if needed
    if FilePreviewer.file_window then
        vim.api.nvim_win_close(FilePreviewer.file_window, true)
        FilePreviewer.file_window = nil
    end
    if FilePreviewer.preview_window then
        vim.api.nvim_win_close(FilePreviewer.preview_window, true)
        FilePreviewer.preview_window = nil
    end
    if FilePreviewer.file_buffer then
        vim.api.nvim_buf_delete(FilePreviewer.file_buffer, { force = true })
        FilePreviewer.file_buffer = nil
    end
    if FilePreviewer.preview_buffer then
        vim.api.nvim_buf_delete(FilePreviewer.preview_buffer, { force = true })
        FilePreviewer.preview_buffer = nil
    end
end

-- --------------------------------------------------------------------------------------
-- Update preview content
-- --------------------------------------------------------------------------------------
function FilePreviewer.update_preview(uri, line, character)
    if not FilePreviewer.preview_window then
        log.error("Error: no callhierarchy window to use : ", FilePreviewer.preview_window)
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
    vim.api.nvim_win_set_buf(FilePreviewer.preview_window, target_buf)

    -- Position cursor on target line
    if vim.api.nvim_win_is_valid(FilePreviewer.preview_window) then
        local total_lines = vim.api.nvim_buf_line_count(target_buf)
        if line >= 1 and line <= total_lines then
            vim.api.nvim_win_set_cursor(FilePreviewer.preview_window, {line, character})

            -- Center the view around the target line
            vim.api.nvim_win_call(FilePreviewer.preview_window, function()
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
function FilePreviewer.create(window_name, process_cb)

    if FilePreviewer.file_window or FilePreviewer.preview_window then
        log.debug("Floating windows already present. Nothing to do")
        return
    end

    if FilePreviewer.preview_buffer == nil then
        FilePreviewer.preview_buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines( FilePreviewer.preview_buffer, 0, -1, false, {})
        vim.api.nvim_buf_set_option(FilePreviewer.preview_buffer, "bufhidden", "hide")
        vim.api.nvim_buf_set_option(FilePreviewer.preview_buffer, "modifiable", false)
        vim.api.nvim_buf_set_option(FilePreviewer.preview_buffer, "readonly", true)
    end

    if FilePreviewer.file_buffer == nil then
        FilePreviewer.file_buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines( FilePreviewer.file_buffer, 0, -1, false, {})
        vim.api.nvim_buf_set_option(FilePreviewer.file_buffer, "bufhidden", "hide")
        vim.api.nvim_buf_set_option(FilePreviewer.file_buffer, "filetype", "callhierarchy")
        vim.api.nvim_buf_set_option(FilePreviewer.file_buffer, "modifiable", false)
        vim.api.nvim_buf_set_option(FilePreviewer.file_buffer, "readonly", true)
    end

    FilePreviewer.previous_win = vim.api.nvim_get_current_win()

    local total_width             = math.floor(vim.o.columns * FilePreviewer.width_size)
    local total_height            = math.floor((vim.o.lines ) * FilePreviewer.height_size) - 3
    local row                     = math.floor((vim.o.lines  - total_height) / 2)
    local col                     = math.floor((vim.o.columns - total_width) / 2)
    local left_width              = math.floor(total_width * (1 - FilePreviewer.preview_size))
    local right_width             = total_width - left_width - 1

    log.info("value of windows ", window_name)

    FilePreviewer.file_window = vim.api.nvim_open_win(FilePreviewer.file_buffer, true, {
        relative = "editor",
        width = left_width,
        height = total_height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = window_name,
        title_pos = "center",
    })

    FilePreviewer.preview_window  = vim.api.nvim_open_win(FilePreviewer.preview_buffer, false, {
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

    vim.api.nvim_win_set_option(FilePreviewer.file_window, "cursorline", true)
    vim.api.nvim_win_set_option(FilePreviewer.preview_window, "number", true)
    vim.api.nvim_win_set_option(FilePreviewer.preview_window, "cursorline", true)
    vim.api.nvim_win_set_option(FilePreviewer.preview_window, "wrap", false)
    vim.api.nvim_win_set_option(FilePreviewer.file_window, "wrap", false)

    -- When windows are created, Add keymap to the window
    -- <CR> : Open the file in neovim default last buffer location
    -- q    : remove calltree
    -- <Esc>: remove calltree
    -- on cursor move : update preview window Jump to location

    -- Close window
    vim.keymap.set("n", "q", FilePreviewer.close, { buffer = buf, desc = "Close window" })
    vim.keymap.set("n", "<Esc>", FilePreviewer.close, { buffer = buf, desc = "Close window" })

    vim.keymap.set("n", "<space>", function()
        local buffer_line = vim.api.nvim_win_get_cursor(0)[1]

        if type(buffer_line) ~= "number" then
            log.error("line couldn't be parsed. Abort operation")
            return
        end

        if FilePreviewer.loaded_files == nil then
            log.error("No loaded file found. Abort operation")
            return
        end

        -- We can have several levels of files. so the line number is not the index of the file in
        -- the list. If we have several level of file, we have to check the sub files
        file_to_process = process_file(FilePreviewer.loaded_files, buffer_line)

        if file_to_process == nil then
            log.error("No file found at index:", buffer_line)
            return
        end

        local file_to_load = file_to_process

        if file_to_load == nil then
            log.error("No file to load for preview")
            return
        end
        if file_to_load.location_link.uri == nil then
            log.error("file to preview doesn't contain uri")
            return
        end
        if file_to_load.location_link.range.start.line == nil or file_to_load.location_link.range.start.character == nil then
            log.error("wrong line of character value for previewing file")
            return
        end

        FilePreviewer.process_cb(file_to_load)
    end, { buffer = buf, desc = "process line" })

    vim.keymap.set("n", "<CR>", function()
        local buffer_line = vim.api.nvim_win_get_cursor(0)[1]

        if type(buffer_line) ~= "number" then
            log.error("line couldn't be parsed. Abort operation")
            return
        end

        if FilePreviewer.loaded_files == nil then
            log.error("No loaded file found. Abort operation")
            return
        end

        if FilePreviewer.loaded_files[buffer_line] == nil then
            log.error("No file found at index:", buffer_line)
            return
        end

        local file_to_load = FilePreviewer.loaded_files[buffer_line]

        local target_win = FilePreviewer.previous_win
        if target_win and vim.api.nvim_win_is_valid(target_win) then
            vim.api.nvim_set_current_win(target_win)
        else
            local wins = vim.api.nvim_list_wins()
            for _, win in ipairs(wins) do
                if vim.api.nvim_win_get_config(win).relative == "" then
                    vim.api.nvim_set_current_win(win)
                    break
                end
            end
        end

        local clients = vim.lsp.get_active_clients({bufnr = 0})

        if clients == nil then
            log.error("No LSP client found. Abort operation")
            return
        end

        local client = clients[1]
        local encoding = client and client.offset_encoding or "utf-16"

        local location_link = {
                uri = file_to_load.location_link.uri,
                range = {
                    start = { line = file_to_load.location_link.range.start.line , character = file_to_load.location_link.range.start.character }, -- The target line is 1 more (dunno why)
                    ["end"] = { line = file_to_load.location_link.range['end'].line , character = file_to_load.location_link.range['end'].character } -- The target line is 1 more (dunno why)
                }
            }


        FilePreviewer.close()

        vim.lsp.util.jump_to_location(location_link, encoding)
    end, { buffer = buf, desc = "Jump to location" })

    -- -- Set up autocmd to update preview on any cursor movement
    local function preview_on_cursor_move()
        local buffer_line = vim.api.nvim_win_get_cursor(0)[1]

        if type(buffer_line) ~= "number" then
            log.error("line couldn't be parsed. Abort operation")
            return
        end

        if FilePreviewer.loaded_files == nil then
            log.error("No loaded file found. Abort operation")
            return
        end

        -- We can have several levels of files. so the line number is not the index of the file in
        -- the list. If we have several level of file, we have to check the sub files
        file_to_process = process_file(FilePreviewer.loaded_files, buffer_line)

        if file_to_process == nil then
            log.error("No file found at index:", buffer_line)
            return
        end

        local file_to_load = file_to_process

        if file_to_load == nil then
            log.error("No file to load for preview")
            return
        end
        if file_to_load.location_link.uri == nil then
            log.error("file to preview doesn't contain uri")
            return
        end
        if file_to_load.location_link.range.start.line == nil or file_to_load.location_link.range.start.character == nil then
            log.error("wrong line of character value for previewing file")
            return
        end

        if file_to_load.caller_location_link ~= nil then
            -- To show where the caller is 
            FilePreviewer.update_preview(file_to_load.caller_location_link.uri, file_to_load.caller_location_link.range.start.line + 1, file_to_load.caller_location_link.range.start.character)
        else
            -- To show the where the call is done
            FilePreviewer.update_preview(file_to_load.location_link.uri, file_to_load.location_link.range.start.line + 1, file_to_load.location_link.range.start.character)
        end
    end

    -- Crée un groupe d'autocommandes dédié qui sera nettoyé à chaque appel
    local augroup = vim.api.nvim_create_augroup("CallHierarchyPreview", { clear = true })

    -- Crée l'autocommande à l'intérieur de ce groupe
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = augroup,
        buffer = FilePreviewer.file_buffer, -- = buf,
        callback = preview_on_cursor_move,
    })

    FilePreviewer.process_cb = process_cb
end

local function fmt(data)
    local format = ""

    for _, it in pairs(data) do
        format = format .. "\n" .. it.format or ""
        if it.format == nil then
            log.info("no format found for value ", vim.inspect(it))
        end

        if it.subcalls ~= nil then
            local d = fmt(it.subcalls) or ""
            format = format .. "\n" .. d
        end

    end

    return format
end

-- --------------------------------------------------------------------------------------
-- Display New data in file_buffer
-- Data must contains:
-- format : Format to display
-- location_link : Location_link to the file
-- --------------------------------------------------------------------------------------
function FilePreviewer.display(data)
    local buffer_content = {}

    if data == nil  then
        log.error("unexpected args. Should contain a valid data containing format and location_link at least :", vim.inspect(data))
        return
    end

    if FilePreviewer.file_buffer == nil then
        log.error("file_buffer not found")
        return
    end

    -- Load data in file_buffer for every item found in location_link
    local format = fmt(data)

    for line in format:gmatch("[^\r\n]+") do
      table.insert(buffer_content, line)
    end

    vim.api.nvim_buf_set_option(FilePreviewer.file_buffer, "modifiable", true)
    vim.api.nvim_buf_set_option(FilePreviewer.file_buffer, "readonly", false)
    vim.api.nvim_buf_set_lines(FilePreviewer.file_buffer, 0, -1, false, {})
    vim.api.nvim_buf_set_lines(FilePreviewer.file_buffer, 0, -1, false, buffer_content)
    vim.api.nvim_buf_set_option(FilePreviewer.file_buffer, "modifiable", false)
    vim.api.nvim_buf_set_option(FilePreviewer.file_buffer, "readonly", true)

    -- Set preview window
    vim.api.nvim_win_set_cursor(FilePreviewer.file_window, {1, 0})
    FilePreviewer.loaded_files = data
end

return FilePreviewer
