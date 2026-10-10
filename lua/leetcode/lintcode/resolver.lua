local config = require("leetcode.config")
local api = require("leetcode.lintcode.api")

---@alias lc.lintcode.source
---| "user" mapped by hand with `:Leet lintcode map`
---| "slug" LintCode redirects the LeetCode slug to this problem
---| "title" the only LintCode problem with exactly the same title

---@alias lc.lintcode.confidence
---| "example" a LeetCode example testcase is identical on LintCode
---| "signature" same number of parameters, examples differ
---| "none" nothing to compare or nothing matched

---@class lc.lintcode.Mapping
---@field id integer LintCode problem id
---@field source lc.lintcode.source
---@field confidence? lc.lintcode.confidence

---Maps a LeetCode problem to its LintCode twin and remembers the answer.
---Only ids are stored, never LintCode's content.
---@class lc.lintcode.Resolver
local Resolver = {}

---@return Path
local function file()
    return config.storage.cache:joinpath("lintcode_map.json")
end

---@return table<string, lc.lintcode.Mapping>
function Resolver.read()
    if not file():exists() then
        return {}
    end

    local ok, map = pcall(vim.json.decode, file():read() or "")
    return ok and type(map) == "table" and map or {}
end

---@param map table<string, lc.lintcode.Mapping>
local function write(map)
    file():write(vim.json.encode(map), "w")
end

---@param slug string LeetCode title slug
---@return lc.lintcode.Mapping|nil
function Resolver.get(slug)
    local mapping = Resolver.read()[slug]
    if type(mapping) == "table" and tonumber(mapping.id) then
        return { id = tonumber(mapping.id), source = mapping.source or "user" }
    end
end

---@param slug string LeetCode title slug
---@param mapping lc.lintcode.Mapping
function Resolver.set(slug, mapping)
    local map = Resolver.read()
    map[slug] = { id = mapping.id, source = mapping.source }
    write(map)
end

---@param slug string LeetCode title slug
---@return boolean removed
function Resolver.unset(slug)
    local map = Resolver.read()
    if not map[slug] then
        return false
    end

    map[slug] = nil
    write(map)
    return true
end

---@param title string
---@return string
function Resolver.norm_title(title)
    local norm = (title or ""):lower():gsub("&", " and "):gsub("['’`]", ""):gsub("[^%w]+", " ")
    norm = vim.trim(norm)

    -- `Two Sum II` and `Two Sum 2` are the same problem
    local romans = { iv = "4", iii = "3", ii = "2", i = "1" }
    local head, roman = norm:match("^(.-)%s+(%a+)$")
    if head and romans[roman] then
        norm = head .. " " .. romans[roman]
    end

    return norm
end

---The unique LintCode problem whose title equals `title`, ignoring case and punctuation.
---@param title string
---@return lc.lintcode.Mapping|nil, lc.err
function Resolver.by_title(title)
    local problems, err = api.search(title)
    if not problems then
        return nil, err
    end

    local want = Resolver.norm_title(title)
    local ids = {}
    for _, p in ipairs(problems) do
        local id = tonumber(p.problem_id or p.id)
        local names = { p.en_title, p.title }

        for _, name in ipairs(names) do
            if id and type(name) == "string" and Resolver.norm_title(name) == want then
                ids[id] = true
            end
        end
    end

    local unique = vim.tbl_keys(ids)
    if #unique == 1 then
        return { id = unique[1], source = "title" }
    end
end

---@param case any
---@return string|nil
local function norm_case(case)
    if type(case) ~= "string" then
        return
    end
    local norm = case:gsub("%s+", "")
    return norm ~= "" and norm or nil
end

---How sure we are that `problem` is the LeetCode question `q`, judged by the
---signature and example testcases LeetCode still serves for premium problems.
---@param q lc.question_res LeetCode question
---@param problem table LintCode problem
---@return lc.lintcode.confidence
function Resolver.verify(q, problem)
    local sample = norm_case(problem.testcase_sample)
    if not sample then
        return "none"
    end

    local cases = type(q.testcase_list) == "table" and q.testcase_list or {}
    for _, case in ipairs(cases) do
        if norm_case(case) == sample then
            return "example"
        end
    end

    local md = type(q.meta_data) == "table" and q.meta_data or {}
    local params = type(md.params) == "table" and #md.params or 0
    local lines = #vim.split(vim.trim(problem.testcase_sample), "\n")
    if params > 0 and params == lines then
        return "signature"
    end

    return "none"
end

---@class lc.lintcode.Resolution
---@field mapping? lc.lintcode.Mapping
---@field problem? table LintCode problem
---@field err? lc.err

---Resolves `q` to its LintCode twin: a stored mapping first, then LintCode's slug
---redirect, then a unique exact title match. Candidates pointing at a deleted problem
---are skipped; a VIP-locked twin stops the search.
---@param q lc.question_res LeetCode question
---@return lc.lintcode.Resolution
function Resolver.resolve(q)
    local tried = {}
    local last_err

    local steps = {
        function()
            return Resolver.get(q.title_slug)
        end,
        function()
            local id, err = api.resolve_slug(q.title_slug)
            return id and { id = id, source = "slug" } or nil, err
        end,
        function()
            return Resolver.by_title(q.title)
        end,
    }

    for _, step in ipairs(steps) do
        local mapping, err = step()
        last_err = err or last_err

        if mapping and not tried[mapping.id] then
            tried[mapping.id] = true

            local problem, perr = api.problem(mapping.id)
            if problem then
                mapping.confidence = Resolver.verify(q, problem)
                Resolver.set(q.title_slug, mapping)
                return { mapping = mapping, problem = problem }
            end

            -- 1001: VIP-only on LintCode too; anything but "not found" is not ours to skip
            if mapping.source == "user" or (perr and perr.code ~= 1004) then
                return { mapping = mapping, err = perr }
            end
            last_err = nil
        end
    end

    return { err = last_err }
end

return Resolver
