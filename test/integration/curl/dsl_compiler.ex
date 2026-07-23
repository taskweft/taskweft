#!/usr/bin/env elixir
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
# Compiler for Elixir DSL to JSON-LD

IO.puts("Compiling DSL...")
{:ok, json} = Taskweft.Domain.SafeParser.parse_file(Param.input)
IO.puts(json)