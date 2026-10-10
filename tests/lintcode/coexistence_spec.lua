local helpers = require("tests.helpers")

-- LeetCode and LintCode credentials live side by side: the LeetCode cookie alone
-- keeps everything working, and neither login touches the other.
describe("LeetCode and LintCode together", function()
    -- one storage for the whole file: the cookie module binds its path when loaded
    local config = helpers.setup()

    local providers = require("leetcode.provider")
    local cookie = require("leetcode.cache.cookie")
    local auth = require("leetcode.api.auth")
    local token = require("leetcode.lintcode.token")
    local api = require("leetcode.lintcode.api")
    local lintcode = require("leetcode.lintcode")
    local Runner = require("leetcode.runner")
    local log = require("leetcode.logger")
    local curl = require("plenary.curl")

    local leetcode_cookie = "csrftoken=csrf-1; LEETCODE_SESSION=session-1"
    local lintcode_jwt = helpers.jwt("lintcode")

    local mocks = {}
    local fetched, warned

    local free = { title_slug = "two-sum", is_paid_only = false }
    local premium = { title_slug = "meeting-rooms", is_paid_only = true }
    local question = { cache = { link = "https://leetcode.com/problems/meeting-rooms/" } }

    before_each(function()
        config.auth = { is_signed_in = true, is_premium = false }
        cookie.delete()
        token.delete()
        fetched, warned = {}, {}

        helpers.mock(mocks, auth, "user", function()
            return {}
        end)
        helpers.mock(mocks, api, "refresh_token", function()
            return { access = "lintcode-access", access_lifetime = 500 }
        end)
        helpers.mock(mocks, api, "profile", function()
            return { profile = {} }
        end)
        helpers.mock(mocks, lintcode, "fetch", function(_, q)
            table.insert(fetched, q.title_slug)
            return vim.tbl_extend("force", q, { lintcode = { id = 920 } })
        end)
        helpers.mock(mocks, log, "warn", function(msg)
            table.insert(warned, msg)
        end)

        assert.is_nil(cookie.set(leetcode_cookie))
    end)

    after_each(function()
        helpers.restore(mocks)
    end)

    describe("with only the LeetCode cookie", function()
        it("opens free questions on LeetCode exactly as before", function()
            local provider, q = providers.open(question, free)

            assert.are.same("leetcode", provider.name)
            assert.are.equal(free, q)
            assert.are.same({}, fetched)
            assert.is_true(Runner:init({ provider = provider }):ready())
        end)

        it("still opens premium questions on their LintCode twin", function()
            assert.is_nil(token.read())

            local provider, q = providers.open(question, premium)

            assert.are.same("lintcode", provider.name)
            assert.are.same(920, q.lintcode.id)
            assert.are.same({ "meeting-rooms" }, fetched)
        end)

        it("asks to log in to LintCode instead of failing a run", function()
            local runner = Runner:init({ provider = providers.lintcode() })

            assert.is_false(runner:ready())
            assert.are.same(1, #warned)
            assert.truthy(warned[1]:find("Log in to LintCode", 1, true))
            assert.truthy(warned[1]:find(":Leet lintcode login", 1, true))
            assert.is_false(Runner.running)
        end)
    end)

    describe("with both credentials", function()
        before_each(function()
            assert.is_nil(token.set(lintcode_jwt))
        end)

        it("stores them separately", function()
            assert.are.same(leetcode_cookie, cookie.read())
            assert.are.same(lintcode_jwt, token.read())
            assert.is_true(Runner:init({ provider = providers.lintcode() }):ready())
        end)

        it("keeps the LintCode token when the LeetCode cookie is deleted", function()
            cookie.delete()

            assert.is_nil(cookie.get())
            assert.are.same(lintcode_jwt, token.read())
        end)

        it("keeps the LeetCode cookie when the LintCode token is deleted", function()
            token.delete()

            assert.is_nil(token.read())
            assert.are.same(leetcode_cookie, cookie.read())
        end)

        it("keeps both when a LintCode login is refused", function()
            assert.truthy(token.set("not a token"))

            assert.are.same(lintcode_jwt, token.read())
            assert.are.same(leetcode_cookie, cookie.read())
        end)

        it("sends each site only its own credential", function()
            local sent = {}
            local function capture(url, params)
                table.insert(sent, { url = url, headers = params.headers })
                return {
                    exit = 0,
                    status = 200,
                    headers = {},
                    body = "{\"success\": true, \"code\": 200, \"data\": {}}",
                }
            end
            helpers.mock(mocks, curl, "get", capture)

            api.request("get", api.base .. "/new/api/accounts/profile/", {
                token = token.access(),
            })
            require("leetcode.api.utils").get("/api/problems/algorithms/")

            local to_lintcode, to_leetcode = sent[1].headers, sent[2].headers
            assert.truthy(sent[1].url:find("lintcode.com", 1, true))
            assert.are.same("Bearer lintcode-access", to_lintcode["Authorization"])
            assert.is_nil(to_lintcode["Cookie"])
            assert.is_nil(to_lintcode["x-csrftoken"])

            assert.truthy(sent[2].url:find("leetcode.com", 1, true))
            assert.are.same(leetcode_cookie, to_leetcode["Cookie"])
            assert.are.same("csrf-1", to_leetcode["x-csrftoken"])
            assert.is_nil(to_leetcode["Authorization"])
        end)

        -- last: the cookie module caches the parsed cookie per second of file mtime
        it("keeps both when the LeetCode cookie is replaced", function()
            local fresh = "csrftoken=csrf-2; LEETCODE_SESSION=session-2"
            assert.is_nil(cookie.set(fresh))

            assert.are.same(fresh, cookie.read())
            assert.are.same(lintcode_jwt, token.read())
        end)
    end)

    describe("with LeetCode Premium", function()
        it("keeps premium questions on LeetCode", function()
            config.auth.is_premium = true

            local provider, q = providers.open(question, premium)

            assert.are.same("leetcode", provider.name)
            assert.are.equal(premium, q)
            assert.are.same({}, fetched)
            assert.is_false(providers.is_locked(true))
        end)
    end)

    it("keeps premium questions locked when LintCode is disabled", function()
        config.user.lintcode.enabled = false

        local provider = providers.open(question, premium)

        config.user.lintcode.enabled = true
        assert.is_nil(provider)
        assert.are.same({ "Question is for premium users only" }, warned)
        assert.are.same({}, fetched)
    end)
end)
