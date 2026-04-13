let g:ycm_language_server[len(g:ycm_language_server)-1] =
    \ {
    \     'name': 'zig',
    \     'filetypes': [ 'zig' ],
    \     'cmdline': [ '/home/mark/workspace/gits/ziglang/zls/zig-out/bin/zls', '--config-path', 'zls.json' ],
    \ }
