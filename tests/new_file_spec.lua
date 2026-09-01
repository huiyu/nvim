local t = dofile("tests/helper.lua")

local path = vim.fn.tempname() .. ".lua"
t.eq(vim.fn.filereadable(path), 0, "new-file fixture does not exist")
vim.cmd("edit " .. vim.fn.fnameescape(path))

t.ok(vim.wait(1000, function() return package.loaded.incline ~= nil end, 10),
  "Incline loads for a new unsaved file")
t.ok(vim.wait(1000, function() return package.loaded["mini.bracketed"] ~= nil end, 10),
  "mini.bracketed loads for a new unsaved file")

t.done()
