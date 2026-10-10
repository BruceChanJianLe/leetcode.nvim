---Maps leetcode.nvim language slugs to LintCode's language names.
---LintCode has no Dart, Racket, Elixir or Bash.
---@type table<lc.lang, string>
local langs = {
    cpp = "cpp",
    java = "java",
    python = "python2",
    python3 = "python3",
    c = "c",
    csharp = "csharp",
    javascript = "js",
    typescript = "typescript",
    php = "php",
    swift = "swift",
    kotlin = "kotlin",
    golang = "go",
    ruby = "ruby",
    scala = "scala2",
    rust = "rust",
    erlang = "erlang",
}

---@class lc.lintcode.Langs
local M = {}

---@param slug lc.lang
---@return string|nil
function M.to_lintcode(slug)
    return langs[slug]
end

---@param name string LintCode language name
---@return lc.lang|nil
function M.from_lintcode(name)
    for slug, lintcode in pairs(langs) do
        if lintcode == name then
            return slug
        end
    end
end

return M
