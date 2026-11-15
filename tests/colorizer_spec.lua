local t = dofile("tests/helper.lua")
local a = vim.api

-- Inspect real highlights so valid color options cannot silently stop working.
vim.cmd("edit " .. vim.fn.fnameescape(vim.fn.tempname() .. ".css"))
a.nvim_buf_set_lines(0, 0, -1, false, {
  ":root {",
  "  --brand: #ff0000;",
  "  color: rgb(0, 255, 0);",
  "  background: hsl(240, 100%, 50%);",
  "  border-color: var(--brand);",
  "}",
})
local colorizer = require("colorizer")
colorizer.attach_to_buffer(0)
local ns = require("colorizer.constants").namespace.default
local function colors()
  local found = {}
  for _, mark in ipairs(a.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
    local hl = mark[4].hl_group
    if hl then found[mark[2]] = a.nvim_get_hl(0, { name = hl, link = false }).bg end
  end
  return found
end
t.ok(vim.wait(1000, function() return colors()[4] ~= nil end, 10), "CSS variable reference receives a color")
t.eq(colors()[1], 0xff0000, "hex preview is preserved")
t.eq(colors()[2], 0x00ff00, "RGB preview renders green")
t.eq(colors()[3], 0x0000ff, "HSL preview renders blue")
t.eq(colors()[4], 0xff0000, "CSS variable preview resolves the local definition")
vim.bo.modified = false
for _, ft in ipairs({ "html", "text" }) do
  vim.cmd.enew()
  vim.bo.filetype = ft
  a.nvim_buf_set_lines(0, 0, -1, false, { '<div class="bg-blue-500">' })
  colorizer.attach_to_buffer(0)
  t.eq(colors()[0] ~= nil, ft == "html", "Tailwind class preview is scoped to frontend files: " .. ft)
  vim.bo.modified = false
end

t.done()
