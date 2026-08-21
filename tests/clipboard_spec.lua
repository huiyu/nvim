-- Exercises the real system clipboard, so it saves whatever is on it first and
-- puts it back afterwards. A test run must not cost the user their clipboard.
local t = dofile("tests/helper.lua")
local clipboard = require("ai.clipboard")

local is_macos = vim.uv.os_uname().sysname == "Darwin"
if not is_macos then
  t.ok(clipboard.has_image() == false, "non-macOS reports no clipboard image rather than raising")
  local ok, err = clipboard.save_image(vim.fn.tempname() .. ".png")
  t.ok(ok == false and type(err) == "string", "non-macOS fails with a reason")
  t.done()
  return
end

local fixture = vim.fn.fnamemodify("tests/fixtures/pixel.png", ":p")

-- Snapshot the user's clipboard before touching it.
local saved_image, saved_text
if clipboard.has_image() then
  local path = vim.fn.tempname() .. ".png"
  if clipboard.save_image(path) then saved_image = path end
else
  saved_text = vim.fn.getreg("+")
end

local function restore_user_clipboard()
  if saved_image then
    clipboard.restore_image(saved_image)
    vim.fn.delete(saved_image)
  elseif saved_text then
    vim.fn.setreg("+", saved_text)
  end
end

local ok, err = pcall(function()
  -- Putting a PNG on the clipboard must be detectable.
  local restored, restore_err = clipboard.restore_image(fixture)
  t.ok(restored, "restore_image puts a PNG on the clipboard" .. (restored and "" or (": " .. tostring(restore_err))))
  t.ok(clipboard.has_image(), "has_image sees the PNG")

  -- And reading it back must produce a real PNG file.
  local out = vim.fn.tempname() .. ".png"
  local saved, save_err = clipboard.save_image(out)
  t.ok(saved, "save_image writes the clipboard image" .. (saved and "" or (": " .. tostring(save_err))))
  if saved then
    local handle = io.open(out, "rb")
    local magic = handle and handle:read(8)
    if handle then handle:close() end
    t.eq(magic, "\137PNG\r\n\26\n", "the saved file carries the PNG magic bytes")
    vim.fn.delete(out)
  end

  -- Text on the clipboard is not an image. This is the case that matters: a
  -- yank inside the composer must not look like a pending screenshot.
  vim.fn.setreg("+", "a yanked line")
  t.ok(not clipboard.has_image(), "a text clipboard reports no image")

  -- Guard rails.
  local bad_ok, bad_err = clipboard.save_image('/tmp/eviltest".png')
  t.ok(bad_ok == false and type(bad_err) == "string", "a path with a quote is refused")

  local missing_ok, missing_err = clipboard.restore_image(vim.fn.tempname() .. ".png")
  t.ok(missing_ok == false and type(missing_err) == "string", "restoring a missing file fails with a reason")

  -- The staging directory must exist and be per-process.
  local dir = clipboard.staging_dir()
  t.ok(vim.fn.isdirectory(dir) == 1, "staging_dir creates its directory")
  t.ok(dir:find(tostring(vim.fn.getpid()), 1, true) ~= nil, "staging_dir is namespaced per Nvim process")
  vim.fn.delete(dir, "rf")
end)

restore_user_clipboard()

if not ok then error(err, 0) end
t.done()
