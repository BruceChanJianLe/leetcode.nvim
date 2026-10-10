local curl = require("plenary.curl")
local log = require("leetcode.logger")

---LintCode has no public API: these are the endpoints its own web client calls.
---@class lc.lintcode.Api
local Api = {}

Api.base = "https://apiv1.lintcode.com"
Api.web = "https://www.lintcode.com"

local user_agent = "Mozilla/5.0 (X11; Linux x86_64; rv:123.0) Gecko/20100101 Firefox/123.0"

---@class lc.lintcode.Request
---@field query? table<string, string|integer>
---@field body? table|string table is encoded as JSON, string is a path to a JSON file
---@field token? string access token
---@field callback? fun(body: table|nil, err: lc.err)

---@param out table plenary.curl response
---@return table|nil body, lc.err
function Api.handle(out)
    log.debug(out)

    if out.exit ~= 0 then
        return nil, { code = out.exit, msg = "LintCode: curl failed" }
    end

    local ok, body = pcall(vim.json.decode, out.body or "")
    if not ok or type(body) ~= "table" then
        return nil,
            {
                status = out.status,
                msg = ("LintCode: unexpected response (HTTP %s)"):format(out.status),
            }
    end

    if body.success == false or out.status >= 300 then
        local detail = type(body.detail) == "string" and body.detail ~= "" and body.detail
        return nil,
            {
                status = out.status,
                code = body.code,
                msg = "LintCode: " .. (detail or ("HTTP %s"):format(out.status)),
            }
    end

    return body
end

---@param method "get"|"post"
---@param url string
---@param opts? lc.lintcode.Request
---@return table|nil body, lc.err
function Api.request(method, url, opts)
    opts = opts or {}

    local headers = {
        ["User-Agent"] = user_agent,
        ["Accept"] = "application/json",
    }
    if opts.token then
        headers["Authorization"] = "Bearer " .. opts.token
    end

    local body = opts.body
    if method == "post" then
        -- GETs must not carry `Origin`: the problem endpoints reject them with it
        headers["Content-Type"] = "application/json"
        headers["Origin"] = Api.web
        headers["Referer"] = Api.web .. "/"

        if type(body) == "table" then
            body = vim.json.encode(body)
        end
    end

    local params = {
        headers = headers,
        query = opts.query,
        body = body,
        compressed = false,
    }

    if opts.callback then
        local cb = vim.schedule_wrap(opts.callback)
        params.callback = function(out)
            cb(Api.handle(out))
        end
        params.on_error = function(out)
            cb(nil, { code = out.exit, msg = "LintCode: curl failed" })
        end

        curl[method](url, params)
        return
    end

    local ok, out = pcall(curl[method], url, params)
    if not ok then
        return nil, { msg = "LintCode: curl failed" }
    end

    return Api.handle(out)
end

---@param id integer
---@return table|nil problem, lc.err
function Api.problem(id)
    local body, err = Api.request("get", ("%s/v2/api/problems/%d/"):format(Api.base, id), {
        query = { lang = 2 },
    })
    if not body then
        return nil, err
    end

    return body.data
end

---@param id integer
---@param language string LintCode language name
---@return string|nil code, lc.err
function Api.template(id, language)
    local body, err = Api.request("get", ("%s/new/api/problems/%d/reset/"):format(Api.base, id), {
        query = { scene = 1, language = language },
    })
    if not body then
        return nil, err
    end

    return type(body.data) == "table" and body.data.code or nil
end

---@param query string
---@return table[]|nil problems, lc.err
function Api.search(query)
    local body, err = Api.request("get", Api.base .. "/v2/api/new-search/mobile/", {
        query = { query = query, search_type = 1, _format = "new" },
    })
    if not body then
        return nil, err
    end

    return type(body.data) == "table" and body.data or {}
end

---Follows LintCode's own `/problem/<slug>/` redirect, which points at `/problem/<id>/`
---when a problem with that slug exists and at the problem list otherwise.
---@param slug string
---@return integer|nil id, lc.err
function Api.resolve_slug(slug)
    local ok, out = pcall(curl.get, ("%s/problem/%s/"):format(Api.web, slug), {
        headers = { ["User-Agent"] = user_agent },
        compressed = false,
    })
    if not ok or out.exit ~= 0 then
        return nil, { msg = "LintCode: curl failed" }
    end

    for _, header in ipairs(out.headers or {}) do
        local name, value = header:match("^([^:]+):%s*(.-)%s*$")
        local id = name and name:lower() == "location" and value:match("/problem/(%d+)/?$")
        if id then
            return tonumber(id)
        end
    end
end

---@param refresh string refresh token
---@return table|nil tokens `{ access, access_lifetime, refresh? }`, lc.err
function Api.refresh_token(refresh)
    local body, err = Api.request("post", Api.base .. "/v2/api/token-refresh/", {
        body = { refresh = refresh },
    })
    if not body then
        return nil, err
    end

    return body.data
end

---@param token string access token
---@return table|nil user_info, lc.err
function Api.profile(token)
    local body, err = Api.request("get", Api.base .. "/new/api/accounts/profile/", {
        token = token,
    })
    if not body then
        return nil, err
    end

    local user = type(body.data) == "table" and body.data.user_info
    return user ~= vim.NIL and user or nil
end

---@param token string access token
---@param body_file string path to the JSON payload
---@param callback fun(id: integer|nil, err: lc.err)
function Api.submit(token, body_file, callback)
    Api.request("post", Api.base .. "/new/api/submissions/", {
        token = token,
        body = body_file,
        callback = function(body, err)
            if not body then
                return callback(nil, err)
            end

            local id = type(body.data) == "table" and body.data.id or nil
            if not id then
                return callback(nil, { msg = "LintCode: submission was not accepted" })
            end
            callback(id)
        end,
    })
end

---@param token string access token
---@param id integer submission id
---@param is_test boolean
---@param callback fun(result: table|nil, err: lc.err)
function Api.poll(token, id, is_test, callback)
    local query = { id = id }
    if is_test then
        query.is_test_submission = "true"
    end

    Api.request("get", Api.base .. "/new/api/submissions/refresh/", {
        token = token,
        query = query,
        callback = function(body, err)
            if not body then
                return callback(nil, err)
            end
            callback(type(body.data) == "table" and body.data or nil)
        end,
    })
end

return Api
