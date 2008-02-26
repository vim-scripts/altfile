" AltFile 0.2 by Alex Kunin <alexkunin@gmail.com>
"
"
" PURPOSE
" ===================================================================
"
" The plugin allows to switch easily between file.h/file.c,
" main source/testcase, etc.
"
"
" HISTORY
" ===================================================================
"
" 2008-02-26    0.2     Added visual file selector (resembles
"                       BufExplorer; also, some tricks were
"                       borrowed from source code of that really
"                       nice script).
"
" 2008-02-22    0.1e    Autoload support and "write-plugin"
"                       guidelines (thanks to Thomas Link
"                       for advices). Couple of minor bugs
"                       fixed. Some "refactoring".
"
" 2008-02-19    0.1d    Now wildmenu is used as "engine",
"                       so look & feel are much better now.
"                       No more numeric shortcats, however.
"                       Lots of code cleanup.
"
" 2008-02-18    0.1c    Default choice now mimics Alt-Tab (Cmd-Tab
"                       for Mac users), i.e. hitting the hot key
"                       and then <CR> will cycle between last
"                       two files. Visual adjustments: current
"                       file is square brakets, and asterisk
"                       indicates default choice.
"
" 2008-02-18    0.1b    If selected file is already visible
"                       in some window, the script will
"                       activate it.
"
" 2008-02-17    0.1a    When GUI is available, dialog forced
"                       to be console-friendly, i.e. no GUI
"                       window is poping up.
"
" 2008-02-16    0.1     Initial release.
"
"
" INSTALLATION
" ===================================================================
"
" Copy this file to your ~/.vim/plugin/ folder. Bind some key to
" AltFile_ShowMenu() and AltFile_ShowSelector():
" 
"   nmap <expr> <M-Tab> AltFile_ShowMenu()
"   nmap <F3> :call AltFile_ShowSelector()<CR>
"
" Make sure that wildmenu is enabled:
"
"   set wildmenu
"
"
" USAGE
" ===================================================================
"
" Suppose we have a project which resides in a "proj"
" directory. Content of that directory might look like this:
"
"   proj/classes/Class1.php
"   proj/classes/Class2.php
"   proj/classes/Namespace/Class3.php
"   proj/tpl/Class1.html
"   proj/tpl/Class2.html
"   proj/tpl/Namespace/Class3.html
"   proj/tests/Class1.phpt
"   proj/tests/Class2.phpt
"   proj/tests/Namespace/Class3.phpt
"
" Create "proj/.altfile" and put these lines inside:
"
"   class: classes/{MATCH}.php
"   template: tpl/{MATCH}.html
"   test: tests/{MATCH}.phpt
"
" Now load "proj/classes/Class1.php" and hit the hot key. Menu will
" appear:
"
"   class  [template]  test
"
" Now you can use it as any other wild menu: cursor keys, <CR>, <Esc>.
"
" By default previously active item is highilighted (works like Alt-Tab
" for Windows or Cmd-Tab for Mac OS X). So, to quickly switch between
" two files all you have to do is <M-Tab><CR>.
"
" Now load "proj/tpl/Class4.html" - it does not exist, and you'll get
" empty window. Hit <M-Tab>, select "class" and hit <CR> - VIM will
" create new buffer for (still non-existing) "proj/classes/Class4.php".
" Ta-dah! Actually, this is my main reason for creating this plugin.
"
" Note that it DOES NOT matter what is your current directory: you
" can cd to whatever place you want. But it DOES matter where ".altfile"
" is, becase patterns inside it are relative to its placement.
"
" To show visual file selector hit <F3>. Use movement/cursor keys to
" highlight a file; <CR> loads file; <Tab> switches between labels.
"
"
" API
" ===================================================================
"
" Functions:
"
"   AltFile_ShowMenu()      show the menu and highlight default
"                           item (algorithm is similar to Alt-Tab
"                           on Windows or Cmd-Tab on Mac OS X)
"
"   AltFile_ShowSelector()  show visual file selector
"
"   altfile#ShowMenu()      autoloadable version of AltFile_ShowMenu()
"
"   altfile#ShowSelector()  autoloadable version of AltFile_ShowSelector()
"
" Variables:
"
"   g:AltFile_CfgFile       name of the configuration file;
"                           default is ".altfile"
"
" Commands:
"
"   :AltFile {handle}       switch to another file; autocompletion
"                           is available
"
"
" FEEDBACK
" ===================================================================
" Probably, there are bugs - I'm not a VIM guru. Please, send
" bug reports to the e-mail mentioned above. Ideas and suggestions
" are welcome too.
"
"
" LICENSE AND DISCLAIMER
" ===================================================================
" Free for whatever use. No warranties at all.

if exists('loaded_altfile')
    finish
