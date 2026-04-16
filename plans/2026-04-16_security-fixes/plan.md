# Fix Security Vulnerabilities in nvim-treesitter

## Context
Security audit of nvim-treesitter identified 3 issues in `lua/nvim-treesitter/install.lua`:
1. **Path traversal** in query installation via crafted `repo.queries` or `repo.location` fields
2. **No HTTPS enforcement** on parser download URLs
3. **Non-atomic parser replacement** — old `.so` deleted before new one is confirmed good

All changes are confined to a single file: `lua/nvim-treesitter/install.lua`, plus a helper in `lua/nvim-treesitter/util.lua`.

## Scope & Non-Goals
- **In scope:** Fix the 3 identified vulnerabilities with minimal, targeted changes.
- **Non-goals:** Adding checksum/signature verification for downloads (larger design effort, deferred). Refactoring the async pipeline. Changing the parser config schema.

## Implementation Plan

### 1. Add path containment helper (`util.lua`)

Add a function `util.is_path_contained(base, target)` that resolves both paths via `vim.fs.normalize()` and checks the normalized target starts with the normalized base + `/`. This will be reused for both `repo.queries` and `repo.location` validation.

**File:** `lua/nvim-treesitter/util.lua`

```lua
--- Check that `child` is contained within `parent` after normalization.
--- @param parent string
--- @param child string
--- @return boolean
function M.is_path_contained(parent, child)
  local np = vim.fs.normalize(parent)
  local nc = vim.fs.normalize(child)
  return nc:sub(1, #np + 1) == np .. '/'
    or nc == np
end
```

### 2. Path traversal fix — validate `query_src` and `compile_location` (`install.lua`)

**File:** `lua/nvim-treesitter/install.lua`

**2a. Validate `repo.location` (line ~400)**

After `compile_location = fs.joinpath(compile_location, repo.location)` (line ~401), add a containment check. The base is either `fs.normalize(repo.path)` for local repos or `fs.joinpath(cache_dir, project_name)` for downloaded ones.

```lua
if repo.location then
  local base = compile_location
  compile_location = fs.joinpath(compile_location, repo.location)
  if not util.is_path_contained(base, compile_location) then
    return logger:error('repo.location escapes base directory: %s', repo.location)
  end
end
```

**2b. Validate `query_src` (lines ~438-442)**

After computing `query_src` in both the `repo.path` and tarball branches, validate it stays within its expected base:

- For local repo: base is `fs.normalize(repo.path)`
- For tarball: base is `fs.joinpath(cache_dir, project_name)`

```lua
if repo and repo.queries and repo.path then
  local base = fs.normalize(repo.path)
  query_src = fs.joinpath(base, repo.queries)
  if not util.is_path_contained(base, query_src) then
    return logger:error('repo.queries escapes base directory: %s', repo.queries)
  end
  task = do_link_queries
elseif repo and repo.queries then
  local base = fs.joinpath(cache_dir, project_name)
  query_src = fs.joinpath(base, repo.queries)
  if not util.is_path_contained(base, query_src) then
    return logger:error('repo.queries escapes base directory: %s', repo.queries)
  end
  task = do_copy_queries
```

### 3. HTTPS enforcement on download URLs (`install.lua`)

**File:** `lua/nvim-treesitter/install.lua`, function `do_download` (line ~230)

Add a check at the top of `do_download`, right after `url = url:gsub('.git$', '')`:

```lua
if not url:match('^https://') then
  return logger:error('Refusing non-HTTPS parser URL: %s', url)
end
```

### 4. Atomic parser replacement (`install.lua`)

**File:** `lua/nvim-treesitter/install.lua`, function `do_install` (lines ~324-335)

Replace the current rename-delete-copy sequence with a copy-to-temp-then-rename approach:

```lua
local function do_install(logger, compile_location, target_location)
  logger:info('Installing parser')

  -- Copy new parser to a temp file next to the target
  local tempfile = target_location .. '.new.' .. tostring(uv.hrtime())
  local err = uv_copyfile(compile_location, tempfile)
  a.schedule()
  if err then
    uv_unlink(tempfile)
    return logger:error('Error during parser installation (copy): %s', err)
  end

  -- Atomically replace old parser with new one
  local old_backup = target_location .. '.old.' .. tostring(uv.hrtime())
  if uv.fs_stat(target_location) then
    uv_rename(target_location, old_backup)
  end

  err = uv_rename(tempfile, target_location)
  a.schedule()
  if err then
    -- Attempt rollback
    if uv.fs_stat(old_backup) then
      uv_rename(old_backup, target_location)
    end
    return logger:error('Error during parser installation (rename): %s', err)
  end

  -- Clean up old backup
  if uv.fs_stat(old_backup) then
    uv_unlink(old_backup)
  end
end
```

Key improvement: if the rename of the new file fails, the old parser is restored from backup. The old parser is only deleted after the new one is successfully in place.

## Verification

1. **Path traversal:** Write a test that registers a parser config with `queries = "../../etc"` and `location = "../../etc"`, calls the install flow, and asserts an error is returned (not a symlink/copy outside bounds).
2. **HTTPS enforcement:** Register a parser with `url = "http://..."`, call install, assert error about non-HTTPS.
3. **Atomic install:** Simulate a failed copy (e.g., read-only target dir) and verify the original `.so` is still intact after the error.
4. **Regression:** Run `make checklua` to verify no Lua lint issues introduced.
5. **Manual smoke test:** `TSInstall lua` (or any available parser) succeeds as before.
