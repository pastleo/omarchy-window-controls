.PHONY: test validate

test:
	lua tests/runtime.lua
	lua tests/resize-settings.lua
	lua tests/input-model.lua
	node tests/window-geometry.cjs
	node tests/runtime-code.cjs
	node tests/compatibility.cjs
	node tests/menu-actions.cjs

validate:
	luac -p hypr/*.lua
	omarchy plugin validate "$(CURDIR)"
