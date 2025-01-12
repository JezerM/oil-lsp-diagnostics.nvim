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

local function get_buf_diagnostics_summary(buffer)
    local severities = { error = 0, warn = 0, info = 0, hint = 0 }

    severities.error = #vim.diagnostic.get(buffer, { severity = vim.diagnostic.severity.ERROR })
    severities.warn = #vim.diagnostic.get(buffer, { severity = vim.diagnostic.severity.WARN })
    severities.info = #vim.diagnostic.get(buffer, { severity = vim.diagnostic.severity.INFO })
    severities.hint = #vim.diagnostic.get(buffer, { severity = vim.diagnostic.severity.HINT })

    return severities
end

local function get_directory_diagnostics_summary(dir)
    local severities = { error = 0, warn = 0, info = 0, hint = 0 }
    local bufs = vim.api.nvim_list_bufs()

    for _, buf in ipairs(bufs) do
        local name = vim.api.nvim_buf_get_name(buf)
        if vim.startswith(name, dir) then
            severities.error = severities.error + #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.ERROR })
            severities.warn = severities.warn + #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.WARN })
            severities.info = severities.info + #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.INFO })
            severities.hint = severities.hint + #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.HINT })
        end
    end

    return severities
end

local function add_lsp_extmarks(buffer)
    vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)

    for n = 1, vim.api.nvim_buf_line_count(buffer) do
        local dir = oil.get_current_dir(buffer)
        local entry = oil.get_entry_on_line(buffer, n)
        local is_folder = entry and entry.type == "directory" or false
        local diagnostics

        if is_folder then
            diagnostics = get_directory_diagnostics_summary(dir .. entry.name .. "/")
        else
            local file_buf = entry and get_buf_from_path(dir .. entry.name) or nil
            local is_active = file_buf and vim.api.nvim_buf_is_loaded(file_buf) or false
            if is_active then
                diagnostics = get_buf_diagnostics_summary(file_buf)
            else
                diagnostics = get_directory_diagnostics_summary(dir .. entry.name)
            end
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
