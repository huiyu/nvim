local api_key = os.getenv("DMX_API_KEY")
local api_base = os.getenv("DMX_HOST")

return {
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter"
    },
    opts = function()
      return {
        strategies = {
          chat = {
            adapter = "dmx_anthropic",
          },
          inline = {
            adapter = "dmx_anthropic",
          }
        },
        adapters = {
          dmx_deepseek = function()
            return require("codecompanion.adapters").extend("openai_compatible", {
              env = {
                url = api_base,
                api_key = api_key,
                chat_url = "/v1/chat/completions",
              },
              schema = {
                model = {
                  default = "deepseek-v3"
                }
              }
            })
          end,
          dmx_anthropic = function()
            return require("codecompanion.adapters").extend("openai_compatible", {
              env = {
                url = api_base,
                api_key = api_key,
                chat_url = "/v1/chat/completions",
              },
              schema = {
                model = {
                  default = "claude-3-7-sonnet-20250219",
                }
              }
            })
          end,
        }
      }
    end
  }
}
