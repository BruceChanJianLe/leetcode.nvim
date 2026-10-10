local config = require("leetcode.config")

---Solved state of problems solved on LintCode, kept apart from LeetCode's own
---problem list status because LeetCode never saw those submissions.
---@class lc.lintcode.Status
local Status = {}

---@return Path
local function file()
    return config.storage.cache:joinpath("lintcode_status.json")
end

---@return table<string, "ac"|"notac">
function Status.read()
    if not file():exists() then
        return {}
    end

    local ok, data = pcall(vim.json.decode, file():read() or "")
    return ok and type(data) == "table" and data or {}
end

---@param slug string LeetCode title slug
---@return "ac"|"notac"|nil
function Status.get(slug)
    return Status.read()[slug]
end

---@param slug string LeetCode title slug
---@param status "ac"|"notac"
function Status.set(slug, status)
    local data = Status.read()
    -- an accepted problem stays accepted after a later failed attempt
    if data[slug] == "ac" then
        return
    end

    data[slug] = status
    file():write(vim.json.encode(data), "w")
end

return Status
