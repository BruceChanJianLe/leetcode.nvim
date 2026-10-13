-- Headless test bootstrap, see `make test`.
-- Dependencies come from $PLENARY_DIR / $NUI_DIR, or are cloned into `.tests/`.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

---@param env string
---@param repo string
local function dep(env, repo)
    local dir = vim.env[env] or ("%s/.tests/deps/%s"):format(root, repo:match("[^/]+$"))

    if vim.fn.isdirectory(dir) == 0 then
        vim.fn.system({ "git", "clone", "--depth", "1", "https://github.com/" .. repo, dir })
        assert(vim.v.shell_error == 0, "failed to clone " .. repo)
    end

    vim.opt.runtimepath:append(dir)
end

vim.opt.runtimepath:append(root)
package.path = ("%s/?.lua;%s"):format(root, package.path)
dep("PLENARY_DIR", "nvim-lua/plenary.nvim")
dep("NUI_DIR", "MunifTanjim/nui.nvim")

vim.cmd("runtime plugin/plenary.vim")
