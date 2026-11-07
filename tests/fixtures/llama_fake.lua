-- Stand-in for llama-server in tests/llama_spec.lua:
--
--   nvim -u NONE -i NONE -l tests/fixtures/llama_fake.lua [--fail]
--     [--mark FILE] [--load-ms N] [--reply-ms N] [--content TEXT]
--     --host H --port P
--
-- /health answers 503 for --load-ms after start, as llama-server does while it
-- loads the model, then 200. /infill checks that the body has the shape the
-- minuet transform promises and streams --content back in three chunks after
-- --reply-ms; a wrong shape gets a 400 naming the field. --fail exits 1 at
-- once, like a server whose weights are not cached under --offline. --mark
-- appends "start <pid>" to FILE on every start and "infill" for every
-- completion request, so a spec can count both.
--
-- It exits by itself when its parent goes, so a spec that dies half-way
-- leaves no server behind.
local opts = {}
local i = 1
while i <= #arg do
  local name = arg[i]:match("^%-%-(.+)")
  if name and arg[i + 1] and not arg[i + 1]:match("^%-%-") then
    opts[name], i = arg[i + 1], i + 2
  else
    opts[name or arg[i]], i = true, i + 1
  end
end
local function mark(line)
  if not opts.mark then return end
  local file = assert(io.open(opts.mark, "a"))
  file:write(line .. "\n")
  file:close()
end
mark("start " .. vim.fn.getpid())
if opts.fail then os.exit(1) end

local parent = vim.uv.os_getppid()
vim.uv.new_timer():start(1000, 1000, function()
  if vim.uv.os_getppid() ~= parent then vim.schedule(function() os.exit(0) end) end
end)

local load_ms = tonumber(opts["load-ms"]) or 0
local reply_ms = tonumber(opts["reply-ms"]) or 0
local content = opts.content or "a + b"
local started = vim.uv.now()

local function respond(client, status, headers, body)
  client:write(("HTTP/1.1 %s\r\n%sConnection: close\r\n\r\n%s"):format(status, headers, body),
    function() client:close() end)
end

local function infill(client, body)
  local ok, request = pcall(vim.json.decode, body)
  if not ok then return respond(client, "400 Bad Request", "", "not json") end
  local problem
  for _, field in ipairs({ "input_prefix", "prompt", "input_suffix" }) do
    if type(request[field]) ~= "string" then problem = problem or ("missing " .. field) end
  end
  if request.stream ~= true then problem = problem or "not streaming" end
  if request.suffix ~= nil or request.model ~= nil then problem = problem or "chat-style fields left in" end
  if problem then return respond(client, "400 Bad Request", "", vim.json.encode({ error = problem })) end

  local third = math.ceil(#content / 3)
  local events = {}
  for start = 1, #content, third do
    events[#events + 1] = "data: " .. vim.json.encode({ content = content:sub(start, start + third - 1) }) .. "\n\n"
  end
  events[#events + 1] = 'data: {"content":""}\n\n'
  vim.defer_fn(function()
    respond(client, "200 OK", "Content-Type: text/event-stream\r\n", table.concat(events))
  end, reply_ms)
end

local server = vim.uv.new_tcp()
assert(server:bind(opts.host or "127.0.0.1", tonumber(opts.port)))
server:listen(16, function()
  local client = vim.uv.new_tcp()
  server:accept(client)
  local data = ""
  client:read_start(function(err, chunk)
    if err or not chunk then return client:close() end
    data = data .. chunk
    local head_end = data:find("\r\n\r\n", 1, true)
    if not head_end then return end
    local length = tonumber(data:match("[Cc]ontent%-[Ll]ength:%s*(%d+)")) or 0
    if #data < head_end + 3 + length then return end
    client:read_stop()
    local path = data:match("^%u+ (%S+)")
    local body = data:sub(head_end + 4, head_end + 3 + length)
    vim.schedule(function()
      if path == "/health" then
        if vim.uv.now() - started < load_ms then
          respond(client, "503 Service Unavailable", "", '{"error":{"code":503,"message":"Loading model"}}')
        else
          respond(client, "200 OK", "", '{"status":"ok"}')
        end
      elseif path == "/infill" then
        mark("infill")
        infill(client, body)
      else
        respond(client, "404 Not Found", "", "{}")
      end
    end)
  end)
end)

while true do
  vim.wait(60000, function() return false end)
end