endif

let loaded_altfile = 1
let s:save_cpo = &cpo
set cpo&vim

if !exists('g:AltFile_CfgFile')
    let g:AltFile_CfgFile = '.altfile'
endif

let s:previous = {}

" "Class" s:Mapper:
"   basedir - absolute path of the project (config file is right here)
"   mappings - list of s:Mapping instances
"   current - currently active file
"   match - {MATCH}-part of the filepath
let s:Mapper =
    \ {
    \ 'basedir':'',
    \ 'mappings':[],
    \ 'selectedIndex':-1,
    \ 'match':''
    \ }

function! s:Mapper.construct() dict
    let absfilename = simplify(getcwd() . '/' . expand('%:p:.'))

    " Climbing up to find configuration file:
    let cfgfile =
        \ findfile(g:AltFile_CfgFile, fnamemodify(absfilename, ':h') . ';')

    if !filereadable(cfgfile)
        throw "Configuration file is not available."
    endif

    let result = deepcopy(self)
    let result.basedir = fnamemodify(cfgfile, ':p:h')
    let result.mappings = map(readfile(cfgfile), 's:Mapping.construct(v:val)')

    " Some weird but working steps to find out relative path (relative to
    " result.basedir):
    let hadlocaldir = haslocaldir()
    let cwd = getcwd()
    execute 'lcd ' . result.basedir
    let relfilename = fnamemodify(absfilename, ":p:.")
    execute (hadlocaldir ? 'lcd' : 'cd') . ' ' . cwd

    let l:matches = result.matchRelFilename(relfilename)

    if empty(l:matches)
        throw "No alternatives available."
    endif

    let result.match = l:matches.match
    let result.selectedIndex = l:matches.index

    " Calculating actual alternative filenames by replacing {MATCH} with
    " its actual value:
    for l:mapping in result.mappings
        let l:mapping.filename = l:mapping.expand(result.match)
    endfor

    return result
endfunction

function! s:Mapper.matchRelFilename(filename) dict
    for i in range(len(self.mappings))
        " Constructing and applying regular expression ("{MATCH}" is
        " converted to "(.+)", rest of the pattern matches literally):
        let matches = matchlist(
            \ a:filename,
            \ '^'
            \ . substitute(
                \ escape(self.mappings[i].pattern, '/.'),
                \ '{MATCH}',
                \ '\\(.\\+\\)',
                \''
            \ )
            \ . '$')

        if len(matches)
            return { 'match':matches[1], 'label':'', 'index':i }
        endif
    endfor

    return {}
endfunction

function! s:Mapper.getPreviouslySelectedIndex() dict
    let key = self.basedir . ' ' . self.match
    return (has_key(s:previous, key) && s:previous[key] != self.selectedIndex ? s:previous[key] : self.selectedIndex + 1) % len(self.mappings)
endfunction

function! s:Mapper.setCurrentHandle(handle) dict
    let l:mapping = get(filter(copy(self.mappings), 'v:val.handle == a:handle'), 0, {})

    if l:mapping != {}
        let l:filename = simplify(self.basedir . '/' . l:mapping.filename)
        let s:previous[self.basedir . ' ' . self.match] = self.selectedIndex
        let l:bufno = bufnr(l:filename)
        if l:bufno != -1
            let l:winno = bufwinnr(l:filename)
            execute l:winno != -1 ? l:winno . ' wincmd w' : 'buffer ' . l:bufno
        else
            execute 'edit ' . l:filename
        endif
    endif
endfunction

" "Class" s:Mapping:
"   handle - human-readable label
"   pattern - pattern as defined in the config file
"   filename - pattern with {MATCH} replaced with result.match
let s:Mapping =
    \ {
    \ 'handle':'',
    \ 'pattern':'',
    \ 'filename':''
    \ }

function! s:Mapping.construct(cfgline) dict
    let result = deepcopy(self)

    " Determining which of two forms is in use: "handle: pattern" or
    " just "pattern":
    let matches = matchlist(a:cfgline, '^\(\S\+\):\s\+\(.\+\)$')

    if len(matches)
        let result.handle = matches[1]
        let result.pattern = matches[2]
    else
        let result.handle = a:cfgline
        let result.pattern = a:cfgline
    endif

    return result
endfunction

function! s:Mapping.expand(match)
    return substitute(self.pattern, '{MATCH}', a:match, '')
endfunction

function! s:CompletionCallback(ArgLead, CmdLine, CursorPos)
    return map(copy(s:Mapper.construct().mappings), 'v:val.handle')
endfunction

function! s:Switch(handle)
    try
        call s:Mapper.construct().setCurrentHandle(a:handle)
    catch
        echohl WarningMsg
        echo v:exception
        return
    endtry
endfunction

