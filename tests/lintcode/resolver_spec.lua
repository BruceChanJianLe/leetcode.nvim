local helpers = require("tests.helpers")

describe("lintcode resolver", function()
    local api, resolver
    local mocks = {}
    local calls

    ---@param problems table<integer, table|lc.err>
    local function serve(problems)
        helpers.mock(mocks, api, "problem", function(id)
            table.insert(calls, "problem:" .. id)
            local p = problems[id]
            if p and p.msg then
                return nil, p
            end
            return p, p == nil and { code = 1004, msg = "LintCode: Object not found" } or nil
        end)
    end

    local q = {
        title = "Meeting Rooms II",
        title_slug = "meeting-rooms-ii",
        testcase_list = { "[[0,30],[5,10]]" },
        meta_data = { params = { { name = "intervals", type = "integer[][]" } } },
    }

    before_each(function()
        helpers.setup()
        api = require("leetcode.lintcode.api")
        resolver = require("leetcode.lintcode.resolver")
        calls = {}

        helpers.mock(mocks, api, "resolve_slug", function(slug)
            table.insert(calls, "slug:" .. slug)
        end)
        helpers.mock(mocks, api, "search", function(query)
            table.insert(calls, "search:" .. query)
            return {}
        end)
    end)

    after_each(function()
        helpers.restore(mocks)
    end)

    it("normalizes titles for exact comparison", function()
        assert.are.same("meeting rooms 2", resolver.norm_title("Meeting Rooms II"))
        assert.are.same("meeting rooms 2", resolver.norm_title("meeting-rooms 2"))
        assert.are.same(
            "two sum iii data structure design",
            resolver.norm_title("Two Sum III - Data structure design")
        )
        assert.are.same("dont stop and go", resolver.norm_title("Don't Stop & Go"))
        assert.are.same("lonely pixel 1", resolver.norm_title("Lonely Pixel I"))
    end)

    it("matches a unique exact title only", function()
        helpers.mock(mocks, api, "search", function()
            return {
                { problem_id = 919, en_title = "Meeting Rooms II" },
                { problem_id = 920, en_title = "Meeting Rooms" },
                { problem_id = 919, title = "Meeting Rooms II" },
            }
        end)
        assert.are.same({ id = 919, source = "title" }, resolver.by_title("Meeting Rooms II"))

        helpers.mock(mocks, api, "search", function()
            return {
                { problem_id = 1, en_title = "Meeting Rooms II" },
                { problem_id = 2, en_title = "Meeting Rooms 2" },
            }
        end)
        assert.is_nil(resolver.by_title("Meeting Rooms II"))
    end)

    it("prefers a stored mapping over network lookups", function()
        resolver.set(q.title_slug, { id = 42, source = "user" })
        serve({ [42] = { id = 42, testcase_sample = "[[0,30],[5,10]]" } })

        local res = resolver.resolve(q)

        assert.are.same({ id = 42, source = "user", confidence = "example" }, res.mapping)
        assert.are.same({ "problem:42" }, calls)
    end)

    it("follows the slug redirect before searching titles", function()
        helpers.mock(mocks, api, "resolve_slug", function(slug)
            table.insert(calls, "slug:" .. slug)
            return 919
        end)
        serve({ [919] = { id = 919, testcase_sample = "[[1,2]]" } })

        local res = resolver.resolve(q)

        assert.are.same({ id = 919, source = "slug", confidence = "signature" }, res.mapping)
        assert.are.same({ "slug:meeting-rooms-ii", "problem:919" }, calls)
        assert.are.same({ id = 919, source = "slug" }, resolver.get(q.title_slug))
    end)

    it("skips a redirect to a deleted problem and falls back to the title", function()
        helpers.mock(mocks, api, "resolve_slug", function()
            return 3796
        end)
        helpers.mock(mocks, api, "search", function()
            return { { problem_id = 919, en_title = "Meeting Rooms II" } }
        end)
        serve({ [919] = { id = 919, testcase_sample = "" } })

        local res = resolver.resolve(q)

        assert.are.same({ id = 919, source = "title", confidence = "none" }, res.mapping)
        assert.is_nil(res.err)
    end)

    it("stops at a twin that is VIP-only on LintCode", function()
        helpers.mock(mocks, api, "resolve_slug", function()
            return 461
        end)
        serve({ [461] = { code = 1001, msg = "LintCode: You have no permission to access" } })

        local res = resolver.resolve(q)

        assert.are.same(461, res.mapping.id)
        assert.are.same(1001, res.err.code)
        assert.is_nil(res.problem)
        assert.is_nil(resolver.get(q.title_slug))
    end)

    it("reports no twin when nothing matches", function()
        local res = resolver.resolve(q)

        assert.is_nil(res.mapping)
        assert.is_nil(res.err)
        assert.are.same({ "slug:meeting-rooms-ii", "search:Meeting Rooms II" }, calls)
    end)

    it("surfaces network errors instead of claiming there is no twin", function()
        helpers.mock(mocks, api, "resolve_slug", function()
            return nil, { msg = "LintCode: curl failed" }
        end)
        helpers.mock(mocks, api, "search", function()
            return nil, { msg = "LintCode: curl failed" }
        end)

        local res = resolver.resolve(q)

        assert.are.same("LintCode: curl failed", res.err.msg)
    end)

    it("stores ids and sources only", function()
        resolver.set("two-sum", { id = 56, source = "title", confidence = "example" })

        assert.are.same({ ["two-sum"] = { id = 56, source = "title" } }, resolver.read())
        assert.is_true(resolver.unset("two-sum"))
        assert.is_false(resolver.unset("two-sum"))
    end)

    it("grades how well a twin matches LeetCode's public signature and examples", function()
        assert.are.same("example", resolver.verify(q, { testcase_sample = "[[0, 30], [5, 10]]\n" }))
        assert.are.same("signature", resolver.verify(q, { testcase_sample = "[[9,9]]" }))
        assert.are.same("none", resolver.verify(q, { testcase_sample = "[[9,9]]\n3" }))
        assert.are.same(
            "none",
            resolver.verify({ testcase_list = vim.NIL }, { testcase_sample = vim.NIL })
        )
    end)
end)
