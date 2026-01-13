local oil = require("oil")
local util = require("oil.util")
local namespace = vim.api.nvim_create_namespace("oil-lsp-diagnostics")

local default_config = {
    count = true,
    parent_dirs = true,
    diagnostic_colors = {
        error = "DiagnosticError",
        warn = "DiagnosticWarn",
        info = "DiagnosticInfo",
        hint = "DiagnosticHint",
    },
    diagnostic_symbols = {
        error = "",
        warn = "",
        info = "",
        hint = "󰌶",
    },
}

local current_config = vim.tbl_extend("force", default_config, {})

local function get_buf_from_path(path)
    local bufs = vim.api.nvim_list_bufs()
    for _, buf in ipairs(bufs) do
        local name = vim.api.nvim_buf_get_name(buf)
        if name == path then
            return buf
        end
    end
    return nil
end

local function get_diagnostics_summary(buffer_or_dir, is_dir)
    local severities = { error = 0, warn = 0, info = 0, hint = 0 }

    local diagnostic_getter
    if is_dir then
        local dir = buffer_or_dir
        if type(dir) == "string" and not vim.endswith(dir, "/") then
            dir = dir .. "/"
        end

        diagnostic_getter = function(buf)
            return vim.startswith(vim.api.nvim_buf_get_name(buf), dir)
        end
    elseif type(buffer_or_dir) == "number" then
        diagnostic_getter = function(buf)
            return buf == buffer_or_dir
        end
    else
        diagnostic_getter = function(buf)
            return vim.api.nvim_buf_get_name(buf) == buffer_or_dir
        end
    end

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if diagnostic_getter(buf) then
            for key, _ in pairs(severities) do
                severities[key] = severities[key]
                    + #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity[string.upper(key)] })
            end
        end
    end

    return severities
end

local function add_lsp_extmarks(buffer)
    vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)

    for n = 1, vim.api.nvim_buf_line_count(buffer) do
        local dir = oil.get_current_dir(buffer)
        local entry = oil.get_entry_on_line(buffer, n)
        local is_dir = entry and entry.type == "directory" or false
        local diagnostics

        if entry then
            if is_dir then
                if current_config.parent_dirs then
                    diagnostics = get_diagnostics_summary(dir .. entry.name .. "/", true)
                end
            else
                local file_path = dir .. entry.name
                local file_buf = get_buf_from_path(file_path)
                diagnostics = file_buf and get_diagnostics_summary(file_buf, false)
                    or get_diagnostics_summary(file_path, false)
            end
        end

        if diagnostics then
            local virt_text = {}
            for _, key in ipairs({ "error", "warn", "info", "hint" }) do
                local count = diagnostics[key]
                if count and count > 0 then
                    local color = current_config.diagnostic_colors[key]
                    local symbol = current_config.diagnostic_symbols[key]
                    local text = current_config.count and (count .. symbol) or symbol
                    table.insert(virt_text, { text .. "  ", color })
                end
            end

            if #virt_text > 0 then
                vim.api.nvim_buf_set_extmark(buffer, namespace, n - 1, 0, {
                    virt_text = virt_text,
                    virt_text_pos = "eol",
                    hl_mode = "combine",
                })
            end
        end
    end
end

local function setup(config)
    current_config = vim.tbl_extend("force", default_config, config or {})

    vim.api.nvim_create_autocmd("FileType", {
        pattern = "oil",
        callback = function(event)
            local buffer = event.buf

            if vim.b[buffer].oil_lsp_started then
                return
            end
            vim.b[buffer].oil_lsp_started = true

            util.run_after_load(buffer, function()
                add_lsp_extmarks(buffer)
            end)

            local group = vim.api.nvim_create_augroup("OilLspDiagnostics" .. buffer, { clear = true })

            vim.api.nvim_create_autocmd("DiagnosticChanged", {
                group = group,
                callback = function()
                    if not vim.api.nvim_buf_is_valid(buffer) then
                        vim.api.nvim_del_augroup_by_id(group)
                        return
                    end

                    add_lsp_extmarks(buffer)
                end,
            })
        end,
    })
end

return {
    setup = setup,
}
