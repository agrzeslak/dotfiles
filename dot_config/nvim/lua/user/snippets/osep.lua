local ls = require("luasnip")
local fmt = require("luasnip.extras.fmt").fmt
local rep = require("luasnip.extras").rep

local s = ls.s
local i = ls.i
local t = ls.t
local c = ls.choice_node

ls.add_snippets("markdown", {
	s(
		"osep-host-notes",
		fmt(
			[[
			# {}

			## Flag(s)

			- `local.txt`: `TODO`

			  ![`local.txt`](./screenshots/TODO)

				```ps1
				TODO
				```

			- `proof.txt`: `TODO`

			  ![`proof.txt`](./screenshots/TODO)

				```ps1
				TODO
				```

			## Pre-Compromise Enumeration Steps

			## Compromise

			## Post-Exploitation Enumeration Steps

			## Local Privilege Escalation

			]],
			i(1)
		)
	),
})
