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

    local function map_file()
        return require("leetcode.config").storage.cache:joinpath("lintcode_map.json")
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
        assert.are.same({ id = 919 }, resolver.by_title("Meeting Rooms II"))

        helpers.mock(mocks, api, "search", function()
            return {
                { problem_id = 1, en_title = "Meeting Rooms II" },
                { problem_id = 2, en_title = "Meeting Rooms 2" },
            }
        end)
        assert.is_nil(resolver.by_title("Meeting Rooms II"))
    end)

    it("remembers a resolved twin and skips network lookups next time", function()
        helpers.mock(mocks, api, "resolve_slug", function(slug)
            table.insert(calls, "slug:" .. slug)
            return 42
        end)
        serve({ [42] = { id = 42 } })
        resolver.resolve(q)
        calls = {}

        local res = resolver.resolve(q)

        assert.are.same({ id = 42 }, res.mapping)
        assert.are.same({ "problem:42" }, calls)
    end)

    it("follows the slug redirect before searching titles", function()
        helpers.mock(mocks, api, "resolve_slug", function(slug)
            table.insert(calls, "slug:" .. slug)
            return 919
        end)
        serve({ [919] = { id = 919, testcase_sample = "[[1,2]]" } })

        local res = resolver.resolve(q)

        assert.are.same({ id = 919 }, res.mapping)
        assert.are.same({ "slug:meeting-rooms-ii", "problem:919" }, calls)
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

        assert.are.same({ id = 919 }, res.mapping)
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
        assert.is_false(map_file():exists())
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

    it("stores LintCode ids only", function()
        helpers.mock(mocks, api, "resolve_slug", function()
            return 919
        end)
        serve({ [919] = { id = 919, title = "Meeting Rooms II", description = "secret" } })

        resolver.resolve(q)

        assert.are.same({ [q.title_slug] = { id = 919 } }, vim.json.decode(map_file():read()))
    end)
end)
