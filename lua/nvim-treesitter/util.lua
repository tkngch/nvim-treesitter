local M = {}

--- @param filename string
--- @return string
function M.read_file(filename)
  local file = assert(io.open(filename, 'r'))
  local r = file:read('*a')
  file:close()
  return r
end

--- @param filename string
--- @param content string
function M.write_file(filename, content)
  local file = assert(io.open(filename, 'w'))
  file:write(content)
  file:close()
end

--- Check that `child` path is contained within `parent` path after normalization.
--- @param parent string
--- @param child string
--- @return boolean
function M.is_path_contained(parent, child)
  local np = vim.fs.normalize(parent)
  local nc = vim.fs.normalize(child)
  return nc == np or nc:sub(1, #np + 1) == np .. '/'
end

return M
