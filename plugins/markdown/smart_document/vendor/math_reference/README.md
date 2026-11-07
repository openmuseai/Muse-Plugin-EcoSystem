# Fixed original formula references

Eight unmodified source/license files, verified against pinned local Git objects. AppFlowy uses the `math_equation` block and string `formula` attribute, a pure Flutter Math.tex renderer, an existing mobile insertion item, and a $$ Markdown node parser. Its lock pins flutter_math_fork 0.7.3 with SHA-256 284bab89b2fbf1bc3a0baf13d011c1dd324d004e35d177626b77f2fc056366ac.

SiYuan source distinguishes inline/display math, width adaptation, remote rendering trust and sanitization. The current Flutter adapter does not execute KaTeX HTML or load scripts; unsupported source remains intact. Complete inline math, mhchem and custom macro compatibility require separate acceptance.
