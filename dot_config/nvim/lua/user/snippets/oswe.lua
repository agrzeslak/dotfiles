local ls = require("luasnip")
local fmt = require("luasnip.extras.fmt").fmt
local rep = require("luasnip.extras").rep

local s = ls.s
local i = ls.i
local t = ls.t
local c = ls.choice_node
local f = ls.function_node

ls.add_snippets("python", {
	s(
		"requests-boilerplate",
		fmt(
			[[
			#!/usr/bin/env python
			import argparse
			import sys

			import requests
			import urllib3


			def main() -> None:
				parser = argparse.ArgumentParser(prog="{}")
				parser.add_argument("target")
				parser.add_argument("-v", "--verbose", action="store_true")
				parser.add_argument("-x", "--proxy")
				arguments = parser.parse_args()

				target = arguments.target.rstrip("/")
    		if arguments.proxy:
    		    proxies = {{ "http": arguments.proxy, "https": arguments.proxy }}
    		else:
    		    proxies = None

				urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

				{}


			if __name__ == "__main__":
				main()
			]],
			{ f(function()
				return vim.fn.expand("%:t")
			end, {}), i(1) }
		)
	),
})
