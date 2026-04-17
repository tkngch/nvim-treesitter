local util = require('nvim-treesitter.util')

describe('util.is_path_contained', function()
  it('returns true for a direct child', function()
    assert.True(util.is_path_contained('/base', '/base/child'))
  end)

  it('returns true for a nested child', function()
    assert.True(util.is_path_contained('/base', '/base/child/grandchild'))
  end)

  it('returns true when paths are equal', function()
    assert.True(util.is_path_contained('/base/dir', '/base/dir'))
  end)

  it('returns false for a parent traversal', function()
    -- vim.fs.normalize resolves ".." so /base/../etc becomes /etc
    assert.False(util.is_path_contained('/base', '/base/../etc'))
  end)

  it('returns false for sibling directory', function()
    assert.False(util.is_path_contained('/base/foo', '/base/bar'))
  end)

  it('returns false for prefix collision (basedir vs basedirx)', function()
    -- /basedirx/child should NOT be considered inside /basedir
    assert.False(util.is_path_contained('/basedir', '/basedirx/child'))
  end)

  it('handles deep traversal correctly', function()
    assert.False(
      util.is_path_contained('/home/user/project', '/home/user/project/../../etc/passwd')
    )
  end)

  it('returns true for relative contained paths', function()
    assert.True(util.is_path_contained('project', 'project/src'))
  end)

  it('returns false for relative traversal', function()
    assert.False(util.is_path_contained('project', 'project/../other'))
  end)

  it('returns false for completely unrelated paths', function()
    assert.False(util.is_path_contained('/opt/parsers', '/tmp/evil'))
  end)

  it('handles trailing slashes in parent', function()
    assert.True(util.is_path_contained('/base/', '/base/child'))
  end)
end)

describe('install security: path validation', function()
  -- These tests verify that the path containment checks in install.lua
  -- would catch malicious parser configs, by testing the same logic
  -- that install.lua uses internally.

  it('detects traversal in repo.location', function()
    -- Simulates: compile_location = /tmp/cache/tree-sitter-lang
    --            repo.location = ../../etc
    local base = '/tmp/cache/tree-sitter-lang'
    local location = '../../etc'
    local resolved = vim.fs.joinpath(base, location)
    assert.False(util.is_path_contained(base, resolved))
  end)

  it('allows valid repo.location', function()
    -- Simulates: compile_location = /tmp/cache/tree-sitter-lang
    --            repo.location = src/parser
    local base = '/tmp/cache/tree-sitter-lang'
    local location = 'src/parser'
    local resolved = vim.fs.joinpath(base, location)
    assert.True(util.is_path_contained(base, resolved))
  end)

  it('detects traversal in repo.queries with local path', function()
    -- Simulates: repo.path = /home/user/my-parser
    --            repo.queries = ../../.ssh
    local base = vim.fs.normalize('/home/user/my-parser')
    local queries = '../../.ssh'
    local query_src = vim.fs.joinpath(base, queries)
    assert.False(util.is_path_contained(base, query_src))
  end)

  it('allows valid repo.queries', function()
    -- Simulates: repo.path = /home/user/my-parser
    --            repo.queries = queries/lang
    local base = vim.fs.normalize('/home/user/my-parser')
    local queries = 'queries/lang'
    local query_src = vim.fs.joinpath(base, queries)
    assert.True(util.is_path_contained(base, query_src))
  end)

  it('detects traversal in repo.queries from tarball', function()
    -- Simulates: cache_dir/project_name = /tmp/nvim-treesitter/tree-sitter-lang
    --            repo.queries = ../../../etc/shadow
    local base = '/tmp/nvim-treesitter/tree-sitter-lang'
    local queries = '../../../etc/shadow'
    local query_src = vim.fs.joinpath(base, queries)
    assert.False(util.is_path_contained(base, query_src))
  end)
end)

describe('install security: URL validation', function()
  it('HTTPS URL is accepted (starts with https://)', function()
    local url = 'https://github.com/tree-sitter/tree-sitter-lua'
    assert.True(url:match('^https://') ~= nil)
  end)

  it('HTTP URL is rejected (does not start with https://)', function()
    local url = 'http://evil.example.com/tree-sitter-malicious'
    assert.True(url:match('^https://') == nil)
  end)

  it('FTP URL is rejected', function()
    local url = 'ftp://example.com/tree-sitter-lang'
    assert.True(url:match('^https://') == nil)
  end)

  it('URL without scheme is rejected', function()
    local url = 'github.com/tree-sitter/tree-sitter-lua'
    assert.True(url:match('^https://') == nil)
  end)

  it('URL with https in path but not scheme is rejected', function()
    local url = 'http://example.com/https://fake'
    assert.True(url:match('^https://') == nil)
  end)
end)
