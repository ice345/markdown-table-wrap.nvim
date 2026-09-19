"""Optional real-input/UI smoke checks: uv run --with pynvim python tests/ui_smoke.py [--lazyvim]."""
import argparse
import pathlib
import time

import pynvim

parser = argparse.ArgumentParser()
parser.add_argument("--lazyvim", action="store_true", help="Load the installed personal LazyVim config in an isolated process")
parser.add_argument("--nvim", default="nvim")
args = parser.parse_args()
root = str(pathlib.Path(__file__).resolve().parent.parent)
# Force this checkout's modules even if Lazy installs another copy. Neither
# the installed plugin nor the personal configuration is edited.
pre = """
local root = %s
for _, f in ipairs(vim.fn.globpath(root..'/lua/markdown-table-wrap', '*.lua', false, true)) do
  local name, path = vim.fn.fnamemodify(f, ':t:r'), f
  package.preload['markdown-table-wrap'..(name=='init' and '' or '.'..name)] = function()
    return assert(loadfile(path))()
  end
end
vim.opt.rtp:prepend(root)
vim.g.clipboard = {name='isolated-test', copy={['+']=function()end,['*']=function()end},
  paste={['+']=function()return {{''},'v'}end,['*']=function()return {{''},'v'}end},cache_enabled=0}
""" % repr(root)
if args.lazyvim:
    pre += """
vim.opt.rtp:prepend(vim.fn.stdpath('data')..'/lazy/lazy.nvim')
local lazy = require('lazy'); local setup = lazy.setup
lazy.setup = function(opts)
  opts.checker={enabled=false}; opts.change_detection={enabled=false}; opts.install={missing=false}
  return setup(opts)
end
"""
argv = [args.nvim, "--embed", "--cmd", "set shadafile=NONE noswapfile", "--cmd", "lua " + pre]
if not args.lazyvim:
    argv += ["-u", "NONE"]
n = pynvim.attach("child", argv=argv)
count = 0


def check(condition, label):
    global count
    assert condition, label
    count += 1


def wait(code, label):
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        if n.exec_lua(code):
            check(True, label)
            return
        time.sleep(.02)
    raise AssertionError(label)


def keys(value):
    n.input(value)
    time.sleep(.15)


def focus(row, col=1):
    check(n.exec_lua("return require('markdown-table-wrap.reader').focus_source_cell(0, ...)", row, col), "focus logical cell")


