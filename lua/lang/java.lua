local function ready(ctx)
  if #vim.lsp.get_clients({ name = "jdtls", bufnr = ctx.bufnr }) == 0 or not require("dap").adapters.java then
    vim.notify("Wait for jdtls and its Java debug bundle to attach", vim.log.levels.WARN)
    return false
  end
  return true
end

local function debug_file(ctx)
  if not ready(ctx) then return end
  local classname = require("jdtls.util").resolve_classname()
  require("jdtls.dap").fetch_main_configs({}, function(configs)
    local candidates = vim.tbl_filter(function(config)
      return config.mainClass == classname or vim.startswith(config.mainClass, classname .. "$")
    end, configs)
    if #candidates == 0 then
      vim.notify("No Java main class found in " .. ctx.path, vim.log.levels.WARN)
    elseif #candidates == 1 then
      require("dap").run(candidates[1])
    else
      vim.ui.select(candidates, { prompt = "Debug main class:", format_item = function(c) return c.name end },
        function(config) if config then require("dap").run(config) end end)
    end
  end)
end

local attach_aware_adapter

local function enable_attach()
  local dap = require("dap")
  if dap.adapters.java == attach_aware_adapter then return end
  local adapter = dap.adapters.java
  attach_aware_adapter = function(callback, config)
    adapter(function(resolved)
      -- nvim-jdtls enriches every request with launch-only main/class paths.
      -- JDWP attach needs no main class (e.g. a container or application server).
      if config.request == "attach" then resolved.enrich_config = nil end
      callback(resolved)
    end, config)
  end
  dap.adapters.java = attach_aware_adapter
end

