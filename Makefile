MINI_PATH ?= deps/mini.nvim
NVIM_BIN ?= nvim

.PHONY: test test-file

test: $(MINI_PATH)
	MINI_NVIM_PATH="$(MINI_PATH)" $(NVIM_BIN) --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

test-file: $(MINI_PATH)
	MINI_NVIM_PATH="$(MINI_PATH)" $(NVIM_BIN) --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('$(FILE)')"

$(MINI_PATH):
	mkdir -p $(@D)
	git clone --filter=blob:none https://github.com/nvim-mini/mini.nvim $@
