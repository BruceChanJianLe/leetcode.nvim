local config = require("leetcode.config")
local interpreter = require("leetcode.api.interpreter")
local problemlist = require("leetcode.cache.problemlist")

---@type lc.Provider
local LeetCode = {
    name = "leetcode",
}

function LeetCode.snippet(question, lang)
    local snippets = question.q.code_snippets ~= vim.NIL and question.q.code_snippets or {}
    local snip = vim.tbl_filter(function(snip)
        return snip.lang_slug == lang
    end, snippets)[1]

    return snip and snip.code
end

function LeetCode.run(question, submit, body, callback)
    local file = config.storage.cache:joinpath("body")
    file:write(vim.json.encode(body), "w")

    interpreter.run(submit, question, file:absolute(), callback)
end

function LeetCode.link(question)
    return question.cache.link
end

function LeetCode.status(question)
    return question.cache.status
end

function LeetCode.record_status(question, status)
    problemlist.change_status(question.q.title_slug, status)
    if status == "ac" then
        config.stats.update_streak()
    end
end

return LeetCode
