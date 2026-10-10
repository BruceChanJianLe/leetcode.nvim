local helpers = require("tests.helpers")

describe("lintcode normalizer", function()
    local normalizer, interpreter

    before_each(function()
        helpers.setup()
        normalizer = require("leetcode.lintcode.normalizer")
        interpreter = require("leetcode.api.interpreter")
    end)

    ---A premium LeetCode question: LeetCode keeps the statement and snippets locked.
    local leetcode = {
        id = "9001",
        frontend_id = "9001",
        title = "Sum Of Pairs",
        title_slug = "sum-of-pairs",
        is_paid_only = true,
        difficulty = "Medium",
        content = vim.NIL,
        code_snippets = vim.NIL,
        testcase_list = { "[1,2]\n3" },
        meta_data = {
            name = "sumOfPairs",
            params = { { name = "nums", type = "integer[]" }, { name = "k", type = "integer" } },
        },
        stats = { acRate = "50%", totalSubmission = "10" },
        hints = {},
        topic_tags = { { name = "Array", slug = "array" } },
        similar = {},
    }

    ---A made-up LintCode problem in the shape of its API.
    local problem = {
        id = 7,
        title = "Pair Sums",
        description = "Count pairs that sum to **k**.",
        example = "**Example 1:**\n```\n[1, 2]\n3\n```",
        notice = "",
        challenge = "",
        hint = "",
        testcase_sample = "[1, 2]\n3\n",
        accept_languages = { "cpp", "python2", "python3", "js", "objc", "r" },
        accepted_rate = 40,
        total_submissions = 1234,
    }

    local mapping = { id = 7, source = "slug", confidence = "example" }

    it("builds a question from the LintCode twin, keeping LeetCode's identity", function()
        local q = normalizer.question(leetcode, problem, mapping)

        assert.are.same("sum-of-pairs", q.title_slug)
        assert.are.same("Sum Of Pairs", q.title)
        assert.are.same("Medium", q.difficulty)
        assert.truthy(q.content:find("<strong>k</strong>", 1, true))
        assert.are.same({ "[1, 2]\n3" }, q.testcase_list)
        assert.are.same(leetcode.meta_data, q.meta_data)
        assert.are.same({ acRate = "40%", totalSubmission = "1234" }, q.stats)
        assert.are.same({}, q.hints)
        assert.are.same(
            { id = 7, title = "Pair Sums", source = "slug", confidence = "example" },
            q.lintcode
        )
        assert.are.same(vim.NIL, leetcode.content, "the LeetCode question is not modified")
    end)

    it("offers the languages both sites support, with templates loaded lazily", function()
        local q = normalizer.question(leetcode, problem, mapping)

        assert.are.same({
            { lang = "C++", lang_slug = "cpp" },
            { lang = "Python", lang_slug = "python" },
            { lang = "Python3", lang_slug = "python3" },
            { lang = "JavaScript", lang_slug = "javascript" },
        }, q.code_snippets)
    end)

    it("drops LeetCode's parameter names when LintCode's inputs do not line up", function()
        local q = normalizer.question(
            leetcode,
            vim.tbl_extend("force", problem, { testcase_sample = "[1, 2]" }),
            mapping
        )

        assert.are.same({}, q.meta_data)
    end)

    it("strips the web markup LintCode wraps judge output in", function()
        assert.are.same(
            "\"a<b\" & 'c'",
            normalizer.clean("<pre><code>&quot;a&lt;b&quot; &amp; &#39;c&#39;\n</code></pre>")
        )
        assert.are.same("", normalizer.clean(vim.NIL))
    end)

    it("maps an accepted submission onto LeetCode's accepted result", function()
        local item = normalizer.submission({
            judge_finished = true,
            judge_status = "success",
            status = "Accepted",
            data_accepted_count = 12,
            data_total_count = 12,
            time_cost = 81,
            memory_cost = 5767168,
            rank_percent = 73.5,
        }, 123, "cpp")

        assert.are.same(10, item.status_code)
        assert.are.same("123", item.submission_id)
        assert.are.same("81 ms", item.status_runtime)
        assert.are.same("5.50 MB", item.status_memory)
        assert.are.same(73.5, item.runtime_percentile)
        assert.are.same("C++", item.pretty_lang)

        item = interpreter:handle_item(item)
        assert.is_true(item._.success)
        assert.is_true(item._.submission)
    end)

    it("maps failed submissions, reading camelCase results too", function()
        local item = normalizer.submission({
            judgeFinished = true,
            status = "Wrong Answer",
            dataAcceptedCount = 3,
            dataTotalCount = 12,
            input = "<pre><code>[1,2]\n3</code></pre>",
            output = "<pre><code>0</code></pre>",
            expected = "<pre><code>1</code></pre>",
        }, 124, "cpp")

        assert.are.same(11, item.status_code)
        assert.are.same(3, item.total_correct)
        assert.are.same("[1,2]\n3", item.last_testcase)
        assert.are.same("0", item.code_output)
        assert.are.same("1", item.expected_output)

        item = interpreter:handle_item(item)
        assert.is_false(item._.success)
        assert.are.same("Wrong Answer", item.status_msg)
    end)

    it("maps every judge verdict to a status code the renderer handles", function()
        assert.are.same(20, normalizer.status_code("Compile Error"))
        assert.are.same(15, normalizer.status_code("Runtime Error"))
        assert.are.same(13, normalizer.status_code("Time Limit Exceeded"))
        assert.are.same(12, normalizer.status_code("Memory Limit Exceeded"))
        assert.are.same(14, normalizer.status_code("Output Limit Exceeded"))
        assert.are.same(16, normalizer.status_code("Something New"))
    end)

    it("merges per-case test runs into one run result", function()
        local item = normalizer.run({
            {
                judge_finished = true,
                status = "Accepted",
                output = "3",
                expected = "3",
                time_cost = 5,
            },
            {
                judge_finished = true,
                status = "Wrong Answer",
                output = "1",
                expected = "2",
                stdout = "dbg",
                time_cost = 9,
            },
        }, "lintcode_runcode_1", "cpp")

        assert.are.same(10, item.status_code)
        assert.are.same("10", item.compare_result)
        assert.are.same({ "3", "1" }, item.code_answer)
        assert.are.same({ "3", "2" }, item.expected_code_answer)
        assert.are.same({ "", "dbg" }, item.std_output_list)
        assert.are.same(1, item.total_correct)
        assert.are.same(2, item.total_testcases)
        assert.are.same("9 ms", item.status_runtime)

        item = interpreter:handle_item(item)
        assert.is_false(item._.submission)
        assert.are.same("Wrong Answer", item.status_msg)
    end)

    it("ends a test run at the first error", function()
        local item = normalizer.run({
            { judge_finished = true, status = "Accepted", output = "3", expected = "3" },
            {
                judge_finished = true,
                status = "Runtime Error",
                error_message = "<pre>segfault</pre>",
            },
        }, "lintcode_runcode_2", "cpp")

        assert.are.same(15, item.status_code)
        assert.are.same("segfault", item.full_runtime_error)
        assert.are.same(2, item.total_testcases)
    end)
end)
