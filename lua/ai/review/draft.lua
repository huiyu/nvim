-- Review draft data and persistence. No buffers, windows, notifications or
-- delivery policy live here. A document's nonce distinguishes its structure
-- from quoted text; concurrent editors merge blocks against their last read.
-- All lasting writes replace a file atomically beside the original.
local M = { STALE = "⚠ changed since this comment" }

local uv = vim.uv
local INTRO = "^Review of changes .+ in .+:$"

---@return string? text nil when the file cannot be read (missing, a directory)
local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

--- Replace `path` in one step, through a temporary file beside it: another
--- Nvim reading the draft meanwhile sees the old text or the new, never half.
---@return boolean ok, string? err
local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local tmp = ("%s.%d.tmp"):format(path, uv.os_getpid())
  local f, err = io.open(tmp, "wb")
  if not f then return false, err end
  local ok, werr = f:write(text)
  f:close()
  if not ok then
    os.remove(tmp)
    return false, werr
  end
  local renamed, rerr = uv.fs_rename(tmp, path)
  if not renamed then
    os.remove(tmp)
    return false, rerr
  end
  return true
end

local function split(text)
  if text == nil or text == "" then return {} end
  local lines = vim.split(text, "\n", { plain = true })
  if lines[#lines] == "" then table.remove(lines) end
  return lines
end

local function join(lines)
  return #lines == 0 and "" or table.concat(lines, "\n") .. "\n"
end

--- The content of the working-tree file `path` (relative to `root`), as the
--- digest a review-item carries; "none" for a file that is not there.
function M.digest(root, path)
  local text = read(root .. "/" .. path)
  if text == nil then return "none" end
  return "sha256:" .. vim.fn.sha256(text)
end

--- An attribute value: bare when it is plainly a word, a JSON string otherwise.
local function bare(value)
  if value:match("^[%w_.:@+-]+$") then return value end
  return vim.json.encode(value)
end

--- The first header or marker in `line` from byte `from` on, whatever its
--- nonce: where it starts and ends, its kind ("" for the header, "-intro",
--- "-item") and its attributes (`key=value key="json string" ...`). Wherever it
--- is in the line: a J or a key typed after "-->" leaves it whole. A quoted
--- value may hold anything, "-->" included.
---@return integer? start, integer? stop, string? kind, table<string, string>? attrs
local function scan(line, from)
  if type(line) ~= "string" then return nil end
  from = from or 1
  while true do
    local s, e, kind = line:find("<!%-%- nvim%-review(%S*) ", from)
    if not s then return nil end
    local attrs, i = {}, e + 1
    while true do
      i = line:find("[^ ]", i) or #line + 1
      if line:sub(i, i + 2) == "-->" then return s, i + 2, kind, attrs end
      local _, ke, key = line:find("^([%w_]+)=", i)
      if not ke then break end
      i = ke + 1
      local value
      if line:sub(i, i) == '"' then
        local j = i + 1
        while j <= #line and line:sub(j, j) ~= '"' do
          j = j + (line:sub(j, j) == "\\" and 2 or 1)
        end
        local ok, decoded = pcall(vim.json.decode, line:sub(i, j))
        if j > #line or not ok or type(decoded) ~= "string" then break end
        value, i = decoded, j + 1
      else
        value = line:match("^[%w_.:@+-]+", i)
        if not value then break end
        i = i + #value
      end
      attrs[key] = value
    end
    from = s + 1
  end
end

---@class ai.review.DraftHeader
---@field n string the draft's nonce
---@field round string the round id, or "unowned"
---@field sha? string
---@field conversation? string
---@field root string

---@param h ai.review.DraftHeader
local function header_line(h)
  local parts = { "n=" .. bare(h.n), "round=" .. bare(h.round) }
  if h.sha then parts[#parts + 1] = "sha=" .. bare(h.sha) end
  if h.conversation then parts[#parts + 1] = "conversation=" .. bare(h.conversation) end
  parts[#parts + 1] = "root=" .. vim.json.encode(h.root)
  return ("<!-- nvim-review %s -->"):format(table.concat(parts, " "))
end

--- The header `line` opens with, if any.
---@return ai.review.DraftHeader?
local function parse_header(line)
  local s, _, kind, a = scan(line)
  if s ~= 1 or kind ~= "" or not a.n or a.n == "" or not a.round or not a.root or a.root == "" then return nil end
  return { n = a.n, round = a.round, sha = a.sha, conversation = a.conversation, root = a.root }
end

--- A nonce for a new draft: random, so no file an entry quotes holds it.
local function new_nonce()
  local ok, bytes = pcall(uv.random, 6)
  if ok and type(bytes) == "string" and #bytes == 6 then
    return (bytes:gsub(".", function(c) return ("%02x"):format(c:byte()) end))
  end
  return vim.fn.sha256(("%d %d %s"):format(uv.os_getpid(), uv.hrtime(), tostring({}))):sub(1, 12)
end

local issued = 0
--- A block id no other Nvim's can equal: this process, a count, the time.
local function new_id()
  issued = issued + 1
  return ("%d.%d.%d"):format(uv.os_getpid(), issued, uv.hrtime())
end

---@class ai.review.Block
---@field kind "text"|"intro"|"item" "text" is what comes before the first marker
---@field id string "" for the text block
---@field attrs? { path?: string, side?: string, digest?: string } an item's
---@field lines string[] the lines after its marker, up to the next one

---@class ai.review.Doc
---@field head? ai.review.DraftHeader
---@field blocks ai.review.Block[] the text block first, always

--- The blocks of `lines`, read with nonce `n`: only a header or marker
--- carrying it is structure, and everything else is text, whatever it looks
--- like. One that shares its line (joined on, or typed after) splits it: what
--- comes before is the previous block's line, what comes after its own first
--- one -- render puts it back on a line of its own. A header of this draft is
--- dropped wherever it is (it is metadata: render writes it on line 1), and so
--- is a marker whose id came already (a pasted copy), so that what follows
--- stays with the block before it.
---@param n? string nil: no structure at all
---@return ai.review.Block[]
local function parse(lines, n)
  local blocks = { { kind = "text", id = "", lines = {} } }
  local seen, cur = {}, blocks[1]
  local function add(text) cur.lines[#cur.lines + 1] = text end
  for _, line in ipairs(lines) do
    local rest, from, found = line, 1, false
    while n do
      local s, e, kind, a = scan(rest, from)
      if not s then break end
      if a.n ~= n then
        -- Another draft's: text.
        from = e + 1
      else
        found = true
        local before = rest:sub(1, s - 1)
        if before:find("%S") then add(before) end
        rest = rest:sub(e + 1):gsub("^%s+", "")
        from = 1
        if (kind == "-intro" or kind == "-item") and type(a.id) == "string" and a.id ~= "" and not seen[a.id] then
          seen[a.id] = true
          cur = { kind = kind:sub(2), id = a.id, lines = {} }
          if kind == "-item" then cur.attrs = { path = a.path, side = a.side, digest = a.digest } end
          blocks[#blocks + 1] = cur
        end
      end
    end
    if not found then
      add(line)
    elseif rest:find("%S") then
      add(rest)
    end
  end
  return blocks
end

--- A draft's lines as its header and blocks. Its first line names its nonce;
--- lines with no header there (an emptied file, a header deleted in the float)
--- are read with `known`, the header this Nvim last saw for the draft.
---@param known? ai.review.DraftHeader
---@return ai.review.Doc
function M.decode(lines, known)
  local head = parse_header(lines[1]) or known
  return { head = head, blocks = parse(lines, head and head.n) }
end

local function read_doc(text, known)
  return M.decode(split(text), known)
end

--- The lines of `doc`: its header, then every block under its marker.
---@param doc ai.review.Doc
local function render(doc)
  local h, out = doc.head, {}
  if h then out[1] = header_line(h) end
  for _, b in ipairs(doc.blocks) do
    if h and b.kind == "intro" then
      out[#out + 1] = ("<!-- nvim-review-intro n=%s id=%s -->"):format(bare(h.n), bare(b.id))
    elseif h and b.kind == "item" then
      local a = b.attrs or {}
      out[#out + 1] = ("<!-- nvim-review-item n=%s id=%s path=%s side=%s digest=%s -->"):format(bare(h.n),
        bare(b.id), vim.json.encode(a.path or ""), vim.json.encode(a.side or ""), vim.json.encode(a.digest or ""))
    end
    vim.list_extend(out, b.lines)
  end
  return out
end

local function has_text(lines)
  for _, line in ipairs(lines) do
    if vim.trim(line) ~= "" then return true end
  end
  return false
end

--- What the agent is sent: every block's lines, without the header and the
--- markers, blank lines trimmed at both ends; "" when it holds no feedback.
--- An intro's line is none, also once its marker is gone and it reads as
--- text: a draft left with only that would otherwise spare its round and be
--- sent.
---@param doc ai.review.Doc
function M.message(doc)
  local out, content = {}, false
  for _, b in ipairs(doc.blocks) do
    for _, line in ipairs(b.lines) do
      out[#out + 1] = line
      if not line:match(INTRO) and vim.trim(line) ~= "" then content = true end
    end
  end
  if not content then return "" end
  while vim.trim(out[1]) == "" do table.remove(out, 1) end
  while vim.trim(out[#out]) == "" do table.remove(out) end
  return table.concat(out, "\n")
end

local function last_intro(doc)
  for i = #doc.blocks, 1, -1 do
    local b = doc.blocks[i]
    if b.kind == "intro" then return b.lines[1] end
  end
end

--- Editable lines for a draft with no feedback left, whose file is
--- empty: its header and an intro -- the text of the last of the first of
--- `docs` that has one -- with a line to type on. What is typed there is
--- saved under that header. The intro is no block of the file but a
--- placeholder of this editor's (d.placeholder, an id of its own, kept while
--- its text is): save drops it untouched, and once another Nvim has started
--- the draft again, it stands for that draft's own intro (adopt).
---@param docs ai.review.Doc[]
---@return ai.review.Doc
local function template(d, docs)
  local head, line = d.head, nil
  for _, doc in ipairs(docs) do
    head = head or doc.head
    for i = #doc.blocks, 1, -1 do
      local b = doc.blocks[i]
      if not line and b.kind == "intro" and (b.lines[1] or ""):match(INTRO) then line = b.lines[1] end
    end
  end
  local blocks, p = { { kind = "text", id = "", lines = {} } }, nil
  if head and line then
    p = d.placeholder
    if not (p and p.lines[1] == line) then p = { kind = "intro", id = new_id(), lines = { line, "" } } end
    blocks[2] = vim.deepcopy(p)
  end
  d.placeholder = p
  return { head = head, blocks = blocks }
end

--- The changes that turn `base` into `lines`, each as the base lines it
--- replaces (lo+1..hi; none when lo == hi, an insertion there) and the new
--- ones.
---@return { lo: integer, hi: integer, new: string[] }[]
local function changes(base, lines)
  local out = {}
  for _, h in ipairs(vim.text.diff(join(base), join(lines), { result_type = "indices" })) do
    local lo = h[2] == 0 and h[1] or h[1] - 1
    out[#out + 1] = { lo = lo, hi = lo + h[2], new = vim.list_slice(lines, h[3], h[3] + h[4] - 1) }
  end
  return out
end

--- A three-way merge of two versions of one block against the one both
--- started from, line by line. Changes to different lines of `base` are both
--- made; two insertions at the same place are both kept, `theirs` (the
--- file's) first; a change both made alike is made once.
---@return string[]? merged nil when the two changed the same lines differently
local function merge3(base, ours, theirs)
  local list = changes(base, ours)
  local mine = #list
  for _, c in ipairs(changes(base, theirs)) do
    local dup = false
    for i = 1, mine do
      local o = list[i]
      if o.lo == c.lo and o.hi == c.hi and vim.deep_equal(o.new, c.new) then
        dup = true
      elseif o.lo < c.hi and c.lo < o.hi then
        return nil
      end
    end
    if not dup then
      c.theirs = true
      list[#list + 1] = c
    end
  end
  -- By position; at one position an insertion before a replacement, and
  -- theirs before ours. Neither side's own changes overlap, nor (checked) do
  -- the two sides'.
  table.sort(list, function(a, b)
    if a.lo ~= b.lo then return a.lo < b.lo end
    if a.hi ~= b.hi then return a.hi < b.hi end
    return a.theirs == true and not b.theirs
  end)
  local out, pos = {}, 0
  for _, c in ipairs(list) do
    for k = pos + 1, c.lo do out[#out + 1] = base[k] end
    vim.list_extend(out, c.new)
    pos = c.hi
  end
  for k = pos + 1, #base do out[#out + 1] = base[k] end
  return out
end

local function by_id(doc)
  local out = {}
  for _, b in ipairs(doc.blocks) do out[b.id] = b end
  return out
end

--- Whether two versions of a block say the same: blank lines at its end are
--- the gap before the next block, which an append adds.
local function same(a, b)
  local n, m = #a, #b
  while n > 0 and vim.trim(a[n]) == "" do n = n - 1 end
  while m > 0 and vim.trim(b[m]) == "" do m = m - 1 end
  if n ~= m then return false end
  for i = 1, n do
    if a[i] ~= b[i] then return false end
  end
  return true
end

--- Two versions of a draft merged against the one both started from, block by
--- block: the text before the first marker, and each intro and entry by id. A
--- block one side left as it was takes the other's version; one both changed
--- is merged line by line (merge3). A block the file no longer has was
--- delivered or deleted elsewhere: it stays gone. New blocks on either side
--- are kept: the file's in its order, this buffer's after the block they
--- follow here. The header is the file's, or this buffer's when the file has
--- none (emptied).
---@param base ai.review.Doc the file when this buffer last matched it
---@param ours ai.review.Doc this buffer
---@param theirs ai.review.Doc the file now
---@return ai.review.Doc merged
---@return { block: ai.review.Block, why: "clash"|"gone" }[] lost this buffer's version of blocks the file keeps its own of (changed in the same lines) or has no more
local function merge(base, ours, theirs)
  local B, O, T = by_id(base), by_id(ours), by_id(theirs)
  local out, lost = {}, {}
  for _, t in ipairs(theirs.blocks) do
    local o, was = O[t.id], B[t.id] and B[t.id].lines
    local keep = t
    if o then
      if not vim.deep_equal(o.lines, t.lines) and not vim.deep_equal(o.lines, was or {}) then
        if vim.deep_equal(t.lines, was or {}) then
          keep = o
        else
          local lines = merge3(was or {}, o.lines, t.lines)
          if lines then
            keep = vim.tbl_extend("force", t, { lines = lines })
          else
            lost[#lost + 1] = { block = o, why = "clash" }
          end
        end
      end
    elseif was and same(t.lines, was) then
      -- Deleted here, left as it was there.
      keep = nil
    end
    if keep then out[#out + 1] = keep end
  end
  for i, o in ipairs(ours.blocks) do
    if not T[o.id] then
      if B[o.id] then
        -- Delivered or deleted elsewhere: what was typed into it goes aside.
        if not same(o.lines, B[o.id].lines) then lost[#lost + 1] = { block = o, why = "gone" } end
      else
        -- New here: after the nearest block before it that is kept (the text
        -- block always is).
        local at
        for j = i - 1, 1, -1 do
          for k, b in ipairs(out) do
            if b.id == ours.blocks[j].id then at = k end
          end
          if at then break end
        end
        table.insert(out, (at or 1) + 1, o)
      end
    end
  end
  return { head = theirs.head or ours.head, blocks = out }, lost
end

--- Before a merge: the template's intro `p` is in no file. Once another Nvim
--- has started the draft again, it stands for the file's first intro of the
--- same text that this buffer has never seen -- its id, and the template's
--- lines as the base -- so what was typed under it goes under that one, and
--- an untouched one changes nothing. With none to stand for, one with nothing
--- typed in it is dropped; anything else in it is new here.
---@param p? ai.review.Block d.placeholder
local function adopt(p, base, ours, theirs)
  local B, O = by_id(base), by_id(ours)
  local o = p and O[p.id]
  if not o then return end
  if o.lines[1] == p.lines[1] then
    for _, t in ipairs(theirs.blocks) do
      if t.kind == "intro" and t.lines[1] == p.lines[1] and not B[t.id] and not O[t.id] then
        o.id = t.id
        base.blocks[#base.blocks + 1] = { kind = "intro", id = t.id, lines = vim.deepcopy(p.lines) }
        return
      end
    end
  end
  if same(o.lines, p.lines) or not has_text(o.lines) then
    for i, b in ipairs(ours.blocks) do
      if b == o then
        table.remove(ours.blocks, i)
        break
      end
    end
  end
end

--- Where a draft's version that lost a merge is written: beside it, under a
--- name no earlier one took.
local function conflict_path(path)
  local stem = (path:gsub("%.md$", ""))
  local candidate, n = stem .. ".conflict.md", 1
  while uv.fs_stat(candidate) do
    n = n + 1
    candidate = ("%s.conflict-%d.md"):format(stem, n)
  end
  return candidate
end

---@class ai.review.DraftConflict
---@field path string the protected local text's file
---@field clash boolean lines changed differently elsewhere
---@field gone boolean a changed block was delivered or deleted elsewhere
---@field err? string the protected copy could not be written

---@class ai.review.DraftWriteError
---@field err string
---@field conflict? ai.review.DraftConflict a copy already written by this save

--- Save the local versions that a merge cannot keep beside the draft.
--- The caller presents the outcome; a failed copy prevents the draft write.
local function set_aside(path, lost)
  local lines, clash, gone = {}, false, false
  for _, l in ipairs(lost) do
    if l.why == "clash" then clash = true else gone = true end
    local text = vim.deepcopy(l.block.lines)
    while #text > 0 and vim.trim(text[#text]) == "" do table.remove(text) end
    if #lines > 0 then lines[#lines + 1] = "" end
    vim.list_extend(lines, text)
  end
  local aside = conflict_path(path)
  local ok, err = write(aside, join(lines))
  return { path = aside, clash = clash, gone = gone, err = not ok and err or nil }, ok
end

--- The data an editor keeps between saves. It holds no buffer or window.
---@class ai.review.Draft
---@field path string
---@field disk string the file's text when the editor last matched it
---@field head? ai.review.DraftHeader the header last seen
---@field placeholder? ai.review.Block an intro shown while the file is empty

---@param path string
---@return ai.review.Draft
function M.open(path)
  return { path = path, disk = "" }
end

--- Read edited lines under the known header: deleting or moving that header
--- does not change the draft's identity or its delivery metadata.
local function edited(d, lines)
  local head = d.head or parse_header(lines[1])
  return { head = head, blocks = parse(lines, head and head.n) }
end

--- Remember a persisted version and return the editor's lines, preserving an
--- empty draft's header and last intro as a placeholder to type under.
local function remember(d, doc, text, before)
  d.head, d.disk = doc.head or d.head, text
  if M.message(doc) == "" then
    doc = template(d, vim.list_extend({ doc }, before))
  else
    d.placeholder = nil
  end
  local lines = render(doc)
  return #lines == 0 and { "" } or lines
end

--- Read the file anew. `lines` supplies an open editor's previous intro when
--- the file was emptied elsewhere; without one, this is an initial load.
---@param d ai.review.Draft
---@param lines? string[]
---@return string[]
function M.reload(d, lines)
  local doc, text = M.read(d.path, d.head)
  return remember(d, doc, text, { edited(d, lines or {}) })
end

--- Merge edited lines with the current file, protecting conflicting local
--- text in a separate file before replacing the draft. An empty document is
--- stored as an empty file so it no longer exempts a round from retention.
---@param d ai.review.Draft
---@param lines string[]
---@return string[]? shown nil on a write failure
---@return ai.review.DraftConflict|ai.review.DraftWriteError? outcome
function M.save(d, lines)
  local ours = edited(d, lines)
  local base = read_doc(d.disk, d.head)
  local disk = read(d.path) or ""
  local doc, outcome = ours, nil
  if disk ~= d.disk then
    local theirs = read_doc(disk, d.head)
    adopt(d.placeholder, base, ours, theirs)
    local lost
    doc, lost = merge(base, ours, theirs)
    if #lost > 0 then
      local ok
      outcome, ok = set_aside(d.path, lost)
      if not ok then return nil, outcome end
    end
  end
  local text = M.message(doc) == "" and "" or join(render(doc))
  if text ~= disk then
    local ok, err = write(d.path, text)
    if not ok then return nil, { err = err, conflict = outcome } end
  end
  return remember(d, doc, text, { ours, base }), outcome
end

--- Read the current persisted document, retaining a known header when its
--- file is empty or its first line was removed.
---@return ai.review.Doc doc, string text
function M.read(path, known)
  local text = read(path) or ""
  return read_doc(text, known), text
end

--- Persist a document; headers and intros alone count as an empty draft.
function M.store(path, doc)
  return write(path, M.message(doc) == "" and "" or join(render(doc)))
end

--- Append `entry` to the draft at `path`, under this view's intro when the
--- draft's last one is another's. A file with no header (emptied) goes on
--- under the header this Nvim knows for it, if any, or starts a draft: the
--- header `header` names, with a new nonce.
---@param known? ai.review.DraftHeader the header this Nvim knows for the draft
---@return integer? line the entry's "> " line in the file, string? err
function M.append(path, header, intro, entry, known)
  local doc = read_doc(read(path) or "", known)
  doc.head = doc.head or vim.tbl_extend("force", header, { n = new_nonce() })
  local blocks = doc.blocks
  -- A blank line between a block and the next.
  local function gap()
    local last = blocks[#blocks].lines
    if #last > 0 and vim.trim(last[#last]) ~= "" then last[#last + 1] = "" end
  end
  if last_intro(doc) ~= intro then
    gap()
    blocks[#blocks + 1] = { kind = "intro", id = new_id(), lines = { intro } }
  end
  gap()
  blocks[#blocks + 1] = { kind = "item", id = new_id(), attrs = entry.attrs, lines = vim.deepcopy(entry.lines) }
  local lines = render(doc)
  local ok, err = write(path, join(lines))
  if not ok then return nil, err end
  return #lines - #entry.lines + entry.comment
end

--- Entries whose file changed since their comment, marked in `doc`: the
--- heading that follows each one's marker. An entry with nothing left in it
--- sends nothing to be warned about.
---@param doc ai.review.Doc
---@return string[] paths the files concerned, each once
function M.mark_stale(doc, root)
  local paths, marked = {}, "## " .. M.STALE
  for _, b in ipairs(doc.blocks) do
    local a = b.attrs or {}
    if b.kind == "item" and type(a.path) == "string" and a.path ~= "" and type(a.digest) == "string"
      and has_text(b.lines) and M.digest(root, a.path) ~= a.digest then
      if not vim.list_contains(paths, a.path) then paths[#paths + 1] = a.path end
      local heading = b.lines[1] or ""
      if heading:sub(1, #marked) ~= marked then
        if heading:match("^## ") then
          b.lines[1] = ("%s · %s"):format(marked, heading:sub(4))
        else
          -- Its heading was edited away: the mark goes where it was.
          table.insert(b.lines, 1, ("%s · %s"):format(marked, a.path))
        end
      end
    end
  end
  return paths
end

--- Acknowledge text that has already arrived at its recipient. Archive it
--- first, then remove only unchanged sent blocks from the current file. New
--- entries survive; an edited sent block keeps the current draft intact.
---@return string status "cleared"|"edited"|"archive_failed"|"clear_failed"
---@return string copy the last-sent archive's path
---@return string? err
function M.acknowledge(path, snapshot, known)
  local copy = (path:gsub("%.md$", "")) .. ".last-sent.md"
  local ok, err = write(copy, snapshot)
  if not ok then return "archive_failed", copy, err end
  local now = read(path) or ""
  local rest = ""
  if now ~= snapshot then
    local sent, doc = by_id(read_doc(snapshot, known)), read_doc(now, known)
    local left, intro = { { kind = "text", id = "", lines = {} } }, nil
    for _, b in ipairs(doc.blocks) do
      local was = sent[b.id]
      if was and not same(was.lines, b.lines) then
        return "edited", copy
      elseif was then
        if b.kind == "intro" then intro = b end
      else
        if b.kind == "intro" then
          intro = nil
        elseif intro then
          -- Only the intro's line stays; its note went out in this delivery.
          left[#left + 1] = { kind = "intro", id = intro.id, lines = { intro.lines[1] or "", "" } }
          intro = nil
        end
        left[#left + 1] = b
      end
    end
    local rest_doc = { head = doc.head, blocks = left }
    rest = M.message(rest_doc) == "" and "" or join(render(rest_doc))
  end
  ok, err = write(path, rest)
  return ok and "cleared" or "clear_failed", copy, err
end

return M
