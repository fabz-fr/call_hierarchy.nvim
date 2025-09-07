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
    file_previewer = nil,
}

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
function Manager.process_incoming_calls()
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
            local previewer_data = {}

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

                    -- New data to set 
                    local call_location_link = {
                            uri = caller.uri,
                            range = {
                                start = { line = calls.start.line + 1, character = calls.start.character }, -- The target line is 1 more (dunno why)
                                ["end"] = { line = calls["end"].line + 1, character = calls["end"].character } -- The target line is 1 more (dunno why)
                            }
                        }
                    local format = string.format("·%s (%s:%s)", caller_funcname, caller_filename, calls.start.line)

                    table.insert(previewer_data, {format = format, location_link = call_location_link})
                end

                table.insert(locations, {
                    callee             = callee,
                    caller_filename    = caller_filename,
                    caller_fullpath    = caller_fullpath,
                    caller_funcname    = caller_funcname,
                    caller_uri         = caller_uri,
                    caller_location    = caller_location,
                    calls_location     = calls_location,
                    previewer_data     = previewer_data,
                })
            end

            -- log.error("location is ", vim.inspect(locations))
            -- Callback are asynchronous, value must be set in config struct
            Manager.locations = locations
            Manager.locations2 = previewer_data
            Manager.process_done = true
        end)
    end)
end


-- --------------------------------------------------------------------------------------
-- Update calltree buffer with new values, from CallHierarchy.locations
-- --------------------------------------------------------------------------------------
function Manager.update_calltree()
    log.info("todo : format value and send it to file previewer")

    if Manager.locations == nil then
        log.error("Error Call hierarchy is empty nothing to update")
        return
    end

    Manager.file_previewer.display(Manager.locations2)

            -- log.error("location is ", vim.inspect(locations))
            -- Callback are asynchronous, value must be set in config struct
            -- Manager.locations = locations

    -- local buffer_content = {}
    --
    -- if Manager.locations == nil then
    --     log.error("Error Call hierarchy is empty nothing to update")
    --     return
    -- end
    --
    -- -- Format calltree buffer content
    -- for _, it in ipairs(Manager.locations) do
    --     local caller_filename = it.caller_filename
    --     local caller_funcname = it.caller_funcname
    --     for _, jt in ipairs(it.calls_location) do
    --         table.insert(buffer_content, 
    --         string.format("·%s (%s:%s)", caller_funcname, caller_filename, jt.start.line))
    --     end
    -- end
    --
    -- -- fill calltree buffer
    -- vim.api.nvim_buf_set_option(Manager.calltree_buffer, "modifiable", true)
    -- vim.api.nvim_buf_set_option(Manager.calltree_buffer, "readonly", false)
    -- -- Clear buffer to show updated content
    -- vim.api.nvim_buf_set_lines(Manager.calltree_buffer, 0, -1, false, {})
    -- vim.api.nvim_buf_set_lines(Manager.calltree_buffer, 0, -1, false, buffer_content)
    -- vim.api.nvim_buf_set_option(Manager.calltree_buffer, "modifiable", false)
    -- vim.api.nvim_buf_set_option(Manager.calltree_buffer, "readonly", true)
    --
    -- -- Set preview window
    -- vim.api.nvim_win_set_cursor(Manager.calltree_window, {1, 0})
end

-- --------------------------------------------------------------------------------------
-- Create the calltree window.
-- Check calltree window doesn't exists, if they exists, remove them, and create it again
-- --------------------------------------------------------------------------------------
function Manager.show_incoming_calls()

    -- Start the the process of getting incoming calls
    Manager.process_incoming_calls()

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
    Manager.file_previewer.remove()

    -- Create a new calltree window to display new informations
    Manager.file_previewer.create("toto")

    -- Update calltree window with new information
    Manager.update_calltree()
end

-- -- Global keymaps
-- vim.keymap.set("n", "<leader>ci", show_incoming_calls, { desc = "Show incoming calls" })
vim.keymap.set("n", "<leader>ci", Manager.show_incoming_calls, { desc = "Show incoming calls" })

vim.api.nvim_create_user_command("ShowIncomingCalls", function()
    Manager.show_incoming_calls()
end, {})

-- vim.keymap.set("n", "<leader>tc", toggle_call_hierarchy, { desc = "Toggle call hierarchy" })
--
-- -- Autocommand to clean up when closing Neovim
-- vim.api.nvim_create_autocmd("VimLeavePre", {
--     callback = cleanup_window,
-- })

function Manager.setup(opts)
    Manager.file_previewer = require('call_hierarchy.file_previewer')
    log.info("Previewer loaded")
end

-- Export for modular usage if needed
return Manager
