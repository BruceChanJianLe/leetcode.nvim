local config = require("leetcode.config")

---Where a question's statement, starter code and judge come from.
---@class lc.Provider
---@field name "leetcode"|"lintcode"
---@field filename_tag? string inserted into solution filenames, keeps them apart per provider
---@field snippet fun(question: lc.ui.Question, lang: lc.lang): string|nil
---@field run fun(question: lc.ui.Question, submit: boolean, body: lc.Interpret.body, callback: fun(item?: lc.interpreter_response, state?: string, err?: lc.err))
---@field link fun(question: lc.ui.Question): string
---@field note? fun(question: lc.ui.Question): string[]|nil lines shown under the title
---@field status fun(question: lc.ui.Question): string|nil solved status
---@field record_status fun(question: lc.ui.Question, status: "ac"|"notac")

---@class lc.Providers
local M = {}

---@return boolean
function M.lintcode_enabled()
    return (config.user.lintcode or {}).enabled == true
end

---Whether a premium problem is served by LintCode instead of LeetCode.
---@param paid_only boolean
---@return boolean
function M.via_lintcode(paid_only)
    return paid_only == true and not config.auth.is_premium and M.lintcode_enabled()
end

---Whether a problem cannot be opened at all.
---@param paid_only boolean
---@return boolean
function M.is_locked(paid_only)
    return paid_only == true and not config.auth.is_premium and not M.lintcode_enabled()
end

---@return lc.Provider
function M.leetcode()
    return require("leetcode.provider.leetcode")
end

---@return lc.Provider
function M.lintcode()
    return require("leetcode.lintcode")
end

return M
