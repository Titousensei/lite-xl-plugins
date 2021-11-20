-- mod-version:2 -- lite-xl 2.0
local core = require "core"
local config = require "core.config"
local command = require "core.command"

config.plugins.indent_convert = {
  update_indent_type = true -- set to false to avoid updating the document indent type
}

-- TODO: only set document indent type if there are no selections
-- TODO: correctly restore selections accounting for the offset caused by the conversion

-- To replace N spaces with tabs, we match the last N spaces before the start of
-- the actual code and replace them with a tab.
-- We repeat this until we can't find any more spaces before the code.
-- The problem we encounter with this method is that if we have less than N
-- remaining spaces, those will end up at the start of the line.
-- Eg:
-- int main() {
-- __printf("Hello world\n");
-- ___return 0;
-- }
--
-- Becomes
-- int main() {
-- #printf("Hello world\n");
-- _#return 0;
-- }
--
-- Instead of
-- int main() {
-- #printf("Hello world\n");
-- #_return 0;
-- }
-- With regex we could do something like
-- `regex.gsub("(^(?: {2})*)(?: {2})", "\\1\t")`
-- but the implementation of `regex.gsub` is very slow.
--
-- The workaround is to find the longest possible repetition of N*X spaces and
-- use that information to replace the longest repetition of spaces starting
-- from the beginning of the line, then the second longest...
local function spaces_replacer(text, indent_size)
  local spaces = string.rep(" ", indent_size)
  local total = 0
  local n
  local reps = 0
  -- find the longest repetition of indent_size*spaces
  repeat
    reps = reps + 1
    local s, _ = string.find(text, "%f[^\0\n]"..string.rep(spaces, reps))
  until not s
  reps = reps - 1
  while reps > 0 do
    text, n = string.gsub(text,
                          "(%f[^\0\n])("..string.rep(spaces, reps)..")",
                          "%1"..string.rep("\t", reps))
    total = total + n
    reps = reps - 1
  end
  return text, total
end

local function tabs_replacer(text, indent_size)
  local spaces = string.rep(" ", indent_size)
  local total = 0
  local n
  -- replace the last tab before the text until there aren't anymore
  repeat
    text, n = string.gsub(text, "(%f[^\0\n]\t*)(\t)", "%1"..spaces)
    total = total + n
  until n == 0
  return text, total
end

local function replacer(doc, fn)
  local size = config.indent_size
  if type(doc.get_indent_info) == "function" then
    -- use the new `Doc:get_indent_info` function
    size = select(2, doc:get_indent_info())
  end
  return function(text)
    return fn(text, size)
  end
end

local function tabs_to_spaces()
  local doc = core.active_view.doc
  local selections = doc.selections
  doc:replace(replacer(doc, tabs_replacer))
  doc.selections = selections
  doc:sanitize_selection()
  if config.plugins.indent_convert.update_indent_type then
    doc.indent_info = {
      type = "soft",
      size = config.indent_size,
      confirmed = true
    }
  end
end

local function spaces_to_tabs()
  local doc = core.active_view.doc
  local selections = doc.selections
  doc:replace(replacer(doc, spaces_replacer))
  doc.selections = selections
  doc:sanitize_selection()
  if config.plugins.indent_convert.update_indent_type then
    doc.indent_info = {
      type = "hard",
      size = config.indent_size,
      confirmed = true
    }
  end
end

command.add("core.docview", {
    ["indent-convert:tabs-to-spaces"] = tabs_to_spaces,
    ["indent-convert:spaces-to-tabs"] = spaces_to_tabs
  }
)
