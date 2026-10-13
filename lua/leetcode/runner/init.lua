---@module 'plenary'

local log = require("leetcode.logger")
local Judge = require("leetcode.logger.spinner.judge")

---@class lc.Runner
---@field question lc.ui.Question
local Runner = {}
Runner.__index = Runner

Runner.running = false

---@param self lc.Runner
---@param submit boolean
Runner.run = vim.schedule_wrap(function(self, submit)
    if Runner.running then
        return log.warn("Runner is busy")
    end

    local ok, err = pcall(Runner.handle, self, submit)
    if not ok then
        self:stop()
        log.error(err)
    end
end)

Runner.stop = function()
    Runner.running = false
end

---Whether the question's provider can run code now, hinting what to do if not.
---@return boolean
function Runner:ready()
    local provider = self.question.provider
    local hint = provider.ready and provider.ready(self.question)
    if hint then
        log.warn(hint)
        return false
    end
    return true
end

function Runner:handle(submit)
    Runner.running = true
    local question = self.question

    local body = {
        lang = question.lang,
        typed_code = self.question:editor_submit_lines(submit),
        question_id = question.q.id,
        data_input = not submit and question.console.testcase:content(),
    }

    local judge = Judge:init()
    local function callback(item, state, err)
        if err or item then
            self:stop()
        end

        if item then
            if item._.success then
                judge:success(item.status_msg)
            else
                judge:error(item.status_msg)
            end
        elseif state then
            judge:from_state(state)
        elseif err then
            judge:error(err.msg or "Something went wrong")
        end

        if item then
            question.console.result:handle(item)
        end
    end

    question.provider.run(question, submit, body, callback)
end

---@param question lc.ui.Question
function Runner:init(question)
    return setmetatable({ question = question }, self)
end

return Runner
