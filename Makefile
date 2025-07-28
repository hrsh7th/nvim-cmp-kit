DENO_DIR := ${PWD}/.deno_dir

.PHONY: lint
lint:
	docker run -v $(PWD):/code -i registry.gitlab.com/pipeline-components/luacheck:latest --codes /code/lua

.PHONY: format
format:
	docker run -v $(PWD):/src -i fnichol/stylua --config-path=/src/.stylua.toml -- /src/lua

.PHONY: test
test:
	TEST=1 vusted --output=gtest --pattern=.spec ./lua

.PHONY: update-emoji
update-emoji:
	nvim -l ./scripts/update-emoji.lua

