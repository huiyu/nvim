return {
  {
    "mfussenegger/nvim-jdtls",
    ft = "java",
    dependencies = {
      "williamboman/mason.nvim",
      "mfussenegger/nvim-dap",
    },
    config = function()
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
        local test_jars = vim.fn.glob(test_path .. "/extension/server/com.microsoft.java.test.plugin-*.jar", true, true)
        vim.list_extend(bundles, test_jars)
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
          "-data", vim.fn.expand("~/.cache/jdtls-workspace") .. vim.fn.getcwd(),
        },
        root_dir = require("jdtls.setup").find_root({ ".git", "mvnw", "gradlew", "pom.xml", "build.gradle" }),
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
      config.on_attach = function()
        pcall(function()
          jdtls.setup_dap({ hotcodereplace = "auto" })
          require("jdtls.dap").setup_dap_main_class_configs()
        end)
      end

      local ok, err = pcall(jdtls.start_or_attach, config)
      if not ok then
        vim.notify("jdtls.start_or_attach error: " .. tostring(err), vim.log.levels.ERROR)
      end
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
