local t = dofile("tests/helper.lua")

local function mapping(lhs, mode)
  return vim.fn.maparg(lhs, mode or "n", false, true)
end

-- Buffer cycling has one fast pair and one discoverable bracket pair. Tab must
-- remain native so legacy terminals can still send <C-I> for jumplist-forward.
t.eq(mapping("<Tab>"), {}, "Tab is not repurposed for buffer cycling")
t.eq(mapping("<S-Tab>"), {}, "Shift-Tab is not repurposed for buffer cycling")
t.ok(mapping("<S-h>").desc == "Prev buffer", "Shift-H cycles to the previous buffer")
t.ok(mapping("<S-l>").desc == "Next buffer", "Shift-L cycles to the next buffer")
t.ok(mapping("[b").desc == "Prev buffer", "[b keeps bracket navigation")
t.ok(mapping("]b").desc == "Next buffer", "]b keeps bracket navigation")

-- Todo search belongs to the location namespace exactly once. Bracket keys
-- remain the sequential navigation form; the old Diagnostics aliases stay gone.
t.ok(mapping(";t").desc == "Todos", ";t finds todos")
t.ok(mapping(";T").desc == "Todo/Fix/Fixme", ";T finds actionable todos")
t.eq(mapping("<leader>xt"), {}, "Diagnostics no longer duplicates Todo search")
t.eq(mapping("<leader>xT"), {}, "Diagnostics no longer duplicates filtered Todo search")
t.ok(mapping("[t").desc == "Prev todo", "[t keeps previous-Todo navigation")
t.ok(mapping("]t").desc == "Next todo", "]t keeps next-Todo navigation")

t.done()
