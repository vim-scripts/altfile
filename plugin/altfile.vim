" AltFile 0.2a by Alex Kunin <alexkunin@gmail.com>
"
" The plugin allows to switch easily between file.h/file.c,
" main source/testcase, etc.
"
" More info can be found here: http://code.google.com/p/altfile/

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
let s:bufname = '\[AltFile\]'

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
        call s:Activate(l:filename)
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
    if exists('b:mapper')
        return
    endif

    let hadlocaldir = haslocaldir()
    let cwd = getcwd()

    try
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
    catch
        echohl WarningMsg
        echo v:exception
        return
    finally
        execute (hadlocaldir ? 'lcd' : 'cd') . ' ' . cwd
    endtry

    call s:Activate(s:bufname)

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
        if !s:Activate(getline('.')[4:])
            if bufnr(s:bufname) != -1
                execute bufnr(s:bufname) . 'bdelete'
            endif
        endif
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

function! s:Activate(filename)
    let l:bufno = bufnr(a:filename)
    if l:bufno != -1
        let l:winno = bufwinnr(a:filename)
        if l:winno != -1
            execute l:winno . ' wincmd w'
            return 0
        else
            execute (&modified ? 'sbuffer ' : 'buffer ') . l:bufno
            return 1
        endif
    else
        execute (&modified ? 'split ' : 'edit ') . a:filename
        return 2
    endif
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
        let l:line = ' '
        
        if bufnr(absfilename) != -1
            let l:line .= (bufwinnr(absfilename) != -1 ? 'w' : 'b') .
                \ (getbufvar(absfilename, '&modified') ? '+' : ' ')
        elseif !filereadable(absfilename)
            let l:line .= '? '
        else
            let l:line .= '  '
        endif

        let l:line .= ' ' . relfilename

        call append(line('$'), l:line)

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
