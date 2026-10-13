local api = require("leetcode.lintcode.api")
local langs = require("leetcode.lintcode.langs")
local normalizer = require("leetcode.lintcode.normalizer")
local resolver = require("leetcode.lintcode.resolver")
local token = require("leetcode.lintcode.token")
local config = require("leetcode.config")
local log = require("leetcode.logger")

---Serves LeetCode premium problems from their free LintCode twin.
---@class lc.lintcode.Provider : lc.Provider
local LintCode = {
    name = "lintcode",
    filename_tag = "lintcode",

    -- `source` the LintCode web client sends for submissions outside courses and exams
    source = 99,
    poll_interval = 1000,
    poll_timeout = 60,
    -- a test run reuses one judge slot per problem, which keeps showing the previous
    -- verdict until the judge picks the new run up; the web editor waits this long too
    test_settle = 8,
}

---Resolves the LintCode twin of a premium LeetCode question.
---@param question lc.ui.Question
---@param q lc.question_res LeetCode question, its content is locked
---@return lc.question_res|nil
function LintCode.fetch(question, q)
    local res = resolver.resolve(q)
    if res.problem then
        return normalizer.question(q, res.problem, res.mapping)
    end

    local link = question.cache.link or ("https://leetcode.com/problems/%s/"):format(q.title_slug)
    if res.err and res.err.code == 1001 then
        log.warn(
            ("Question is for premium users only, and its LintCode twin %d is VIP-only too.\n%s"):format(
                res.mapping.id,
                link
            )
        )
    elseif res.err then
        log.error("Could not load the LintCode twin: " .. (res.err.msg or "unknown error"))
    else
        local msg = "Question is for premium users only and has no free LintCode twin."
        log.warn(("%s\nOpen it in the browser: %s"):format(msg, link))
    end
end

function LintCode.snippet(question, lang)
    local snip = vim.tbl_filter(function(snip)
        return snip.lang_slug == lang
    end, question.q.code_snippets or {})[1]
    if not snip then
        return
    end

    if not snip.code then
        local code, err = api.template(question.q.lintcode.id, langs.to_lintcode(lang))
        if not code then
            return log.err(err)
        end
        snip.code = code
    end

    return snip.code
end

function LintCode.link(question)
    return ("%s/problem/%d/"):format(api.web, question.q.lintcode.id)
end

---Reading needs no account; running and submitting do.
function LintCode.ready()
    if not token.read() then
        return "Log in to LintCode to run and submit premium questions: `:Leet lintcode login`"
    end
end

function LintCode.status() end

function LintCode.record_status() end

---@param payload table
---@param callback fun(id: integer|nil, err: lc.err)
local function send(payload, callback)
    local access, err = token.access()
    if not access then
        return callback(nil, err)
    end

    local file = config.storage.cache:joinpath("lintcode_body")
    file:write(vim.json.encode(payload), "w")
    api.submit(access, file:absolute(), callback)
end

---@class lc.lintcode.Poll
---@field id integer
---@field is_test boolean
---@field accept fun(result: table, elapsed: number, seen_running: boolean): boolean
---@field on_state fun(state: string)
---@field on_done fun(result: table|nil, err: lc.err)

---@param opts lc.lintcode.Poll
local function poll(opts)
    local started = vim.loop.now()
    local seen_running = false

    local function tick()
        local access, err = token.access()
        if not access then
            return opts.on_done(nil, err)
        end

        api.poll(access, opts.id, opts.is_test, function(result, perr)
            if perr then
                return opts.on_done(nil, perr)
            end

            local elapsed = (vim.loop.now() - started) / 1000
            if result and normalizer.finished(result) then
                if opts.accept(result, elapsed, seen_running) then
                    return opts.on_done(result)
                end
            else
                seen_running = true
            end

            if elapsed > LintCode.poll_timeout then
                return opts.on_done(nil, { msg = "LintCode: judging timed out" })
            end

            opts.on_state("STARTED")
            vim.defer_fn(tick, LintCode.poll_interval)
        end)
    end

    vim.defer_fn(tick, LintCode.poll_interval)
end

---@param item lc.interpreter_response
---@return lc.interpreter_response
local function finish(item)
    return require("leetcode.api.interpreter"):handle_item(item)
end

---@param question lc.ui.Question
---@param language string LintCode language
---@param body lc.Interpret.body
---@param callback function
local function submit(question, language, body, callback)
    send({
        is_test_submission = false,
        problem_id = question.q.lintcode.id,
        language = language,
        source = LintCode.source,
        code = body.typed_code,
    }, function(id, err)
        if not id then
            return callback(nil, nil, err)
        end

        question.console.result:clear()
        poll({
            id = id,
            is_test = false,
            accept = function()
                return true
            end,
            on_state = function(state)
                callback(nil, state)
            end,
            on_done = function(result, perr)
                if not result then
                    return callback(nil, nil, perr)
                end
                callback(finish(normalizer.submission(result, id, body.lang)))
            end,
        })
    end)
end

---Splits the console's testcases into one input per case.
---@param input string
---@param size integer lines per case
---@return string[]
function LintCode.split_cases(input, size)
    local lines = vim.tbl_filter(function(line)
        return vim.trim(line) ~= ""
    end, vim.split(input or "", "\n"))

    size = (size and size > 0) and size or #lines
    local cases = {}
    for i = 1, #lines, size do
        table.insert(cases, table.concat(lines, "\n", i, math.min(i + size - 1, #lines)))
    end
    return cases
end

---@param question lc.ui.Question
---@param language string LintCode language
---@param body lc.Interpret.body
---@param callback function
local function test(question, language, body, callback)
    local cases = LintCode.split_cases(body.data_input, question.console.testcase.testcase_len)
    if vim.tbl_isempty(cases) then
        return callback(nil, nil, { msg = "No testcases to run" })
    end

    local run_id = ("lintcode_runcode_%d"):format(vim.loop.hrtime())
    question.console.testcase:snapshot(run_id, { test_case = table.concat(cases, "\n") })
    question.console.result:clear()

    local results = {}
    local function done()
        callback(finish(normalizer.run(results, run_id, body.lang)))
    end

    local function step(i)
        if i > #cases then
            return done()
        end

        local input = cases[i]
        send({
            is_test_submission = true,
            problem_id = question.q.lintcode.id,
            language = language,
            source = LintCode.source,
            input = input,
            code = body.typed_code,
        }, function(id, err)
            if not id then
                return callback(nil, nil, err)
            end

            poll({
                id = id,
                is_test = true,
                accept = function(result, elapsed, seen_running)
                    local echoed = normalizer.clean(normalizer.snake(result).input)
                    if echoed ~= "" and echoed:gsub("%s+", "") ~= input:gsub("%s+", "") then
                        return false
                    end
                    return seen_running or elapsed >= LintCode.test_settle
                end,
                on_state = function(state)
                    callback(nil, state)
                end,
                on_done = function(result, perr)
                    if not result then
                        return callback(nil, nil, perr)
                    end

                    results[i] = result
                    local code = normalizer.status_code(normalizer.status(normalizer.snake(result)))
                    if code ~= 10 and code ~= 11 then
                        return done()
                    end
                    step(i + 1)
                end,
            })
        end)
    end

    step(1)
end

function LintCode.run(question, is_submit, body, callback)
    local language = langs.to_lintcode(body.lang)
    if not language then
        return callback(nil, nil, { msg = ("LintCode does not support `%s`"):format(body.lang) })
    end

    if is_submit then
        submit(question, language, body, callback)
    else
        test(question, language, body, callback)
    end
end

return LintCode
