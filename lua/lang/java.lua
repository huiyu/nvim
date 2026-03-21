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

      local jdtls_install = mason_registry.get_package("jdtls"):get_install_path()
      local system = vim.fn.has("mac") == 1 and "mac" or "linux"

      -- Collect debug and test bundles
      local bundles = {}

      -- java-debug-adapter
      local java_debug = mason_registry.get_package("java-debug-adapter")
      if java_debug:is_installed() then
        local debug_path = java_debug:get_install_path()
        local debug_jars = vim.fn.glob(debug_path .. "/extension/server/com.microsoft.java.debug.plugin-*.jar", true, true)
        vim.list_extend(bundles, debug_jars)
      end

      -- java-test
      local java_test = mason_registry.get_package("java-test")
      if java_test:is_installed() then
        local test_path = java_test:get_install_path()
        local test_jars = vim.fn.glob(test_path .. "/extension/server/*.jar", true, true)
        vim.list_extend(bundles, test_jars)
      end

      -- Lombok
      local lombok_path = jdtls_install .. "/lombok.jar"

      local config = {
        cmd = {
          "java",
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
          "-jar", vim.fn.glob(jdtls_install .. "/plugins/org.eclipse.jdt.ls.core_*.jar"),
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

      jdtls.start_or_attach(config)
    end,
  },
  {
    "williamboman/mason.nvim",
    opts = {
      ensure_installed = {
        "jdtls",
        "java-debug-adapter",
        "java-test",
      },
    },
  },
}
