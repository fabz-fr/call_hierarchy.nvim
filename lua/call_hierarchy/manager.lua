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
    value_to_process = nil,
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
function Manager.process_incoming_calls(uri, line, character)
    local params = nil

    -- Si uri, line ou character ne sont pas fournis, on utilise la position actuelle du curseur
    if not uri or not line or not character then
        params = vim.lsp.util.make_position_params(0, 'utf-8')
    else
        params = {
            textDocument = {
                uri = uri,
            },
            position = {
                line = line,
                character = character,
            },
        }
    end

    -- Normaliser le chemin du fichier pour qu'il corresponde à ce que Neovim attend
    -- Assurez-vous que le buffer est ouvert pour le fichier, ou ouvrez-le si nécessaire
    local filepath = params.textDocument.uri:gsub("file://", "")
    local bufnr = vim.fn.bufnr(filepath)
    if bufnr == -1 then
        log.info("Buffer not open for: " .. filepath)
        return
    end

    local locations = {}

    Manager.process_done = false

    vim.lsp.buf_request(bufnr, "textDocument/prepareCallHierarchy", params, function(err, items)
        if err or not items or vim.tbl_isempty(items) then
            log.error("No call hierarchy items found")
            Manager.process_done = true
            return locations
        end
        log.info("aaaaaaaaaaaa : " , vim.inspect(items))

        local item = items[1]
        Manager.value_to_process = {
            format = "\t ─ " .. item.name,
            funcname = nil,
            caller_location_link = nil,
            location_link = {
                uri = item.uri,
                range = {
                    start = { line = item.selectionRange.start.line , character = item.selectionRange.start.character }, -- The target line is 1 more (dunno why)
                    ["end"] = { line = item.selectionRange["end"].line , character = item.selectionRange["end"].character } -- The target line is 1 more (dunno why)
                }
            },
        }

        vim.lsp.buf_request(bufnr, "callHierarchy/incomingCalls", { item = item }, function(err2, calls)
            if err2 or not calls or vim.tbl_isempty(calls) then
                log.error("No incoming calls found")
                Manager.process_done = true
                return locations
            end

            log.info("Get incoming calls")
        log.info("bbbbbbbbb : " , vim.inspect(calls))

            local previewer_data = {}

            for _, call in ipairs(calls) do
                local caller_filename    = vim.fn.fnamemodify(vim.uri_to_fname(call.from.uri), ":t")
                local caller_funcname    = call.from.name
                local caller_location_link = {
                    uri = call.from.uri,
                    range = {
                        start = { line = call.from.range.start.line, character = call.from.range.start.character },
                        ["end"] = { line = call.from.range["end"].line, character = call.from.range["end"].character},
                    },
                }
                local calls_location = {}

                for _, calls in ipairs(call.fromRanges) do
                    local call_location_link = {
                            uri = call.from.uri,
                            range = {
                                start = { line = calls.start.line , character = calls.start.character }, -- The target line is 1 more (dunno why)
                                ["end"] = { line = calls["end"].line , character = calls["end"].character } -- The target line is 1 more (dunno why)
                            }
                        }
                    local format = string.format("─ %s()", caller_funcname)

                    table.insert(previewer_data, {format = format, funcname = caller_funcname, location_link = call_location_link, caller_location_link = caller_location_link})
                end
            end

            -- If location is not empty, it means we are trying to get the incoming calls for a
            -- function that is present in the location variable. So we must update the formatting
            -- of this particular value. The value must be retrieved, it must be right shifted.
            -- Then the new value must be set added before this particular function
            if Manager.location ~= nil then
                log.info("location is not empty")
                local idx = nil
                for i, it in ipairs(Manager.location) do
                    log.info("comparing ", it.funcname, " with " , Manager.value_to_process)
                    if it.funcname == Manager.value_to_process then
                        it.format = "\t" .. it.format
                        log.info("found value : ", vim.inspect(it))
                        if idx == nil then
                            idx = i
                        end
                    end
                end

                -- insert all element at position i
                if idx ~= nil then
                    for i, it in ipairs(previewer_data) do
                        table.insert(Manager.location, idx, it)
                    end
                end

                Manager.process_done = true
            else
                -- Callback are asynchronous, value must be set in config struct
                table.insert(previewer_data, Manager.value_to_process)
                Manager.location = previewer_data
                Manager.process_done = true
            end
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

    Manager.file_previewer.display(Manager.location)
end

-- --------------------------------------------------------------------------------------
-- Update Manager.location with new data
-- --------------------------------------------------------------------------------------

function Manager.process_cb(loaded_file)
  local uri = loaded_file.caller_location_link.uri
  local range = loaded_file.caller_location_link.range

  -- Normaliser le chemin du fichier pour qu'il corresponde à ce que Neovim attend
  local filepath = uri:gsub("file://", "")

  -- Assurez-vous que le buffer est ouvert pour le fichier, ou ouvrez-le si nécessaire
  local bufnr = vim.fn.bufnr(filepath)
  if bufnr == -1 then
    log.info("Buffer not open for: " .. filepath)
    return
  end

  Manager.process_incoming_calls(uri, range.start.line, range.start.character)

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
    Manager.file_previewer.create("Incoming calls", Manager.process_cb)

    -- Update calltree window with new information
    Manager.update_calltree()
  -- -- 1. Exécuter la requête LSP pour 'textDocument/callHierarchy' pour obtenir les CallHierarchyItem
  -- vim.lsp.buf_request( bufnr, "textDocument/prepareCallHierarchy", hierarchy_params,
  --   function(err, call_hierarchy_items, ctx)
  --     if err then
  --       log.info("Erreur lors de la récupération de la hiérarchie d'appels: " .. err.message)
  --       return
  --     end
  --
  --     if not call_hierarchy_items or #call_hierarchy_items == 0 then
  --       log.info("Aucun CallHierarchyItem trouvé à la position spécifiée.")
  --       return
  --     end
  --
  --     -- Généralement, il ne devrait y avoir qu'un seul CallHierarchyItem pour une position donnée.
  --     local call_hierarchy_item = call_hierarchy_items[1]
  --     log.info("CallHierarchyItem trouvé: " .. vim.inspect(call_hierarchy_item))
  --
  --     -- 2. Une fois que nous avons le CallHierarchyItem, nous pouvons demander les appels entrants.
  --     local incoming_calls_params = {
  --       item = call_hierarchy_item
  --     }
  --
  --     vim.lsp.buf_request(
  --       bufnr,
  --       "callHierarchy/incomingCalls",
  --       incoming_calls_params,
  --       function(err_calls, incoming_calls_result, ctx_calls)
  --         if err_calls then
  --           log.info("Erreur lors de la récupération des appels entrants: " .. err_calls.message)
  --           return
  --         end
  --
  --         if incoming_calls_result and #incoming_calls_result > 0 then
  --             log.info("value found : ", vim.inspect(incoming_calls_result))
  --           log.info("Appels entrants trouvés pour la fonction à " .. filepath .. ":" .. (position.line + 1) .. ":" .. (position.character + 1) .. ":")
  --           for i, call in ipairs(incoming_calls_result) do
  --             local from_item = call.from
  --             local from_ranges = call.fromRanges -- Un tableau de plages où l'appel se produit
  --
  --             for j, from_range in ipairs(from_ranges) do
  --               log.info(string.format("  %d.%d: Appelant: %s (URI: %s), Range: Line %d-%d, Char %d-%d",
  --                 i, j,
  --                 from_item.name,
  --                 from_item.uri:gsub("file://", ""),
  --                 from_range.start.line + 1,
  --                 from_range["end"].line + 1,
  --                 from_range.start.character + 1,
  --                 from_range["end"].character + 1
  --               ))
  --             end
  --           end
  --         else
  --           log.info("Aucun appel entrant trouvé.")
  --         end
  --       end
  --     )
  --   end
  -- )
end
-- --------------------------------------------------------------------------------------
-- Create the calltree window.
-- Check calltree window doesn't exists, if they exists, remove them, and create it again
-- --------------------------------------------------------------------------------------
function Manager.show_incoming_calls()

    -- local test = {
    --     position = {
    --         character = 16,
    --         line = 171
    --     },
    --     textDocument = {
    --         uri = "file:///home/fabien/Documents/test/neovim/src/nvim/fold.c"
    --     }
    --   }
    --
    Manager.location = nil

    -- Start the the process of getting incoming calls
    -- Manager.process_incoming_calls(test.textDocument.uri, test.position.line, test.position.character)
    Manager.process_incoming_calls(nil, nil, nil)

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
    Manager.file_previewer.create("Incoming calls", Manager.process_cb)

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
