---@module "lang.java"
---Java development support using Eclipse JDT Language Server
---
---Provides comprehensive Java language support including:
---  - LSP features (completion, diagnostics, formatting)
---  - Debugging support through DAP
---  - Build tool integration (Maven, Gradle)
---  - Source code management and refactoring
---
---@example
---# Automatically activates for .java files
---# Provides features like:
---#   - Intelligent code completion
---#   - Error detection and quick fixes
---#   - Refactoring tools
---#   - Debug support

return {
  {
    "mfussenegger/nvim-jdtls",
    ft = "java",  -- Load only for Java files
    dependencies = {
      "williamboman/mason.nvim",  -- Package manager for LSP servers
      "mfussenegger/nvim-dap",    -- Debug adapter support
    },
    config = function()
      local jdtls = require("jdtls")
      local mason_registry = require("mason-registry")
      
      -- Detect system type and get JDTLS installation path
      local jdtls_install = mason_registry.get_package("jdtls"):get_install_path()
      local system = vim.fn.has("mac") == 1 and "mac" or "linux"
      
      -- JDTLS configuration
      local config = {
        -- Command to start JDTLS with appropriate JVM settings
        cmd = {
          "java",
          "-Declipse.application=org.eclipse.jdt.ls.core.id1",  -- Eclipse app ID
          "-Dosgi.bundles.defaultStartLevel=4",                 -- OSGi bundle start level
          "-Declipse.product=org.eclipse.jdt.ls.core.product",   -- Eclipse product ID
          "-Dlog.protocol=true",                               -- Enable protocol logging
          "-Dlog.level=ALL",                                   -- Log level
          "-Xmx1g",                                            -- Max heap size
          "--add-modules=ALL-SYSTEM",                          -- Java module system
          "--add-opens", "java.base/java.util=ALL-UNNAMED",     -- Open Java internals
          "--add-opens", "java.base/java.lang=ALL-UNNAMED",     -- Required for Java 17+
          "-jar", vim.fn.glob(jdtls_install .. "/plugins/org.eclipse.jdt.ls.core_*.jar"),
          "-configuration", jdtls_install .. "/config_" .. system,  -- Platform-specific config
          "-data", vim.fn.expand("~/.cache/jdtls-workspace") .. vim.fn.getcwd(),  -- Workspace data
        },
        -- Determine project root by looking for common Java project files
        root_dir = require("jdtls.setup").find_root({ ".git", "mvnw", "gradlew", "pom.xml", "build.gradle" }),
        settings = {
          java = {
            -- Eclipse JDT settings
            eclipse = {
              downloadSources = true,  -- Download source jars for dependencies
            },
            configuration = {
              updateBuildConfiguration = "interactive",  -- Prompt for build config updates
            },
            maven = {
              downloadSources = true,  -- Download Maven source attachments
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
            format = {
              enabled = true,
            },
          },
          signatureHelp = { enabled = true },
          completion = {
            -- Static imports to suggest in completion
            favoriteStaticMembers = {
              "org.hamcrest.MatcherAssert.assertThat",   -- Hamcrest testing
              "org.hamcrest.Matchers.*",
              "org.hamcrest.CoreMatchers.*",
              "org.junit.jupiter.api.Assertions.*",      -- JUnit 5 assertions
              "java.util.Objects.requireNonNull",        -- Null checking
              "java.util.Objects.requireNonNullElse",
              "org.mockito.Mockito.*",                   -- Mockito mocking
            },
          },
          contentProvider = { preferred = "fernflower" },
          extendedClientCapabilities = jdtls.extendedClientCapabilities,
          sources = {
            organizeImports = {
              starThreshold = 9999,       -- Threshold for using star imports
              staticStarThreshold = 9999, -- Threshold for static star imports
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
          bundles = {},
        },
      }
      
      -- Start or attach to existing JDTLS instance
      jdtls.start_or_attach(config)
    end,
  },
}
