local helpers = require("tests.helpers")

describe("lintcode token", function()
    local api, token, config
    local mocks = {}
    local refreshed

    before_each(function()
        config = helpers.setup()
        api = require("leetcode.lintcode.api")
        token = require("leetcode.lintcode.token")
        token.reset()
        refreshed = {}

        helpers.mock(mocks, api, "refresh_token", function(refresh)
            table.insert(refreshed, refresh)
            return { access = "access-" .. #refreshed, access_lifetime = 500 }
        end)
        helpers.mock(mocks, api, "profile", function()
            return { profile = { is_vip = false } }
        end)
    end)

    after_each(function()
        helpers.restore(mocks)
    end)

    it("accepts the raw refresh token from local storage", function()
        local jwt = helpers.jwt("eyJ0b2tlbl90eXBlIjoicmVmcmVzaCJ9")

        assert.are.same(jwt, token.parse(jwt))
        assert.are.same(jwt, token.parse(("  %s\n"):format(jwt)))
        assert.is_nil(token.parse("Bearer " .. jwt))
        assert.is_nil(token.parse(("\"%s\""):format(jwt)))
        assert.is_nil(token.parse("LEETCODE_SESSION=abc; csrftoken=def"))
        assert.is_nil(token.parse(""))
    end)

    it("accepts LintCode's cookie in place of the token", function()
        local jwt = helpers.jwt("fromcookie")

        assert.are.same(jwt, token.parse(("access_lifetime=500; refresh=%s; access=x"):format(jwt)))
        assert.are.same(jwt, token.parse(("Cookie: sid=1; refresh=%s"):format(jwt)))
        assert.are.same(jwt, token.parse(("refresh=%s"):format(jwt)))
        assert.is_nil(token.parse(("access=%s; sid=1"):format(jwt)))
        assert.is_nil(token.parse(("no_refresh=%s"):format(jwt)))
    end)

    it("refuses a short-lived access token with a hint", function()
        local err = token.set(helpers.jwt_with({ token_type = "access" }))

        assert.truthy(err:find("access token", 1, true))
        assert.are.same({}, refreshed)
        assert.is_nil(token.read())
    end)

    it("explains where to find the token when the paste has none", function()
        local err = token.set("csrftoken=abc; sessionid=def")

        assert.truthy(err:find("@JWT:REFRESH_TOKEN", 1, true))
        assert.truthy(err:find("refresh", 1, true))
    end)

    it("decodes the claims of a token", function()
        local jwt = helpers.jwt_with({ token_type = "refresh", user_id = 7 })

        assert.are.same({ token_type = "refresh", user_id = 7 }, token.claims(jwt))
        assert.is_nil(token.claims(helpers.jwt("opaque")))
    end)

    it("stores a refresh token LintCode accepts, readable by the owner only", function()
        local jwt = helpers.jwt("first")

        assert.is_nil(token.set(jwt))
        assert.are.same(jwt, token.read())
        assert.are.same({ jwt }, refreshed)

        local stat = vim.loop.fs_stat(config.storage.cache:joinpath("lintcode_token"):absolute())
        assert.are.same(tonumber("600", 8), bit.band(stat.mode, tonumber("777", 8)))
    end)

    it("rejects a token LintCode refuses", function()
        helpers.mock(mocks, api, "refresh_token", function()
            return nil, { code = 1008, msg = "LintCode: Not authenticated" }
        end)

        assert.are.same("Not authenticated", token.set(helpers.jwt("bad")))
        assert.is_nil(token.read())
    end)

    it("rejects a token that does not belong to a signed-in user", function()
        helpers.mock(mocks, api, "profile", function()
            return nil
        end)

        assert.truthy(token.set(helpers.jwt("anon")))
        assert.is_nil(token.read())
    end)

    it("reuses the access token until it is about to expire", function()
        token.set(helpers.jwt("first"))

        assert.are.same("access-1", token.access())
        assert.are.same("access-1", token.access())
        assert.are.same(1, #refreshed)

        helpers.mock(mocks, os, "time", function()
            return math.huge
        end)
        assert.are.same("access-2", token.access())
    end)

    it("keeps the rotated refresh token", function()
        local rotated = helpers.jwt("rotated")
        helpers.mock(mocks, api, "refresh_token", function()
            return { access = "access", access_lifetime = 500, refresh = rotated }
        end)

        token.set(helpers.jwt("first"))
        assert.are.same(rotated, token.read())

        token.reset()
        local next_rotation = helpers.jwt("next")
        helpers.mock(mocks, api, "refresh_token", function()
            return { access = "access", access_lifetime = 500, refresh = next_rotation }
        end)
        assert.are.same("access", token.access())
        assert.are.same(next_rotation, token.read())
    end)

    it("asks for a login when there is no token", function()
        local access, err = token.access()

        assert.is_nil(access)
        assert.truthy(err.msg:find(":Leet lintcode login", 1, true))
    end)

    it("tells an expired token apart from a network failure", function()
        token.write(helpers.jwt("stored"))

        helpers.mock(mocks, api, "refresh_token", function()
            return nil, { code = 1008, msg = "LintCode: Not authenticated" }
        end)
        local _, expired = token.access()
        assert.truthy(expired.msg:find("expired", 1, true))

        helpers.mock(mocks, api, "refresh_token", function()
            return nil, { code = 7, msg = "LintCode: curl failed" }
        end)
        local _, offline = token.access()
        assert.are.same("LintCode: curl failed", offline.msg)
    end)
end)
