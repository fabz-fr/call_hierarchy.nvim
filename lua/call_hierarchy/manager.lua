local log = require('log')

local Manager = {
    calltree_buffer = nil,
    calltree_window = nil,
    preview_buf = nil,
    preview_window = nil,
    previous_win = nil, -- Previous neovim window, where cursor was. This variable is used to open the preview buffer in the last window used !
    dummy_buffer = nil, -- dummy buffer used to fill calltree windows during their creation
    process_done = true,
    file_previewer = nil,
    value_to_process = nil,
}

local function deep_copy(orig)
  local copy
  if type(orig) == 'table' then
    copy = {}
    for k, v in next, orig, nil do
      copy[deep_copy(k)] = deep_copy(v)
    end
    setmetatable(copy, deep_copy(getmetatable(orig)))
  else
    copy = orig
  end
  return copy
end

function copy(t)
  local u = { }
  for k, v in pairs(t) do u[k] = v end
  return setmetatable(u, getmetatable(t))
end

function tables_equal(t1, t2)
  if t1 == t2 then return true end
  if type(t1) ~= "table" or type(t2) ~= "table" then return false end

  for k, v in pairs(t1) do
    if type(v) == "table" and type(t2[k]) == "table" then
      if not tables_equal(v, t2[k]) then return false end
    elseif v ~= t2[k] then
      return false
    end
  end

  for k in pairs(t2) do
    if t1[k] == nil then return false end
  end

  return true
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
function Manager.process_incoming_calls(uri, line, character)
    local params = nil
    Manager.process_done = false

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

    vim.lsp.buf_request(bufnr, "textDocument/prepareCallHierarchy", params, function(err, items)
        if err or not items or vim.tbl_isempty(items) then
            log.error("No call hierarchy items found")
            Manager.process_done = true
            return nil
        end

        local item = items[1]
        Manager.value_to_process = {
            format = "·" .. item.name,
            funcname = item.name,
            caller_location_link = {
                uri = item.uri,
                range = {
                    start = { line = item.selectionRange.start.line , character = item.selectionRange.start.character }, -- The target line is 1 more (dunno why)
                    ["end"] = { line = item.selectionRange["end"].line , character = item.selectionRange["end"].character } -- The target line is 1 more (dunno why)
                }
            },
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
                return nil
            end

            log.info("Get incoming calls")

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
                    local format = ""

                    table.insert(previewer_data, {format = format, funcname = caller_funcname, location_link = call_location_link, caller_location_link = caller_location_link})
                end
            end

            -- If location is not empty, it means we are trying to get the incoming calls for a
            -- function that is present in the location variable. So we must update the formatting
            -- of this particular value. The value must be retrieved, it must be right shifted.
            -- Then the new value must be set added before this particular function
            if #Manager.location ~= 0 then
                log.info("location is not empty : ", #Manager.location)
                local value_found = false

                local function add_data(data_to_check, input)
                    for k, v in ipairs(data_to_check) do

                        if data_to_check[k].subcalls ~= nil then
                            add_data(data_to_check[k].subcalls, input)
                        end

                        if  v.funcname                                       == input.funcname 
                         and v.caller_location_link.range["end"].character   == input.caller_location_link.range["end"].character 
                         and v.caller_location_link.range["end"].line        == input.caller_location_link.range["end"].line      
                         and v.caller_location_link.range.start.character    == input.caller_location_link.range.start.character  
                         and v.caller_location_link.range.start.line         == input.caller_location_link.range.start.line       
                         and v.caller_location_link.uri                      == input.caller_location_link.uri                    
                         and value_found == false
                         then
                            log.info("value found is at index ", k)
                            value_found = true
                            data_to_check[k].subcalls = deep_copy(previewer_data)
                        end

                    end
                end

                add_data(Manager.location, Manager.value_to_process)

            -- If value wasn't found, it means the value to process is the origin value
            else
                Manager.value_to_process.subcalls = deep_copy(previewer_data)
                table.insert(Manager.location, Manager.value_to_process)
            end

            Manager.format()
            Manager.process_done = true
        end)
    end)
end

local function fmt(data, format) 
    local tabs = format

    -- if level > 1 then
    --     tabs = string.rep("│   ", level - 1)
    -- end

    for i, it in ipairs(data) do
        if it.subcalls ~= nil then
            local next_format = tabs
            if i == #data then
                next_format = next_format .. "    "
            else
                next_format = next_format .. "│   "
            end
            it.subcalls = fmt(it.subcalls, next_format)
        end
        if i < #data then
            begin_format = tabs .. "├──"
        else
            begin_format = tabs .. "└──"
        end
        -- If last value 
        if i == #data then
            it.format = string.format("%s %s()", begin_format, it.funcname)
        else
            it.format = string.format("%s %s()", begin_format, it.funcname)
        end
    end
    return data
end

function Manager.format()
    -- First one is always the original one
    Manager.location[1].format = string.format("· %s()", Manager.location[1].funcname)

    if Manager.location[1].subcalls ~= nil then
        local begin_format = ""
        Manager.location[1].subcalls  = deep_copy(fmt(Manager.location[1].subcalls, begin_format))
    end
end

-- --------------------------------------------------------------------------------------
-- Update calltree buffer with new values, from CallHierarchy.location
-- --------------------------------------------------------------------------------------
function Manager.update_calltree()
    if Manager.location == nil then
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
end
-- --------------------------------------------------------------------------------------
-- Create the calltree window.
-- Check calltree window doesn't exists, if they exists, remove them, and create it again
-- --------------------------------------------------------------------------------------
function Manager.show_incoming_calls()
    Manager.location = {}
    Manager.process_done = false

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
