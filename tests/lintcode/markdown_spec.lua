local markdown = require("leetcode.lintcode.markdown")

describe("lintcode markdown", function()
    it("renders paragraphs with inline markup", function()
        local html = markdown.to_html("Return **the sum** of `a` and *b*.\nSecond line.")

        assert.are.same(
            "<p>Return <strong>the sum</strong> of <code>a</code> and <em>b</em>.\nSecond line.</p>",
            html
        )
    end)

    it("escapes HTML outside and inside code", function()
        assert.are.same(
            "<p>a &lt; b &amp;&amp; <code>x &lt;&gt; y</code></p>",
            markdown.to_html("a < b && `x <> y`")
        )
    end)

    it("keeps fenced code verbatim inside pre", function()
        local html = markdown.to_html("```python\nif a < b:\n    return [1, 2]\n```")

        assert.are.same("<pre>if a &lt; b:\n    return [1, 2]</pre>", html)
    end)

    it("folds testcase labels into their code block like LeetCode statements", function()
        local html = markdown.to_html(
            "**Example 1:**  \n \nInput:  \n\n```\n1\n```\nOutput：\n```\n2\n```\nExplanation:\n\n1 + 1 = 2"
        )

        assert.are.same(
            table.concat({
                "<p><strong>Example 1:</strong></p>",
                "<pre><strong>Input:</strong>\n1</pre>",
                "<pre><strong>Output:</strong>\n2</pre>",
                "<p><strong>Explanation:</strong></p>",
                "<p>1 + 1 = 2</p>",
            }, "\n\n"),
            html
        )
    end)

    it("separates paragraphs by blank lines", function()
        assert.are.same("<p>one\ntwo</p>\n\n<p>three</p>", markdown.to_html("one\ntwo\n\nthree"))
    end)

    it("renders bullet and numbered lists", function()
        local html = markdown.to_html("- one\n- two\n\n1. first\n2. second")

        assert.are.same(
            "<ul>\n<li>one</li>\n<li>two</li>\n</ul>\n\n<ol>\n<li>first</li>\n<li>second</li>\n</ol>",
            html
        )
    end)

    it("renders headings, links and images", function()
        local html =
            markdown.to_html("## Notes\nSee [docs](https://e.x/a) ![graph](https://e.x/g.png)")

        assert.are.same(
            "<p><strong>Notes</strong></p>\n\n"
                .. "<p>See <a href=\"https://e.x/a\">docs</a> <img alt=\"graph\" src=\"https://e.x/g.png\" /></p>",
            html
        )
    end)

    it("turns inline LaTeX into plain text", function()
        assert.are.same(
            "<p>-2^31 ≤ a_i ≤ 2^31 - 1, n × m &lt; 10^5</p>",
            markdown.to_html("$-2^{31} \\leq a_i \\le 2^{31} - 1$, $n \\times m \\lt 10^5$")
        )
        assert.are.same("{1, 2}", markdown.latex("\\{1, 2\\}"))
        assert.are.same("len(s)", markdown.latex("\\text{len}(s)"))
    end)

    it("does not treat spaced asterisks as emphasis", function()
        assert.are.same("<p>2 * 3 * 4</p>", markdown.to_html("2 * 3 * 4"))
    end)

    it("assembles a problem from its statement blocks in reading order", function()
        local html = markdown.problem({
            description = "Add two numbers.",
            example = "**Example 1:**\n```\n1\n```",
            new_notice = "",
            notice = "Numbers fit in an int.",
            challenge = "Do it without `+`.",
        })

        assert.are.same(
            table.concat({
                "<p>Add two numbers.</p>",
                "<p><strong>Example 1:</strong></p>",
                "<pre>1</pre>",
                "<p><strong>Note:</strong></p>",
                "<p>Numbers fit in an int.</p>",
                "<p><strong>Follow-up:</strong></p>",
                "<p>Do it without <code>+</code>.</p>",
            }, "\n\n"),
            html
        )
    end)

    it("tolerates missing blocks", function()
        assert.are.same("", markdown.problem({ description = vim.NIL }))
    end)
end)
