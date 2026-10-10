local config = require("leetcode.config")

---Where a question's statement, starter code and judge come from.
---@class lc.Provider
---@field name "leetcode"|"lintcode"
---@field filename_tag? string inserted into solution filenames, keeps them apart per provider
---@field snippet fun(question: lc.ui.Question, lang: lc.lang): string|nil
---@field run fun(question: lc.ui.Question, submit: boolean, body: lc.Interpret.body, callback: fun(item?: lc.interpreter_response, state?: string, err?: lc.err))
---@field link fun(question: lc.ui.Question): string
---@field note? fun(question: lc.ui.Question): string[]|nil lines shown under the title
---@field ready? fun(question: lc.ui.Question): string|nil why running is not possible yet
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

---Picks who serves a question: LeetCode, or LintCode for premium questions the
---account cannot open. Returns nothing, after telling the user why, when nobody can.
---@param question lc.ui.Question
---@param q lc.question_res|nil the question as LeetCode returned it
---@return lc.Provider|nil provider, lc.question_res|nil q the question as `provider` serves it
function M.open(question, q)
    if q and M.via_lintcode(q.is_paid_only) then
        local lintcode = M.lintcode()
        local twin = lintcode.fetch(question, q)
        if twin then
            return lintcode, twin
        end
        return
    end

    if not q or M.is_locked(q.is_paid_only) then
        require("leetcode.logger").warn("Question is for premium users only")
        return
    end

    return M.leetcode(), q
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