try:
    n.ui_attach(120, 35, rgb=True)
    if not args.lazyvim:
        n.command("filetype on")
        n.exec_lua("require('markdown-table-wrap').setup({debounce_ms=0,mappings={reader={passthrough={H='previous_buffer',L='next_buffer'}}}})")
    n.exec_lua("""
      _G.smoke_lines={'# Integration test','','| 方案 | 类型 | 说明 |','| - | - | - |',
        '| Wine | 兼容层 | [复杂链接](https://github.com) 中文长内容 repeated repeated repeated repeated |',
        '| UTM | 虚拟机 | `some_code_here` and 界界 emoji 😀 |','','## Another table','',
        '| X | Y |','| - | - |','| one | two |'}
      _G.smoke_path=vim.fn.tempname()..'.md'
      vim.fn.writefile(smoke_lines,smoke_path)
      vim.cmd('edit '..vim.fn.fnameescape(smoke_path))
      _G.smoke_source=vim.api.nvim_get_current_buf()
      vim.bo[smoke_source].ft='markdown'
      vim.b[smoke_source].autoformat=false
    """)
    wait("return require('markdown-table-wrap.reader').is_reader(0)", "automatic Reader opens")
    check(root in n.exec_lua("return debug.getinfo(require('markdown-table-wrap').setup,'S').source"), "local checkout loaded")
    focus(5)
    keys('"ayic')
    check(n.eval('getreg("a")') == "Wine", "typed named-register yic")
    baseline = n.exec_lua("return vim.api.nvim_buf_get_lines(smoke_source,0,-1,false)")
    for sequence in ("yj", "yk", "dj", "dk", "dd", "2yic", "2dic", "2cic"):
        focus(5)
        keys(sequence)
        check(n.exec_lua("return vim.api.nvim_buf_get_lines(smoke_source,0,-1,false)") == baseline, sequence + " preserves Source")
        check(n.eval('getreg("a")') == "Wine", sequence + " preserves named register")
        check(n.eval("mode()") == "n", sequence + " leaves no pending operator")
    focus(5)
    n.funcs.setreg('"', 'preserve me')
    keys('"_dic')
    check(n.funcs.getreg('"') == "preserve me", "black-hole delete preserves unnamed register")
    keys("u")
    check(n.exec_lua("return vim.api.nvim_buf_get_lines(smoke_source,0,-1,false)") == baseline,
          "one undo restores dic: " + repr(n.exec_lua("return {vim.api.nvim_buf_get_lines(smoke_source,0,-1,false),vim.api.nvim_get_mode().mode,require('markdown-table-wrap').get_state()}")))
    focus(5)
    keys("cicNEW<Esc>")
    wait("return require('markdown-table-wrap.reader').is_reader(0)", "cic returns to Reader")
    check("| NEW |" in n.exec_lua("return vim.api.nvim_buf_get_lines(smoke_source,4,5,false)[1]"), "fast typed cic inserts into Source")
    keys("u")
    check(n.exec_lua("return vim.api.nvim_buf_get_lines(smoke_source,0,-1,false)") == baseline, "one undo restores entire cic")
    keys("<C-r>")
    check("| NEW |" in n.exec_lua("return vim.api.nvim_buf_get_lines(smoke_source,4,5,false)[1]"), "redo reapplies cic")
    focus(6)
    keys(".")
    check("| NEW |" in n.exec_lua("return vim.api.nvim_buf_get_lines(smoke_source,5,6,false)[1]"), "dot repeats on another cell")
    focus(5)
    if args.lazyvim:
        keys(" mf")
    else:
        n.command("MarkdownTableFloatPreview")
    check(n.exec_lua("return require('markdown-table-wrap').state.win ~= nil"), "Reader opens Float through configured entry")
    keys("q")
    check(n.exec_lua("return require('markdown-table-wrap.reader').is_reader(0)"), "Float q restores Reader")
    keys("q")
    check(n.exec_lua("return vim.api.nvim_get_current_buf()==smoke_source"), "Reader q restores Source")
    n.command("MarkdownTableFloatPreview")
    keys("q")
    check(n.exec_lua("return vim.api.nvim_get_current_buf()==smoke_source and not require('markdown-table-wrap.reader').is_reader(0)"), "Float q restores Source origin")
    n.exec_lua("""
      _G.smoke_other=vim.fn.bufadd(vim.fn.tempname()..'.md');vim.fn.bufload(smoke_other)
      vim.bo[smoke_other].buflisted=true;vim.bo[smoke_other].ft='markdown'
      vim.api.nvim_buf_set_lines(smoke_other,0,-1,false,smoke_lines)
      require('markdown-table-wrap').reader_preview()
    """)
    keys("L")
    wait("return require('markdown-table-wrap').resolve_source_buffer(0)==smoke_other", "L reaches next Source")
    keys("H")
    wait("return require('markdown-table-wrap.reader').source_bufnr(0)==smoke_source", "H restores original Reader")
    n.exec_lua("""
      _G.smoke_first=vim.api.nvim_get_current_buf();_G.smoke_win1=vim.api.nvim_get_current_win()
      vim.cmd('vsplit');vim.api.nvim_win_set_buf(0,smoke_source)
      _G.smoke_second=require('markdown-table-wrap').reader_preview();_G.smoke_win2=vim.api.nvim_get_current_win()
    """)
    check(n.exec_lua("return smoke_first~=smoke_second and require('markdown-table-wrap.reader').is_reader(smoke_first)"), "two independent Readers share Source")
    # Actual input/event-loop coverage for window-local diff suspension.
    keys(":diffthis<CR>")
    wait("return vim.api.nvim_get_current_buf()==smoke_source and vim.wo.diff", "typed diffthis suspends only this Reader")
    check(n.exec_lua("return require('markdown-table-wrap.reader').is_reader(vim.api.nvim_win_get_buf(smoke_win1))"), "sibling Reader survives diff")
    keys(":MarkdownTableToggleReader<CR>")
    check(n.exec_lua("return vim.api.nvim_get_current_buf()==smoke_source and vim.wo.diff"), "typed Reader command preserves diff")
    keys(":diffoff!<CR>")
    wait("return require('markdown-table-wrap.reader').is_reader(vim.api.nvim_win_get_buf(smoke_win2))", "typed diffoff restores shared-Source Reader")
    n.exec_lua("smoke_second=vim.api.nvim_win_get_buf(smoke_win2)")
    check(n.exec_lua("return not require('markdown-table-wrap').state.paused_buffers[smoke_source]"), "diff round-trip does not pause Source")
    if args.lazyvim:
        # Invoke the actual configured Bufferline callback; only simulate the
        # user's Cancel response rather than opening a blocking confirmation.
        n.exec_lua("""
          local confirm=vim.fn.confirm;vim.fn.confirm=function()return 3 end
          local ok,err=pcall(require('bufferline.config').options.close_command,smoke_source)
          vim.fn.confirm=confirm;if not ok then error(err) end
        """)
        check(n.exec_lua("return vim.bo[smoke_source].modified and require('markdown-table-wrap.reader').is_reader(smoke_first) and require('markdown-table-wrap.reader').is_reader(smoke_second)"), "cancelled Bufferline delete preserves dirty Source and both Readers")
    n.command("write")
    check(n.exec_lua("return vim.deep_equal(vim.fn.readfile(smoke_path),vim.api.nvim_buf_get_lines(smoke_source,0,-1,false))"), "Reader writes exact canonical bytes")
    if args.lazyvim:
        n.exec_lua("require('bufferline.config').options.close_command(smoke_source)")
    else:
        n.exec_lua("vim.cmd('bdelete '..smoke_source)")
    wait("return not require('markdown-table-wrap.reader').has_source_readers(smoke_source)", "Source delete clears Reader ownership")
    check(n.exec_lua("return not vim.api.nvim_buf_is_valid(smoke_first) and not vim.api.nvim_buf_is_valid(smoke_second)"), "Source delete disposes both Reader buffers")
    check(n.exec_lua("return vim.api.nvim_win_is_valid(smoke_win1) and vim.api.nvim_win_is_valid(smoke_win2)"), "Source delete preserves both split windows")
    check(n.exec_lua("return require('markdown-table-wrap').state.refresh_tokens[smoke_source]==nil"), "Source delete invalidates pending refresh")
    print("PASS", count, "real-input checks", "with personal LazyVim/Bufferline/Snacks" if args.lazyvim else "with clean Neovim")
finally:
    try:
        n.command("qa!")
    except EOFError:
        pass
