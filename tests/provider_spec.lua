local helpers = require("tests.helpers")

describe("provider selection", function()
    local providers, config

    before_each(function()
        config = helpers.setup()
        providers = require("leetcode.provider")
    end)

    it("serves premium questions from LintCode only when enabled and not premium", function()
        assert.is_true(providers.via_lintcode(true))
        assert.is_false(providers.via_lintcode(false))
        assert.is_false(providers.is_locked(true))

        config.auth.is_premium = true
        assert.is_false(providers.via_lintcode(true))
        assert.is_false(providers.is_locked(true))
    end)

    it("keeps premium questions locked when LintCode is disabled", function()
        config = helpers.setup({ lintcode = { enabled = false } })

        assert.is_false(providers.via_lintcode(true))
        assert.is_true(providers.is_locked(true))
        assert.is_false(providers.is_locked(false))
    end)

    it("defaults to LeetCode with LintCode switched off", function()
        assert.is_false(require("leetcode.config.template").lintcode.enabled)
        assert.are.same("leetcode", providers.leetcode().name)
        assert.are.same("lintcode", providers.lintcode().name)
    end)
end)
