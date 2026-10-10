---Converts the Markdown subset LintCode writes its statements in (with `$...$` LaTeX)
---into the HTML shape the description renderer already handles for LeetCode questions.
---@class lc.lintcode.Markdown
local M = {}

---@param str string
---@return string
local function escape(str)
    return (str:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local symbols = {
    le = "≤",
    leq = "≤",
    leqslant = "≤",
    ge = "≥",
    geq = "≥",
    geqslant = "≥",
    lt = "<",
    gt = ">",
    ne = "≠",
    neq = "≠",
    times = "×",
    cdot = "·",
    cdots = "⋯",
    ldots = "…",
    dots = "…",
    infty = "∞",
    ["in"] = "∈",
    notin = "∉",
    sum = "∑",
    prod = "∏",
    sqrt = "√",
    pm = "±",
    to = "→",
    rightarrow = "→",
    leftarrow = "←",
    lfloor = "⌊",
    rfloor = "⌋",
    lceil = "⌈",
    rceil = "⌉",
    alpha = "α",
    beta = "β",
    lambda = "λ",
    pi = "π",
    left = "",
    right = "",
    quad = " ",
    qquad = " ",
}

local text_commands = { "text", "textbf", "texttt", "mathrm", "mathbf", "mathit", "operatorname" }

---Renders inline LaTeX as plain text.
---@param src string
---@return string
function M.latex(src)
    local str = src
    for _, name in ipairs(text_commands) do
        str = str:gsub("\\" .. name .. "%s*{([^{}]*)}", "%1")
    end

    str = str:gsub("\\(%a+)", function(name)
        return symbols[name] or name
    end)
    -- escaped characters; literal braces survive the grouping-brace cleanup below
    str = str:gsub("\\([%%{}_#&$ ,;!])", function(c)
        if c == "," or c == ";" then
            return " "
        elseif c == "!" then
            return ""
        elseif c == "{" then
            return "\3"
        elseif c == "}" then
            return "\4"
        end
        return c
    end)

    -- `2^{31}` reads as `2^31`, which is also how the html renderer shows `<sup>`,
    -- and unlike tags it survives the plain-text renderer
    str = escape(str):gsub("[{}]", ""):gsub("\3", "{"):gsub("\4", "}")

    return vim.trim(str)
end

---@param text string
---@return string
function M.inline(text)
    local stash = {}
    local function keep(html)
        table.insert(stash, html)
        return "\1" .. #stash .. "\2"
    end

    text = text:gsub("`([^`]+)`", function(code)
        return keep("<code>" .. escape(code) .. "</code>")
    end)
    text = text:gsub("%$%$(.-)%$%$", function(math)
        return keep(M.latex(math))
    end)
    text = text:gsub("%$([^%$\n]+)%$", function(math)
        return keep(M.latex(math))
    end)

    text = escape(text)
    text = text:gsub("!%[([^%]]*)%]%(([^%s%)]+)[^%)]*%)", function(alt, src)
        return keep(("<img alt=\"%s\" src=\"%s\" />"):format(alt, src))
    end)
    text = text:gsub("%[([^%]]+)%]%(([^%s%)]+)[^%)]*%)", "<a href=\"%2\">%1</a>")
    text = text:gsub("%*%*(.-)%*%*", "<strong>%1</strong>")
    text = text:gsub("%*([^%s%*][^%*]-)%*", function(inner)
        if not inner:match("%s$") then
            return "<em>" .. inner .. "</em>"
        end
    end)

    return (text:gsub("\1(%d+)\2", function(i)
        return stash[tonumber(i)]
    end))
end

---Example labels LintCode writes as plain lines, styled like LeetCode's bold ones.
---@param line string
---@return string|nil
local function label(line)
    local name = line:match("^%s*(%a+)%s*:%s*$") or line:match("^%s*(%a+)%s*：%s*$")
    if name == "Input" or name == "Output" or name == "Explanation" then
        return ("<strong>%s:</strong>"):format(name)
    end
end

---Blocks are separated by a blank line, like LeetCode's statements, so they also
---read well through the plain-text renderer used without the html parser.
---@param markdown string
---@return string html
function M.to_html(markdown)
    local out = {}
    local paragraph, labeled = {}, false
    local list ---@type { tag: string, items: string[] }|nil
    local code ---@type string[]|nil

    local function flush_paragraph()
        if not vim.tbl_isempty(paragraph) then
            table.insert(out, "<p>" .. table.concat(paragraph, "\n") .. "</p>")
            paragraph, labeled = {}, false
        end
    end

    local function close_list()
        if list then
            local items = table.concat(list.items, "\n")
            table.insert(out, ("<%s>\n%s\n</%s>"):format(list.tag, items, list.tag))
            list = nil
        end
    end

    local function close_code()
        table.insert(out, "<pre>" .. table.concat(code, "\n") .. "</pre>")
        code = nil
    end

    for line in vim.gsplit((markdown or ""):gsub("\r\n", "\n"), "\n") do
        if code then
            if line:match("^%s*```") then
                close_code()
            else
                table.insert(code, escape(line))
            end
        elseif line:match("^%s*```") then
            close_list()
            code = {}
            -- `Input:` right above a code block labels it, as in LeetCode's `<pre>`
            if labeled and #paragraph == 1 then
                table.insert(code, paragraph[1])
                paragraph, labeled = {}, false
            else
                flush_paragraph()
            end
        elseif line:match("^%s*$") then
            -- a label waits for the code block it names
            if not labeled then
                flush_paragraph()
            end
            close_list()
        else
            local heading = line:match("^%s*#+%s+(.-)%s*$")
            local bullet = line:match("^%s*[-*+]%s+(.-)%s*$")
            local numbered = line:match("^%s*%d+[.)]%s+(.-)%s*$")
            local tag = label(line)

            if heading then
                flush_paragraph()
                close_list()
                table.insert(out, ("<p><strong>%s</strong></p>"):format(M.inline(heading)))
            elseif bullet or numbered then
                flush_paragraph()
                local kind = bullet and "ul" or "ol"
                if not list or list.tag ~= kind then
                    close_list()
                    list = { tag = kind, items = {} }
                end
                table.insert(list.items, ("<li>%s</li>"):format(M.inline(bullet or numbered)))
            elseif tag then
                flush_paragraph()
                close_list()
                paragraph, labeled = { tag }, true
            else
                close_list()
                if labeled then
                    flush_paragraph()
                end
                table.insert(paragraph, M.inline(vim.trim(line)))
            end
        end
    end

    if code then
        close_code()
    end
    flush_paragraph()
    close_list()

    return table.concat(out, "\n\n")
end

---@param value any
---@return string|nil
local function text(value)
    if type(value) == "string" and vim.trim(value) ~= "" then
        return value
    end
end

---Builds the statement HTML from a LintCode problem's Markdown blocks.
---@param problem table LintCode problem
---@return string html
function M.problem(problem)
    local parts = {}

    local description = text(problem.description)
    if description then
        table.insert(parts, M.to_html(description))
    end

    local example = text(problem.example)
    if example then
        table.insert(parts, M.to_html(example))
    end

    local notice = text(problem.new_notice) or text(problem.notice)
    if notice then
        table.insert(parts, "<p><strong>Note:</strong></p>")
        table.insert(parts, M.to_html(notice))
    end

    local challenge = text(problem.challenge)
    if challenge then
        table.insert(parts, "<p><strong>Follow-up:</strong></p>")
        table.insert(parts, M.to_html(challenge))
    end

    return table.concat(parts, "\n\n")
end

return M