command!
    \ -nargs=?
    \ -complete=customlist,s:CompletionCallback
    \ AltFile
    \ call s:Switch('<args>')

function! AltFile_ShowMenu()
    try
        let index = s:Mapper.construct().getPreviouslySelectedIndex()
        " Defining macro-aware wildchar (actual value does not matter):
        if !&wildcharm
            set wildcharm=<C-Z>
        endif
        return ':AltFile ' . repeat(nr2char(&wildcharm), index + 1)
    catch
        echohl WarningMsg
        echo v:exception
        return ''
    endtry
endfunction

function! AltFile_ShowSelector()
    let hadlocaldir = haslocaldir()
    let cwd = getcwd()

    "try
        let l:mapper = s:Mapper.construct()
        let l:files = filter(split(globpath(l:mapper.basedir, '**'), "\n"), '!isdirectory(v:val)')
        let l:items = {}

        execute 'lcd ' . l:mapper.basedir

        for l:file in l:files
            let relfilename = fnamemodify(l:file, ":p:.")
            let l:matches = l:mapper.matchRelFilename(relfilename)

            if !empty(l:matches)
                if !has_key(l:items, l:matches.match)
                    let l:items[l:matches.match] = []
                endif
                call add(l:items[l:matches.match], l:mapper.mappings[l:matches.index].handle)
            endif
        endfor
    "catch
    "    echohl WarningMsg
    "    echo v:exception
    "    return
    "finally
        execute (hadlocaldir ? 'lcd' : 'cd') . ' ' . cwd
    "endtry

    drop [AltFile]

    execute 'lcd ' . l:mapper.basedir

    let b:mapper = l:mapper
    let b:items = l:items
    let b:selectedIndex = l:mapper.selectedIndex

    nmap <buffer> <silent> <Tab> :call <SID>NextTab()<CR>
    nmap <buffer> <silent> <S-Tab> :call <SID>PreviousTab()<CR>
    nmap <buffer> <silent> <CR> :call <SID>SwitchToSelectedFile()<CR>

    call s:RenderSelector(1)
endfunction

function! s:SwitchToSelectedFile()
    if line('.') > 2
        execute 'drop ' . getline('.')[4:]
    endif
endfunction

function! s:NextTab()
    let b:selectedIndex = (b:selectedIndex + 1) % len(b:mapper.mappings)
    call s:RenderSelector()
endfunction

function! s:PreviousTab()
    let b:selectedIndex = (b:selectedIndex - 1 + len(b:mapper.mappings)) % len(b:mapper.mappings)
    call s:RenderSelector()
endfunction

function! s:RenderSelector(...)
    setlocal bufhidden=delete
    setlocal buftype=nofile
    setlocal modifiable
    setlocal noswapfile
    setlocal nowrap
    setlocal cursorline

    highlight link AltFile_LabelSel Cursor
    highlight link AltFile_Label Normal

    syntax clear

    syntax match Normal /^Alternatives: .*$/ contains=AltFile_Label,AltFile_LabelSel
    syntax match AltFile_Label / \w\+ / contained
    syntax match AltFile_LabelSel /\[\w\+\]/ contained

    syntax match Normal /^  .*$/
    syntax match Identifier /^ [bw].*$/
    syntax match Special /^ ?.*$/

    let l:moveCurcor = a:0 && a:1

    if !l:moveCurcor
        let l:pos = getpos(".")
    endif

    %delete

    let l:current = b:mapper.mappings[b:selectedIndex].handle

    call setline(1, 'Alternatives: ' . join(map(copy(b:mapper.mappings), 'v:val.handle == l:current ? "[" . v:val.handle . "]" : " " . v:val.handle . " "'), ''))
    call setline(2, '')

    for l:match in sort(keys(b:items))
        let relfilename = b:mapper.mappings[b:selectedIndex].expand(l:match)
        let absfilename = b:mapper.basedir . '/' . relfilename
        let s:line = ' '
        
        if bufnr(absfilename) != -1
            let s:line .= (bufwinnr(absfilename) != -1 ? 'w' : 'b') .
                \ (getbufvar(absfilename, '&modified') ? '+' : ' ')
        elseif !filereadable(absfilename)
            let s:line .= '? '
        else
            let s:line .= '  '
        endif

        let s:line .= ' ' . relfilename

        call append(line('$'), s:line)

        if l:moveCurcor && b:mapper.match == l:match
            call cursor('$', 5)
        endif
    endfor

    if !l:moveCurcor
        call setpos('.', l:pos)
    endif

    setlocal modifiable!
endfunction

function! altfile#ShowMenu()
    return AltFile_ShowMenu()
endfunction

function! altfile#ShowSelector()
    return AltFile_ShowSelector()
endfunction

let &cpo = s:save_cpo
