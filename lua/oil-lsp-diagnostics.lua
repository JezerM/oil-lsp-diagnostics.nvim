local oil = require("oil")
local namespace = vim.api.nvim_create_namespace("oil-lsp-diagnostics")

local default_config = {
    diagnostic_colors = {
        error = "DiagnosticError",
        warn  = "DiagnosticWarn",
        info  = "DiagnosticInfo",
        hint  = "DiagnosticHint",
    },
    diagnostic_symbols = {
        error = "",
        warn = "",
        info = "",
        hint = "󰌶",
    }
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
    local diagnostic_getter = is_dir and function(buf)
        return vim.startswith(vim.api.nvim_buf_get_name(buf), buffer_or_dir)
    end or function(buf)
        return buf == buffer_or_dir
    end

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if diagnostic_getter(buf) then
            for key, severity in pairs(severities) do
                severities[key] = severities[key] + #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity[string.upper(key)] })
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

        if is_dir then
            diagnostics = get_diagnostics_summary(dir .. entry.name .. "/", true)
        else
            local file_buf = entry and get_buf_from_path(dir .. entry.name) or nil
            local is_active = file_buf and vim.api.nvim_buf_is_loaded(file_buf) or false
            diagnostics = is_active and get_diagnostics_summary(file_buf, false) or get_diagnostics_summary(dir .. entry.name, true)
        end

        if diagnostics then
            local p = 0
            for key, severity in pairs(diagnostics) do
                if severity > 0 then
                    local color = current_config.diagnostic_colors[key]
                    local symbol = current_config.diagnostic_symbols[key]
                    vim.api.nvim_buf_set_extmark(buffer, namespace, n - 1, 0, {
                        virt_text = { { symbol, color } },
                        priority = p,
                    })
                    p = p + 1
                end
            end
        end
    end
end

local function setup(config)
    current_config = vim.tbl_extend("force", default_config, config or {})

    vim.api.nvim_create_autocmd({ "FileType" }, {
        pattern = { "oil" },

        callback = function()
            local buffer = vim.api.nvim_get_current_buf()

            if vim.b[buffer].oil_lsp_started then
                return
            end
            vim.b[buffer].oil_lsp_started = true

            vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave", "TextChanged" }, {
                buffer = buffer,
                callback = function()
                    add_lsp_extmarks(buffer)
                end,
            })
        end,
    })
end

return {
    setup = setup,
}
