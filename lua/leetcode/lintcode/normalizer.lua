local markdown = require("leetcode.lintcode.markdown")
local langs = require("leetcode.lintcode.langs")
local utils = require("leetcode.utils")

---Turns LintCode responses into the shapes the LeetCode UI already renders.
---@class lc.lintcode.Normalizer
local N = {}

---@param value any
---@return string|nil
local function str(value)
    if type(value) == "string" then
        return value
    elseif type(value) == "number" then
        return tostring(value)
    end
end

---@param value any
---@return number|nil
local function num(value)
    return type(value) == "number" and value or tonumber(str(value) or "")
end

---LintCode wraps judge fields in `<pre><code>` markup and HTML entities for its web UI.
---@param value any
---@return string
function N.clean(value)
    local text = str(value) or ""
    text = text:gsub("<[^>]->", "")
    text = text:gsub("&quot;", "\"")
        :gsub("&#39;", "'")
        :gsub("&#x27;", "'")
        :gsub("&lt;", "<")
        :gsub("&gt;", ">")
        :gsub("&nbsp;", " ")
        :gsub("&amp;", "&")
    return vim.trim(text)
end

---@param problem table LintCode problem
---@return string[]
function N.testcases(problem)
    local sample = str(problem.testcase_sample)
    if not sample or vim.trim(sample) == "" then
        return {}
    end

    local lines = vim.tbl_map(vim.trim, vim.split(vim.trim(sample), "\n"))
    return { table.concat(lines, "\n") }
end

---@param problem table LintCode problem
---@return lc.QuestionCodeSnippet[]
function N.snippets(problem)
    local snippets = {}
    local accepted = type(problem.accept_languages) == "table" and problem.accept_languages or {}

    for _, name in ipairs(accepted) do
        local slug = langs.from_lintcode(name)
        local lang = slug and utils.get_lang(slug)
        if lang then
            -- `code` is fetched lazily, LintCode serves one template per request
            table.insert(snippets, { lang = lang.lang, lang_slug = lang.slug })
        end
    end

    return snippets
end

---@param q lc.question_res LeetCode question
---@param problem table LintCode problem
---@param mapping lc.lintcode.Mapping
---@return lc.question_res
function N.question(q, problem, mapping)
    local nq = vim.deepcopy(q)

    nq.content = markdown.problem(problem)
    nq.translated_content = nil
    nq.code_snippets = N.snippets(problem)
    nq.testcase_list = N.testcases(problem)

    -- LeetCode's parameter names label LintCode's inputs only when the counts agree
    local md = type(q.meta_data) == "table" and q.meta_data or {}
    local params = type(md.params) == "table" and #md.params or 0
    local lines = nq.testcase_list[1] and #vim.split(nq.testcase_list[1], "\n") or 0
    nq.meta_data = params > 0 and params == lines and md or {}

    nq.stats = {
        acRate = ("%s%%"):format(str(problem.accepted_rate) or "?"),
        totalSubmission = str(problem.total_submissions) or "?",
    }

    local hint = str(problem.hint)
    nq.hints = hint and vim.trim(hint) ~= "" and { hint } or {}
    if type(nq.topic_tags) ~= "table" then
        nq.topic_tags = {}
    end
    if type(nq.similar) ~= "table" then
        nq.similar = {}
    end

    nq.lintcode = { id = mapping.id }

    return nq
end

---LintCode verdicts to LeetCode status codes, so the result renderer is reused as is.
local status_codes = {
    ["accepted"] = 10,
    ["wrong answer"] = 11,
    ["memory limit exceeded"] = 12,
    ["time limit exceeded"] = 13,
    ["output limit exceeded"] = 14,
    ["runtime error"] = 15,
    ["compile error"] = 20,
    ["compilation error"] = 20,
}

---Judge results come back in snake_case or camelCase depending on the endpoint version.
---@param result table
---@return table
function N.snake(result)
    local out = {}
    for key, value in pairs(result) do
        if type(key) == "string" then
            local snake = key:gsub("(%u)", function(c)
                return "_" .. c:lower()
            end)
            if out[snake] == nil then
                out[snake] = value
            end
        end
    end
    return out
end

---@param result table LintCode judge result
---@return string
function N.status(result)
    local status = str(result.status) or ""
    if status == "" and str(result.judge_status) == "success" then
        status = "Accepted"
    end
    return status
end

---@param status string
---@return integer
function N.status_code(status)
    return status_codes[status:lower()] or 16
end

---@param bytes any
---@return string
local function memory(bytes)
    local n = num(bytes)
    if not n then
        return "0 MB"
    end
    return ("%.2f MB"):format(n / 1024 / 1024)
end

---@param result table LintCode judge result
---@return boolean
function N.finished(result)
    return N.snake(result).judge_finished == true
end

---A finished submission as an interpreter response.
---@param result table LintCode judge result
---@param id integer submission id
---@param lang lc.lang
---@return lc.interpreter_response
function N.submission(result, id, lang)
    result = N.snake(result)
    local status = N.status(result)
    local code = N.status_code(status)
    local time = num(result.time_cost) or 0
    local input = N.clean(result.input)
    local rank = num(result.rank_percent)

    return {
        status_code = code,
        status_msg = status ~= "" and status or "Unknown",
        submission_id = tostring(id),
        compare_result = code == 10 and "1" or "0",
        total_correct = num(result.data_accepted_count) or 0,
        total_testcases = num(result.data_total_count) or 0,
        display_runtime = tostring(time),
        status_runtime = ("%d ms"):format(time),
        status_memory = memory(result.memory_cost),
        runtime_percentile = rank,
        pretty_lang = (utils.get_lang(lang) or {}).lang or lang,
        input = input,
        last_testcase = input,
        code_output = N.clean(result.output),
        expected_output = N.clean(result.expected),
        std_output = N.clean(result.stdout),
        full_compile_error = N.clean(result.compile_info),
        full_runtime_error = N.clean(result.error_message),
    }
end

---Test runs judge one input at a time; this merges them into one "run code" response.
---@param results table[] LintCode judge results, one per testcase
---@param id string run id, kept for `Testcase:by_id`
---@param lang lc.lang
---@return lc.interpreter_response
function N.run(results, id, lang)
    local item = {
        status_code = 10,
        submission_id = id,
        code_answer = {},
        expected_code_answer = {},
        std_output_list = {},
        compare_result = "",
        total_correct = 0,
        total_testcases = #results,
        pretty_lang = (utils.get_lang(lang) or {}).lang or lang,
    }

    local max_time = 0
    for i, raw in ipairs(results) do
        local result = N.snake(raw)
        local status = N.status(result)
        local code = N.status_code(status)
        max_time = math.max(max_time, num(result.time_cost) or 0)

        if code ~= 10 and code ~= 11 then
            -- compile/runtime/limit errors end the run, like on LeetCode
            item.status_code = code
            item.status_msg = status ~= "" and status or "Unknown"
            item.full_compile_error = N.clean(result.compile_info)
            item.full_runtime_error = N.clean(result.error_message)
            item.std_output_list = { N.clean(result.stdout) }
            item.total_testcases = i
            break
        end

        local passed = code == 10
        item.code_answer[i] = N.clean(result.output)
        item.expected_code_answer[i] = N.clean(result.expected)
        item.std_output_list[i] = N.clean(result.stdout)
        item.compare_result = item.compare_result .. (passed and "1" or "0")
        item.total_correct = item.total_correct + (passed and 1 or 0)
    end

    item.status_runtime = ("%d ms"):format(max_time)
    return item
end

return N
