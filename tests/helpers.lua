local M = {}

---Applies a test configuration with storage in a fresh temporary directory.
---@param cfg? table
---@return lc.Config
function M.setup(cfg)
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    local config = require("leetcode.config")

    config.apply(vim.tbl_deep_extend("force", {
        logging = false,
        storage = { home = tmp .. "/home", cache = tmp .. "/cache" },
        lintcode = { enabled = true },
    }, cfg or {}))
    config.setup()
    config.auth = { is_signed_in = true, is_premium = false }

    return config
end

---Replaces `tbl[key]` until `restore` runs.
---@param mocks table
---@param tbl table
---@param key string
---@param value any
function M.mock(mocks, tbl, key, value)
    table.insert(mocks, { tbl = tbl, key = key, value = tbl[key] })
    tbl[key] = value
end

---@param mocks table
function M.restore(mocks)
    for i = #mocks, 1, -1 do
        local m = mocks[i]
        m.tbl[m.key] = m.value
        mocks[i] = nil
    end
end

---A JWT-shaped string, the contents do not matter to the client.
---@param name string
---@return string
function M.jwt(name)
    return ("eyJhbGciOiJIUzI1NiJ9.%s.c2lnbmF0dXJl"):format(name)
end

---A JWT carrying `claims`, unsigned.
---@param claims table
---@return string
function M.jwt_with(claims)
    local payload = vim.base64.encode(vim.json.encode(claims))
    return M.jwt((payload:gsub("%+", "-"):gsub("/", "_"):gsub("=", "")))
end

return M
