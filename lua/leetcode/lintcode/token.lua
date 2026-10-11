local path = require("plenary.path")
local config = require("leetcode.config")
local api = require("leetcode.lintcode.api")

---LintCode's web client keeps a JWT refresh token in `localStorage["@JWT:REFRESH_TOKEN"]`
---and trades it for short-lived access tokens. The user pastes that refresh token once;
---access tokens are minted on demand and only kept in memory.
---@class lc.lintcode.Token
local Token = {}

---@type { token: string, expires_at: integer }|nil
local access = nil

---@return Path
local function file()
    return config.storage.cache:joinpath("lintcode_token")
end

---Extracts the refresh JWT from a pasted value: the token itself (as stored under
---`@JWT:REFRESH_TOKEN`), or a `Cookie` header or cookie string carrying LintCode's
---`refresh` cookie.
---@param str string
---@return string|nil
function Token.parse(str)
    local token = vim.trim(str or ""):gsub("^[Cc]ookie:%s*", "")
    token = token:match("%f[%w_]refresh=([^;%s]+)") or token

    if token:match("^[%w_-]+%.[%w_-]+%.[%w_-]+$") then
        return token
    end
end

---The claims of a JWT, when they can be decoded.
---@param jwt string
---@return table|nil
function Token.claims(jwt)
    local payload = jwt:match("^[^.]+%.([^.]+)%.")
    if not payload or not vim.base64 then
        return
    end

    payload = payload:gsub("-", "+"):gsub("_", "/")
    payload = payload .. ("="):rep((4 - #payload % 4) % 4)

    local ok, decoded = pcall(vim.base64.decode, payload)
    if not ok then
        return
    end
    local ok_json, claims = pcall(vim.json.decode, decoded)
    return ok_json and type(claims) == "table" and claims or nil
end

---@return string|nil
function Token.read()
    if not file():exists() then
        return
    end

    local contents = file():read()
    if type(contents) ~= "string" then
        return
    end

    return Token.parse(contents)
end

---@param refresh string
function Token.write(refresh)
    file():write(refresh, "w")
    pcall(vim.loop.fs_chmod, file():absolute(), tonumber("600", 8))
end

---@return boolean
function Token.delete()
    access = nil
    if not file():exists() then
        return false
    end
    return pcall(path.rm, file())
end

---@param tokens table `{ access, access_lifetime, refresh? }`
---@param refresh string the refresh token that minted `tokens`
---@return string|nil access_token, string refresh_token to keep, refresh tokens may rotate
local function remember(tokens, refresh)
    if type(tokens) ~= "table" or type(tokens.access) ~= "string" then
        access = nil
        return nil, refresh
    end

    -- renew 30 seconds before LintCode does, to not race the expiry mid-request
    local lifetime = tonumber(tokens.access_lifetime) or 300
    access = {
        token = tokens.access,
        expires_at = os.time() + math.max(lifetime - 30, 0),
    }

    local rotated = type(tokens.refresh) == "string" and tokens.refresh ~= ""
    return access.token, rotated and tokens.refresh or refresh
end

---Returns a valid access token, minting a new one from the stored refresh token if needed.
---@return string|nil access_token, lc.err
function Token.access()
    if access and os.time() < access.expires_at then
        return access.token
    end

    local refresh = Token.read()
    if not refresh then
        return nil, { msg = "No LintCode token found. Run `:Leet lintcode login` first" }
    end

    local tokens, err = api.refresh_token(refresh)
    if not tokens then
        access = nil
        if err and err.status ~= 401 and err.code ~= 1008 then
            return nil, err
        end
        return nil,
            {
                msg = "LintCode token expired or invalid. Paste a fresh one with `:Leet lintcode login`",
            }
    end

    local token, keep = remember(tokens, refresh)
    if not token then
        return nil, { msg = "LintCode: token refresh returned no access token" }
    end

    -- refresh tokens rotate: keep the newest one or the next refresh fails
    if keep ~= refresh then
        Token.write(keep)
    end
    return token
end

---Validates and stores a pasted refresh token.
---@param str string
---@return string|nil err why the token was refused
function Token.set(str)
    local refresh = Token.parse(str)
    if not refresh then
        return "no refresh token found. Paste `@JWT:REFRESH_TOKEN` from LintCode's local storage,"
            .. " or a `Cookie` header with a `refresh` cookie"
    end

    local claims = Token.claims(refresh)
    if claims and claims.token_type == "access" then
        return "that is a short-lived access token. Paste the refresh token"
            .. " (`@JWT:REFRESH_TOKEN` or the `refresh` cookie)"
    end

    local tokens, err = api.refresh_token(refresh)
    if not tokens then
        local reason = (err or {}).msg or "the token was rejected"
        return (reason:gsub("^LintCode: ", ""))
    end

    local token, keep = remember(tokens, refresh)
    if not token then
        return "token refresh returned no access token"
    end

    if not api.profile(token) then
        access = nil
        return "the token does not belong to a signed-in account"
    end

    Token.write(keep)
end

---@private
function Token.reset()
    access = nil
end

return Token