return {
  {
    "mfussenegger/nvim-dap",
    opts = {
      configurations = { java = {
        { name = "java: attach to JDWP", type = "java", request = "attach",
          hostName = function() return require("util.dap").input("JDWP host: ", "127.0.0.1") end,
          port = function() return require("util.dap").port(5005) end,
          cwd = function()
            local client = vim.lsp.get_clients({ name = "jdtls", bufnr = 0 })[1]
            return client and client.config.root_dir or vim.fn.getcwd()
          end },
      } },
      targets = { java = {
      file = debug_file,
      test = function(ctx)
        if ready(ctx) then require("jdtls").test_nearest_method({ bufnr = ctx.bufnr, lnum = ctx.line - 1 }) end
      end,
      test_file = function(ctx)
        -- jdtls exposes class-level testing; a Java source normally owns one
        -- top-level test class. Keep its supported API and document that scope.
        if ready(ctx) then require("jdtls").test_class({ bufnr = ctx.bufnr }) end
      end,
      } },
    },
  },
  {
    "mfussenegger/nvim-jdtls",
    ft = "java",
    dependencies = {
      "williamboman/mason.nvim",
      "mfussenegger/nvim-dap",
    },
    config = function()
      local function start()
        local jdtls = require("jdtls")
        local mason_registry = require("mason-registry")

        local mason_path = vim.fn.stdpath("data") .. "/mason/packages"
        local jdtls_pkg = mason_registry.get_package("jdtls")
        if not jdtls_pkg:is_installed() then
          vim.notify("jdtls not installed. Run :MasonInstall jdtls", vim.log.levels.WARN)
          return
        end
        local jdtls_install = mason_path .. "/jdtls"
        local system = vim.fn.has("mac") == 1 and "mac" or "linux"

        -- Collect debug and test bundles
        local bundles = {}

        -- java-debug-adapter
        local java_debug = mason_registry.get_package("java-debug-adapter")
        if java_debug:is_installed() then
          local debug_path = mason_path .. "/java-debug-adapter"
          local debug_jars = vim.fn.glob(debug_path .. "/extension/server/com.microsoft.java.debug.plugin-*.jar", true, true)
          vim.list_extend(bundles, debug_jars)
        end

        -- java-test
        local java_test = mason_registry.get_package("java-test")
        if java_test:is_installed() then
          local test_path = mason_path .. "/java-test"
          local test_jars = vim.fn.glob(test_path .. "/extension/server/*.jar", true, true)
          for _, jar in ipairs(test_jars) do
            local name = vim.fs.basename(jar)
            if name ~= "com.microsoft.java.test.runner-jar-with-dependencies.jar" and name ~= "jacocoagent.jar" then
              table.insert(bundles, jar)
            end
          end
        end

        -- Lombok
        local lombok_path = jdtls_install .. "/lombok.jar"

        -- Resolve a java binary portably: $JAVA_HOME, then sdkman, then PATH.
        local function find_java()
          local candidates = {}
          if vim.env.JAVA_HOME and vim.env.JAVA_HOME ~= "" then
            table.insert(candidates, vim.env.JAVA_HOME .. "/bin/java")
          end
          table.insert(candidates, vim.fn.expand("~/.sdkman/candidates/java/current/bin/java"))
          for _, bin in ipairs(candidates) do
            if vim.fn.executable(bin) == 1 then return bin end
          end
          return vim.fn.executable("java") == 1 and vim.fn.exepath("java") or nil
        end

        local java_bin = find_java()
        if not java_bin then
          vim.notify("jdtls: no java found (checked $JAVA_HOME, sdkman, PATH)", vim.log.levels.ERROR)
          return
        end

        local root = require("jdtls.setup").find_root({ "mvnw", "gradlew", "pom.xml", "build.gradle", "build.gradle.kts", ".git" })
          or vim.fs.dirname(vim.api.nvim_buf_get_name(0))
        local config = {
          cmd = {
            java_bin,
            "-Declipse.application=org.eclipse.jdt.ls.core.id1",
            "-Dosgi.bundles.defaultStartLevel=4",
            "-Declipse.product=org.eclipse.jdt.ls.core.product",
            "-Dlog.protocol=true",
            "-Dlog.level=ALL",
            "-Xmx1g",
            "--add-modules=ALL-SYSTEM",
            "--add-opens", "java.base/java.util=ALL-UNNAMED",
            "--add-opens", "java.base/java.lang=ALL-UNNAMED",
            "-javaagent:" .. lombok_path,
            "-jar", vim.fn.glob(jdtls_install .. "/plugins/org.eclipse.equinox.launcher_*.jar"),
            "-configuration", jdtls_install .. "/config_" .. system,
            "-data", vim.fn.stdpath("cache") .. "/jdtls/" .. vim.fn.sha256(root),
          },
          root_dir = root,
          settings = {
            java = {
              eclipse = {
                downloadSources = true,
              },
              configuration = {
                updateBuildConfiguration = "interactive",
              },
              maven = {
                downloadSources = true,
              },
              implementationsCodeLens = {
                enabled = true,
              },
              referencesCodeLens = {
                enabled = true,
              },
              references = {
                includeDecompiledSources = true,
              },
              inlayHints = {
                parameterNames = { enabled = "all" },
              },
              format = {
                enabled = true,
              },
            },
            signatureHelp = { enabled = true },
            completion = {
              favoriteStaticMembers = {
                "org.hamcrest.MatcherAssert.assertThat",
                "org.hamcrest.Matchers.*",
                "org.hamcrest.CoreMatchers.*",
                "org.junit.jupiter.api.Assertions.*",
                "java.util.Objects.requireNonNull",
                "java.util.Objects.requireNonNullElse",
                "org.mockito.Mockito.*",
              },
            },
            contentProvider = { preferred = "fernflower" },
            extendedClientCapabilities = jdtls.extendedClientCapabilities,
            sources = {
              organizeImports = {
                starThreshold = 9999,
                staticStarThreshold = 9999,
              },
            },
            codeGeneration = {
              toString = {
                template = "${object.className}{${member.name()}=${member.value}, ${otherMembers}}",
              },
              useBlocks = true,
            },
          },
          flags = {
            allow_incremental_sync = true,
          },
          init_options = {
            bundles = bundles,
          },
        }

        -- Setup DAP after jdtls attaches
        config.on_attach = function(_, bufnr)
          if #vim.fn.glob(mason_path .. "/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar", true, true) == 0 then
            vim.notify("Java debugging needs :MasonInstall java-debug-adapter, then :JdtRestart", vim.log.levels.WARN)
            return
          end
          -- nvim-jdtls discovers main classes on each dap.continue(). Eager
          -- discovery disables that provider and leaves stale cross-project configs.
          local ok, err = pcall(jdtls.setup_dap, { hotcodereplace = "auto" })
          if not ok then
            vim.notify("Java DAP setup failed: " .. tostring(err), vim.log.levels.ERROR)
            return
          end
          enable_attach()
          vim.keymap.set("n", "<localleader>dt", jdtls.test_nearest_method,
            { buffer = bufnr, desc = "[LSP] Debug Java Test Method" })
          vim.keymap.set("n", "<localleader>dT", jdtls.test_class,
            { buffer = bufnr, desc = "[LSP] Debug Java Test Class" })
        end

        local ok, err = pcall(jdtls.start_or_attach, config)
        if not ok then
          vim.notify("jdtls.start_or_attach error: " .. tostring(err), vim.log.levels.ERROR)
        end
      end
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "java",
        group = vim.api.nvim_create_augroup("java_jdtls", { clear = true }),
        callback = start,
      })
      start()
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      tools = {
        ["jdtls"] = {},
        ["java-debug-adapter"] = {},
        ["java-test"] = {},
      },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "java" } },
  },
}
