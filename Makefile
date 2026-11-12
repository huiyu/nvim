# Everyday commands for this config. `make` or `make help` lists them.
# They run against this checkout as the Neovim config, as tests/run.sh and
# the CI workflow do (AGENTS.md, Validation).

# Not NVIM: inside an Nvim terminal that variable is the parent's socket, and
# make takes a variable's default from the environment.
NVIM_BIN ?= nvim
S ?=
HEADLESS = $(NVIM_BIN) --headless -u init.lua -i NONE
# A headless `+qa` exits 0 even when init.lua raised, so ask v:errmsg.
ERRMSG = '+lua if vim.v.errmsg ~= "" then print(vim.v.errmsg) vim.cmd("cquit 1") end'

.DEFAULT_GOAL := help
.PHONY: help test startup check verify health profile deps

help: ## List the commands
	@awk 'BEGIN { FS = ":.*## " } /^[a-z]+:.*## / { printf "  make %-8s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

test: ## Run every spec; S="hunk_actions codediff" runs some
	@./tests/run.sh $(S)

startup: ## Start headless and fail on any startup error
	@$(HEADLESS) $(ERRMSG) +qa && echo "startup: ok"

check: ## Whitespace errors in unstaged and staged changes
	@git diff --check && git diff --cached --check && echo "check: ok"

verify: check startup test ## Everything to run before a change lands (what CI runs)

health: ## Print :checkhealth config
	@$(HEADLESS) '+checkhealth config' \
	  '+lua io.stdout:write(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n") .. "\n")' \
	  +qa 2>/dev/null

profile: ## The slowest steps of a headless startup (plugins loaded later are not in it)
	@f=$$(mktemp); $(HEADLESS) --startuptime "$$f" +qa; \
	  echo "  clock   self+src  self    step"; sort -k2 -rn "$$f" | head -15; rm -f "$$f"

deps: ## Install what the specs need: missing plugins, Mason packages, CodeDiff's library
	@$(HEADLESS) '+Lazy! install' $(ERRMSG) +qa
	@$(HEADLESS) '+Lazy! load nvim-lspconfig nvim-dap' '+luafile .github/mason-wait.lua' +qa
	@$(HEADLESS) '+Lazy! load codediff.nvim' +qa
	@# mason-wait.lua's last line ends without a newline.
	@printf '\ndeps: ok\n'
