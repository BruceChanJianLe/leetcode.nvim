local config = require("leetcode.config")
local api = require("leetcode.lintcode.api")

---@class lc.lintcode.Mapping
---@field id integer LintCode problem id

---Maps a LeetCode problem to its LintCode twin and remembers the answer.
---Only ids are stored, never LintCode's content.
---@class lc.lintcode.Resolver
local Resolver = {}

---@return Path
local function file()
    return config.storage.cache:joinpath("lintcode_map.json")
end

---@return table<string, lc.lintcode.Mapping>
local function read()
    if not file():exists() then
        return {}
    end

    local ok, map = pcall(vim.json.decode, file():read() or "")
    return ok and type(map) == "table" and map or {}
end

---@param slug string LeetCode title slug
---@return lc.lintcode.Mapping|nil
local function get(slug)
    local mapping = read()[slug]
    if type(mapping) == "table" and tonumber(mapping.id) then
        return { id = tonumber(mapping.id) }
    end
end

---@param slug string LeetCode title slug
---@param mapping lc.lintcode.Mapping
local function set(slug, mapping)
    local map = read()
    map[slug] = { id = mapping.id }
    file():write(vim.json.encode(map), "w")
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
        return { id = unique[1] }
    end
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
            return get(q.title_slug)
        end,
        function()
            local id, err = api.resolve_slug(q.title_slug)
            return id and { id = id } or nil, err
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
                set(q.title_slug, mapping)
                return { mapping = mapping, problem = problem }
            end

            -- 1001: VIP-only on LintCode too; anything but "not found" is not ours to skip
            if perr and perr.code ~= 1004 then
                return { mapping = mapping, err = perr }
            end
            last_err = nil
        end
    end

    return { err = last_err }
end

return Resolver
