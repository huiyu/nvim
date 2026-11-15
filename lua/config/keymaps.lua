-- Key choices only. Each owner installs actions in its own mode/lifecycle.
return {
  leader = " ",
  localleader = ",",
  open = {
    vsplit = { key = "<C-v>", desc = "Open in vertical split" },
    split = { key = "<C-s>", desc = "Open in horizontal split" },
    tab = { key = "<C-t>", desc = "Open in tab" },
    preview = { key = "<M-p>", desc = "Preview" },
  },
  ai = {
    new_chat = "<leader>an", switch_chat = "<leader>al", toggle = "<leader>ac", focus = "<leader>af",
    resume = "<leader>ar", continue = "<leader>aR", select_model = "<leader>am",
    add_buffer = "<leader>ab", send_selection = "<leader>as", compose = "<leader>ai",
    transcript = "<leader>at", transcript_pick = "<leader>aT", review = "<leader>av", new_round = "<leader>aV",
    key = "<leader>ax", history = "<leader>ao", inline = "<leader>ae",
  },
}
