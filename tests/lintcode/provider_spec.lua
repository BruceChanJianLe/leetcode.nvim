local helpers = require("tests.helpers")

describe("lintcode provider", function()
    local api, token, resolver, lintcode
    local mocks = {}
    local payloads, polls, queue

    local function fake_question()
        local snapshots = {}
        return {
            lang = "cpp",
            cache = { link = "https://leetcode.com/problems/sum-of-pairs/" },
            q = {
                title_slug = "sum-of-pairs",
                lintcode = { id = 7 },
                code_snippets = { { lang = "C++", lang_slug = "cpp" } },
            },
            console = {
                testcase = {
                    testcase_len = 2,
                    snapshots = snapshots,
                    snapshot = function(_, id, data)
                        snapshots[id] = data
                    end,
                },
                result = { clear = function() end },
            },
        }
    end

    ---Runs the provider and waits for its final callback.
    local function run(question, submit, body)
        local out = { states = {} }
        lintcode.run(question, submit, body, function(item, state, err)
            if state then
                table.insert(out.states, state)
            end
            out.item, out.err = item, err
            out.done = out.done or item ~= nil or err ~= nil
        end)
        vim.wait(3000, function()
            return out.done
        end, 5)
        assert.is_true(out.done, "the run never finished")
        return out
    end

    before_each(function()
        helpers.setup()
        api = require("leetcode.lintcode.api")
        token = require("leetcode.lintcode.token")
        resolver = require("leetcode.lintcode.resolver")
        lintcode = require("leetcode.lintcode")

        payloads, polls, queue = {}, {}, {}

        helpers.mock(mocks, lintcode, "poll_interval", 1)
        helpers.mock(mocks, lintcode, "test_settle", 100)
        helpers.mock(mocks, token, "access", function()
            return "access-token"
        end)
        helpers.mock(mocks, api, "submit", function(access, file, cb)
            local payload = vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
            table.insert(payloads, { access = access, payload = payload })
            vim.schedule(function()
                cb(payload.is_test_submission and 600 or 500 + #payloads)
            end)
        end)
        helpers.mock(mocks, api, "poll", function(access, id, is_test, cb)
            table.insert(polls, { access = access, id = id, is_test = is_test })
            local result = table.remove(queue, 1)
            vim.schedule(function()
                cb(result)
            end)
        end)
    end)

    after_each(function()
        helpers.restore(mocks)
    end)

    it("submits and polls until the judge finishes", function()
        queue = {
            { judge_finished = false },
            {
                judge_finished = true,
                status = "Accepted",
                data_accepted_count = 5,
                data_total_count = 5,
                time_cost = 10,
                memory_cost = 1048576,
            },
        }

        local out = run(fake_question(), true, { lang = "cpp", typed_code = "int x;" })

        assert.is_nil(out.err)
        assert.are.same({
            access = "access-token",
            payload = {
                is_test_submission = false,
                problem_id = 7,
                language = "cpp",
                source = 99,
                code = "int x;",
            },
        }, payloads[1])
        assert.are.same({ access = "access-token", id = 501, is_test = false }, polls[1])
        assert.are.same({ "STARTED" }, out.states)
        assert.are.same(10, out.item.status_code)
        assert.is_true(out.item._.success)
        assert.is_true(out.item._.submission)
    end)

    it("runs each testcase on its own and ignores results left over in the judge slot", function()
        queue = {
            -- case 1: the slot still shows an older run, then the judge picks ours up
            {
                judge_finished = true,
                status = "Accepted",
                input = "<pre><code>[9]\n9</code></pre>",
            },
            { judge_finished = false },
            {
                judge_finished = true,
                status = "Accepted",
                input = "<pre><code>[1,2]\n3</code></pre>",
                output = "<pre><code>3</code></pre>",
                expected = "<pre><code>3</code></pre>",
            },
            -- case 2: the slot shows case 1 until the judge restarts
            { judge_finished = true, status = "Accepted", input = "[1,2]\n3" },
            { judge_finished = false },
            {
                judge_finished = true,
                status = "Wrong Answer",
                input = "[4]\n5",
                output = "1",
                expected = "2",
            },
        }

        local question = fake_question()
        local out = run(question, false, {
            lang = "cpp",
            typed_code = "\n\nint x;",
            data_input = "[1,2]\n3\n[4]\n5",
        })

        assert.is_nil(out.err)
        assert.are.same(2, #payloads)
        assert.are.same("[1,2]\n3", payloads[1].payload.input)
        assert.are.same("[4]\n5", payloads[2].payload.input)
        assert.is_true(payloads[2].payload.is_test_submission)
        assert.is_true(polls[1].is_test)

        local item = out.item
        assert.are.same(10, item.status_code)
        assert.are.same("10", item.compare_result)
        assert.are.same({ "3", "1" }, item.code_answer)
        assert.is_false(item._.submission)
        assert.are.same(
            { test_case = "[1,2]\n3\n[4]\n5" },
            question.console.testcase.snapshots[item.submission_id]
        )
    end)

    it("trusts a finished result for the same input after the settle delay", function()
        lintcode.test_settle = 0
        queue = {
            {
                judge_finished = true,
                status = "Accepted",
                input = "[1,2]\n3",
                output = "3",
                expected = "3",
            },
        }

        local question = fake_question()
        question.console.testcase.testcase_len = 2
        local out = run(question, false, { lang = "cpp", typed_code = "", data_input = "[1,2]\n3" })

        assert.are.same("1", out.item.compare_result)
    end)

    it("stops a test run at a compile error", function()
        queue = {
            { judge_finished = false },
            {
                judge_finished = true,
                status = "Compile Error",
                compile_info = "<pre>oops</pre>",
                input = "[1,2]\n3",
            },
        }

        local out = run(fake_question(), false, {
            lang = "cpp",
            typed_code = "",
            data_input = "[1,2]\n3\n[4]\n5",
        })

        assert.are.same(1, #payloads)
        assert.are.same(20, out.item.status_code)
        assert.are.same("oops", out.item.full_compile_error)
    end)

    it("reports a missing token and unsupported languages without calling LintCode", function()
        helpers.mock(mocks, token, "access", function()
            return nil, { msg = "No LintCode token found" }
        end)
        assert.are.same(
            "No LintCode token found",
            run(fake_question(), true, { lang = "cpp", typed_code = "" }).err.msg
        )

        assert.are.same(
            "LintCode does not support `bash`",
            run(fake_question(), true, { lang = "bash", typed_code = "" }).err.msg
        )
        assert.are.same(0, #payloads)
    end)

    it("gives up when judging never finishes", function()
        helpers.mock(mocks, lintcode, "poll_timeout", 0)
        queue = { { judge_finished = false }, { judge_finished = false } }

        local out = run(fake_question(), true, { lang = "cpp", typed_code = "" })

        assert.are.same("LintCode: judging timed out", out.err.msg)
    end)

    it("splits the console testcases into one input per case", function()
        assert.are.same({ "a\nb", "c\nd" }, lintcode.split_cases("a\nb\n\nc\nd\n", 2))
        assert.are.same({ "a\nb\nc" }, lintcode.split_cases("a\nb\nc", 0))
        assert.are.same({}, lintcode.split_cases("", 2))
    end)

    it("loads a starter template once per language", function()
        local fetched = 0
        helpers.mock(mocks, api, "template", function(id, language)
            fetched = fetched + 1
            return ("// %d %s"):format(id, language)
        end)
        local question = fake_question()

        assert.are.same("// 7 cpp", lintcode.snippet(question, "cpp"))
        assert.are.same("// 7 cpp", lintcode.snippet(question, "cpp"))
        assert.are.same(1, fetched)
        assert.is_nil(lintcode.snippet(question, "rust"))
    end)

    it("links the LintCode twin", function()
        local question = fake_question()
        question.q.lintcode = { id = 920 }

        assert.are.same("https://www.lintcode.com/problem/920/", lintcode.link(question))
    end)

    it("does not track solved state for LintCode twins", function()
        local question = fake_question()

        lintcode.record_status(question, "ac")

        assert.is_nil(lintcode.status(question))
    end)

    it("serves the twin's statement for a premium question", function()
        helpers.mock(mocks, resolver, "resolve", function()
            return {
                mapping = { id = 7 },
                problem = {
                    id = 7,
                    title = "Pair Sums",
                    description = "Hi",
                    accept_languages = { "cpp" },
                },
            }
        end)

        local q =
            lintcode.fetch(fake_question(), { title_slug = "sum-of-pairs", title = "Sum Of Pairs" })

        assert.are.same("<p>Hi</p>", q.content)
        assert.are.same(7, q.lintcode.id)
    end)

    it("refuses a premium question without a free twin", function()
        helpers.mock(mocks, resolver, "resolve", function()
            return {}
        end)
        assert.is_nil(lintcode.fetch(fake_question(), { title_slug = "x", title = "X" }))

        helpers.mock(mocks, resolver, "resolve", function()
            return { mapping = { id = 461 }, err = { code = 1001, msg = "VIP" } }
        end)
        assert.is_nil(lintcode.fetch(fake_question(), { title_slug = "x", title = "X" }))
    end)
end)
