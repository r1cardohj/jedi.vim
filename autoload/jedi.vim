" autoload/jedi.vim - Core jedi integration

" The Jedi server runs as a background Vim job.  Individual requests are sent
" synchronously via ch_evalexpr(), which keeps the MVP simple and reliable.
" The synchronous calls return quickly for typical Python files; the server
" itself stays alive across requests.

" Guard against missing global defaults (e.g. autoload called before plugin).
if !exists('g:jedi#enabled')
    let g:jedi#enabled = 1
endif
if !exists('g:jedi#virtual_env')
    let g:jedi#virtual_env = ''
endif
if !exists('g:jedi#completeopt')
    let g:jedi#completeopt = 'menuone,noselect,preview'
endif
if !exists('g:jedi#signature_delay')
    let g:jedi#signature_delay = 100
endif
if !exists('g:jedi#autocomplete')
    let g:jedi#autocomplete = 1
endif
if !exists('g:jedi#complete_delay')
    let g:jedi#complete_delay = 100
endif
if !exists('g:jedi#install_dir')
    let g:jedi#install_dir = expand('~/.cache/jedi.vim')
endif
if !exists('g:jedi#python_executable')
    " A virtualenv previously created by :JediInstall takes precedence over
    " the system interpreters: it is guaranteed to have jedi installed.
    let s:managed_python = g:jedi#install_dir . '/venv/bin/python'
    if executable(s:managed_python)
        let g:jedi#python_executable = s:managed_python
    elseif executable('python3')
        let g:jedi#python_executable = 'python3'
    elseif executable('python')
        let g:jedi#python_executable = 'python'
    else
        let g:jedi#python_executable = ''
    endif
endif

" Script-local state -------------------------------------------------------

let s:job = v:null
let s:channel = v:null
let s:server_script = expand('<sfile>:p:h:h') . '/python/jedi_server.py'
if !filereadable(s:server_script)
    let s:server_script = getcwd() . '/python/jedi_server.py'
endif

" Initialization -----------------------------------------------------------

function! jedi#init() abort
    if !g:jedi#enabled
        return
    endif
    if exists('b:jedi_initialized')
        return
    endif
    let b:jedi_initialized = 1

    call jedi#ensure_running()

    setlocal omnifunc=jedi#complete
    if !empty(g:jedi#completeopt)
        execute 'setlocal completeopt=' . g:jedi#completeopt
    endif

    " Default $VIMRUNTIME/ftplugin/python.vim may overwrite omnifunc later.
    call timer_start(0, {-> execute("setlocal omnifunc=jedi#complete")})

    " Dot-triggered completion: typing "." inserts the dot and schedules
    " an asynchronous completion request.
    inoremap <silent> <buffer> . .<C-R>=jedi#complete_trigger()<CR>

    " Auto completion as you type (see g:jedi#autocomplete).
    autocmd TextChangedI <buffer> call <SID>on_text_changed()

    " Auto call-signature popup while typing arguments.
    inoremap <silent> <buffer> ( (<C-R>=jedi#signature_trigger()<CR>
    inoremap <silent> <buffer> , ,<C-R>=jedi#signature_trigger()<CR>
    inoremap <silent> <buffer> ) )<C-R>=jedi#signature_close()<CR>
    autocmd InsertLeave <buffer> call jedi#signature_close()

    nnoremap <buffer> <Plug>JediGoto :call jedi#goto()<CR>
    nnoremap <buffer> <Plug>JediDoc  :call jedi#show_documentation()<CR>
    nnoremap <buffer> <Plug>JediSignature :call jedi#show_signature()<CR>

    if !hasmapto('<Plug>JediGoto', 'n')
        nmap <buffer> gd <Plug>JediGoto
    endif

    if !hasmapto('<Plug>JediDoc', 'n')
        nmap <buffer> K <Plug>JediDoc
    endif

    if !hasmapto('<Plug>JediSignature', 'n')
        nmap <buffer> gs <Plug>JediSignature
    endif
endfunction

function! jedi#enable(...) abort
    let g:jedi#enabled = 1
    if a:0 >= 1
        let g:jedi#virtual_env = a:1
    endif
    call jedi#init()
    call jedi#ensure_running()
    call s:rpc('init', {'virtual_env': s:effective_virtual_env()})
endfunction

" Virtual environment discovery ----------------------------------------

" Candidate directory names, in priority order.
let s:venv_names = ['.venv', '.env', 'venv', 'env']

" Look for a virtualenv in the working directory under common names.
" Returns the directory path, or '' when none is found.
function! jedi#find_virtual_env() abort
    for l:name in s:venv_names
        let l:dir = getcwd() . '/' . l:name
        if isdirectory(l:dir) && (filereadable(l:dir . '/pyvenv.cfg')
            \ || executable(l:dir . '/bin/python'))
            return l:dir
        endif
    endfor
    return ''
endfunction

" The environment to hand to jedi: an explicitly configured
" g:jedi#virtual_env always wins; otherwise auto-detect in the cwd.
function! s:effective_virtual_env() abort
    if !empty(g:jedi#virtual_env)
        return g:jedi#virtual_env
    endif
    return jedi#find_virtual_env()
endfunction

function! jedi#disable() abort
    let g:jedi#enabled = 0
    call jedi#stop_server()
endfunction

" Server lifecycle ---------------------------------------------------------

function! jedi#ensure_running() abort
    if s:job isnot v:null && job_status(s:job) ==# 'run'
        return
    endif
    call jedi#start_server()
endfunction

function! jedi#start_server() abort
    call jedi#stop_server()

    if empty(g:jedi#python_executable)
        echoerr 'jedi.vim: g:jedi#python_executable is not set'
        return
    endif

    let l:cmd = [g:jedi#python_executable, s:server_script]
    let l:opts = {
        \ 'mode': 'json',
        \ 'err_mode': 'raw',
        \ 'err_cb': function('s:on_stderr'),
        \ 'exit_cb': function('s:on_exit'),
    \ }

    let s:job = job_start(l:cmd, l:opts)
    if s:job is v:null || job_status(s:job) !=# 'run'
        echoerr 'jedi.vim: failed to start server: ' . string(l:cmd)
        let s:job = v:null
        return
    endif
    let s:channel = job_getchannel(s:job)

    " Initialize with the configured or auto-detected virtual environment.
    let l:venv = s:effective_virtual_env()
    call s:rpc('init', {'virtual_env': l:venv})
    if !empty(l:venv) && empty(g:jedi#virtual_env)
        echom 'jedi.vim: auto-detected virtualenv: ' . l:venv
    endif
endfunction

function! jedi#stop_server() abort
    if s:job isnot v:null
        try
            call job_stop(s:job)
        catch /.*/
        endtry
    endif
    let s:job = v:null
    let s:channel = v:null
endfunction

" Installation ---------------------------------------------------------

" Install jedi into a plugin-managed virtualenv (g:jedi#install_dir/venv)
" and switch the server to it.  Runs asynchronously; requires network
" access for pip.
function! jedi#install() abort
    if executable('python3')
        let l:python = 'python3'
    elseif executable('python')
        let l:python = 'python'
    else
        echoerr 'jedi.vim: no python3/python found to create a virtualenv'
        return
    endif

    let l:venv = g:jedi#install_dir . '/venv'
    call mkdir(g:jedi#install_dir, 'p')

    echom 'jedi.vim: installing jedi into ' . l:venv . ' (this may take a minute)...'
    let l:cmd = ['/bin/sh', '-c',
        \ l:python . ' -m venv ' . shellescape(l:venv)
        \ . ' && ' . shellescape(l:venv . '/bin/pip')
        \ . ' install --upgrade --quiet jedi']
    let l:job = job_start(l:cmd, {
        \ 'exit_cb': function('s:on_install_exit', [l:venv]),
        \ })
    if l:job is v:null || job_status(l:job) !=# 'run'
        echoerr 'jedi.vim: failed to start the installer'
    endif
endfunction

function! s:on_install_exit(venv, job, status) abort
    if a:status != 0
        echoerr 'jedi.vim: installation failed (exit status ' . a:status . ')'
        return
    endif
    let g:jedi#python_executable = a:venv . '/bin/python'
    echom 'jedi.vim: jedi installed, restarting server with ' . g:jedi#python_executable
    call jedi#start_server()
endfunction

function! jedi#server_status() abort
    if s:job is v:null
        return 'stopped'
    endif
    return job_status(s:job)
endfunction

" Low-level RPC ------------------------------------------------------------

function! s:rpc(method, params) abort
    call jedi#ensure_running()

    let l:request = {
        \ 'id': 1,
        \ 'method': a:method,
        \ 'params': a:params,
    \ }

    " Vim's JSON channel wraps requests as [id, expr].  ch_evalexpr returns the
    " unwrapped result (the expr's response), not the wrapper itself.
    let l:response = ch_evalexpr(s:channel, l:request)

    if type(l:response) == v:t_dict && has_key(l:response, 'error')
        throw 'jedi.vim: ' . l:response.error
    endif

    return l:response
endfunction

" Asynchronous variant: the Callback is invoked with the unwrapped result
" once the response arrives; Vim stays responsive in the meantime.
function! s:rpc_async(method, params, Callback) abort
    call jedi#ensure_running()

    let l:request = {
        \ 'id': 1,
        \ 'method': a:method,
        \ 'params': a:params,
    \ }

    try
        call ch_sendexpr(s:channel, l:request,
            \ {'callback': {ch, resp -> a:Callback(resp)}})
    catch /.*/
        " Channel died mid-request; s:on_exit will clean up.
    endtry
endfunction

function! s:on_stderr(channel, msg) abort
    echohl WarningMsg
    echom 'jedi.vim: ' . string(a:msg)
    echohl None
endfunction

function! s:on_exit(job, status) abort
    let s:job = v:null
    let s:channel = v:null
endfunction

" Completion ---------------------------------------------------------------

function! jedi#complete(findstart, base) abort
    if a:findstart
        let l:line = getline('.')
        let l:col = col('.')
        call writefile(['findstart col=' . l:col . ' line=' . l:line], '/tmp/jedi_complete_log.txt', 'a')

        " findstart must return a 0-based byte offset (see :h complete-functions);
        " the text between it and the cursor is replaced by the chosen match.
        if l:col > 1 && l:line[l:col - 2] ==# '.'
            let s:complete_startcol = l:col - 1
            call writefile(['findstart dot-after start=' . (l:col - 1)], '/tmp/jedi_complete_log.txt', 'a')
            return l:col - 1
        endif

        if l:col > 1 && l:line[l:col - 1] ==# '.'
            let s:complete_startcol = l:col
            call writefile(['findstart dot-on start=' . l:col], '/tmp/jedi_complete_log.txt', 'a')
            return l:col
        endif

        let l:start = l:col - 1
        while l:start > 0 && l:line[l:start - 1] =~# '\k'
            let l:start -= 1
        endwhile
        let s:complete_startcol = l:start
        call writefile(['findstart keyword start=' . l:start], '/tmp/jedi_complete_log.txt', 'a')
        return l:start
    endif

    if !exists('s:complete_startcol')
        let s:complete_startcol = col('.') - 1
    endif

    let l:base = a:base
    let l:startcol = s:complete_startcol
    if l:base[0:0] ==# '.'
        let l:base = l:base[1:]
        let l:startcol += 1
    endif

    let l:ctx = s:current_context()
    let l:line = getline('.')
    " s:complete_startcol is a 0-based byte offset; jedi also uses 0-based columns.
    let l:jedi_col = l:startcol + len(l:base)
    if l:jedi_col > len(l:line)
        let l:jedi_col = len(l:line)
    endif
    if l:jedi_col < 0
        let l:jedi_col = 0
    endif
    let l:ctx.column = l:jedi_col
    call writefile(['complete(0) startcol=' . l:startcol . ' base=' . l:base . ' jedi_col=' . l:jedi_col . ' line=' . l:line . ' col=' . col('.')], '/tmp/jedi_complete_log.txt', 'a')

    try
        let l:result = s:rpc('complete', l:ctx)
    catch
        echohl ErrorMsg
        echom 'jedi.vim: completion failed: ' . v:exception
        echohl None
        return []
    endtry

    return s:complete_items(l:result)
endfunction

" Convert a list of jedi completion dicts into Vim completion items.
" Shared by the synchronous omnifunc and the asynchronous completion path.
function! s:complete_items(result) abort
    if type(a:result) != v:t_list
        return []
    endif
    let l:items = []
    for l:item in a:result
        if type(l:item) != v:t_dict
            continue
        endif
        let l:word = get(l:item, 'word', '')
        if empty(l:word)
            continue
        endif
        let l:entry = {
            \ 'word': l:word,
            \ 'abbr': get(l:item, 'abbr', l:word),
            \ 'menu': get(l:item, 'menu', ''),
            \ 'info': get(l:item, 'info', ''),
            \ 'kind': s:map_kind(get(l:item, 'kind', '')),
        \ }
        call add(l:items, l:entry)
    endfor
    return l:items
endfunction

function! s:map_kind(kind) abort
    let l:map = {
        \ 'module': 'm',
        \ 'class': 'c',
        \ 'instance': 'v',
        \ 'function': 'f',
        \ 'method': 'f',
        \ 'generator': 'f',
        \ 'statement': 'v',
        \ 'param': 'v',
        \ 'keyword': 'k',
    \ }
    return get(l:map, a:kind, '')
endfunction

" Async completion ---------------------------------------------------------
"
" The omnifunc (i_CTRL-X_CTRL-O) is inherently synchronous, so automatic
" completion takes a different route: typing (TextChangedI) or a dot
" schedules a debounced request, and when the response arrives the popup
" menu is opened with complete().  Vim never blocks waiting for jedi.

let s:comp_timer = v:null
let s:comp_seq = 0
let s:comp_pos = [0, 0, 0, 0]   " [bufnr, lnum, col, startcol] of pending request

" Called from the dot-trigger mapping; returns '' so only the dot is
" inserted.  Works regardless of g:jedi#autocomplete.
function! jedi#complete_trigger() abort
    call s:schedule_completion()
    return ''
endfunction

function! s:on_text_changed() abort
    if g:jedi#autocomplete
        call s:schedule_completion()
    endif
endfunction

function! s:schedule_completion() abort
    if pumvisible() || mode() !~# '^[iR]'
        return
    endif
    call s:cancel_complete_timer()
    let s:comp_timer = timer_start(g:jedi#complete_delay,
        \ {-> s:on_complete_timer(bufnr('%'))})
endfunction

function! s:cancel_complete_timer() abort
    if s:comp_timer isnot v:null
        call timer_stop(s:comp_timer)
        let s:comp_timer = v:null
    endif
endfunction

function! s:on_complete_timer(buf) abort
    let s:comp_timer = v:null
    if bufnr('%') != a:buf || mode() !~# '^[iR]' || pumvisible()
        return
    endif

    let l:line = getline('.')
    let l:col = col('.')

    if l:col > 1 && l:line[l:col - 2] ==# '.'
        " Right after a dot: complete with an empty base.
        let l:start = l:col - 1
    else
        " Complete the keyword before the cursor.  Without a base (after
        " whitespace, an open paren, ...) do not pop anything up.
        let l:start = l:col - 1
        while l:start > 0 && l:line[l:start - 1] =~# '\k'
            let l:start -= 1
        endwhile
        if l:start == l:col - 1
            return
        endif
    endif

    let s:comp_seq += 1
    let s:comp_pos = [a:buf, line('.'), l:col, l:start]
    call s:rpc_async('complete', s:current_context(),
        \ function('s:on_completions', [s:comp_seq]))
endfunction

function! s:on_completions(seq, response) abort
    " Drop stale responses: a newer request was issued since, or the
    " cursor moved away from where the request was made.
    if a:seq != s:comp_seq || mode() !~# '^[iR]'
        return
    endif
    if [bufnr('%'), line('.'), col('.')] !=# s:comp_pos[0:2]
        return
    endif
    let l:items = s:complete_items(a:response)
    if empty(l:items)
        return
    endif
    call complete(s:comp_pos[3] + 1, l:items)
endfunction

" Completion helper for dot-trigger and manual completion.
function! jedi#complete_string(autocomplete) abort
    if a:autocomplete
        if pumvisible()
            return ''
        endif
        return "\<C-X>\<C-O>"
    endif
    if pumvisible()
        return "\<C-n>"
    endif
    return "\<C-X>\<C-O>"
endfunction

" Navigation ---------------------------------------------------------------

function! jedi#goto() abort
    call jedi#ensure_running()
    let l:ctx = s:current_context()
    let l:ctx.goto_type = 'definition'

    try
        let l:results = s:rpc('goto', l:ctx)
    catch
        echohl ErrorMsg
        echom v:exception
        echohl None
        return
    endtry

    if empty(l:results)
        echohl WarningMsg
        echo 'jedi.vim: No definition found'
        echohl None
        return
    endif

    let l:first = l:results[0]

    if len(l:results) == 1
        call s:jump_to(l:first.path, l:first.line, l:first.column)
        return
    endif

    let l:list = []
    for l:r in l:results
        call add(l:list, {
            \ 'filename': l:r.path,
            \ 'lnum': l:r.line,
            \ 'col': l:r.column + 1,
            \ 'text': l:r.description,
        \ })
    endfor
    call setloclist(0, l:list)
    lopen
endfunction

function! s:jump_to(path, line, column) abort
    if a:path !=# expand('%:p')
        execute 'edit ' . fnameescape(a:path)
    endif
    call cursor(a:line, a:column + 1)
endfunction

" Documentation ------------------------------------------------------------

function! jedi#show_documentation() abort
    call jedi#ensure_running()

    try
        let l:result = s:rpc('get_doc', s:current_context())
    catch
        echohl ErrorMsg
        echom v:exception
        echohl None
        return
    endtry

    let l:doc = get(l:result, 'doc', '')
    if empty(l:doc)
        echo 'jedi.vim: No documentation available'
        return
    endif

    call s:show_doc('Jedi Documentation', l:doc)
endfunction

function! s:show_doc(title, text) abort
    " Prefer a floating popup window; fall back to the preview window.
    if exists('*popup_create')
        call s:show_in_popup(a:title, a:text)
    else
        call s:show_in_preview(a:title, a:text)
    endif
endfunction

function! s:show_in_popup(title, text) abort
    call popup_clear()
    call popup_create(split(a:text, "\n"), {
        \ 'title': a:title,
        \ 'line': 'cursor+1',
        \ 'col': 'cursor',
        \ 'pos': 'topleft',
        \ 'moved': 'any',
        \ 'close': 'click',
        \ 'border': [],
        \ 'padding': [0, 1, 0, 1],
        \ 'wrap': 1,
        \ 'scrollbar': 1,
        \ 'filter': function('s:popup_scroll_filter'),
        \ 'maxwidth': min([80, &columns - 4]),
        \ 'maxheight': min([30, &lines - 4]),
    \ })
endfunction

" Key handler for the doc popup: C-f/C-b scroll the window contents,
" q or Esc closes it, everything else passes through.
function! s:popup_scroll_filter(winid, key) abort
    if a:key ==# "\<C-f>"
        call s:popup_scroll(a:winid, 1)
        return v:true
    endif
    if a:key ==# "\<C-b>"
        call s:popup_scroll(a:winid, -1)
        return v:true
    endif
    if a:key ==# 'q' || a:key ==# "\<Esc>"
        call popup_close(a:winid)
        return v:true
    endif
    return v:false
endfunction

" Scroll a popup by setting its 'firstline' option; this works without
" redrawing and does not depend on the popup window's cursor.
function! s:popup_scroll(winid, dir) abort
    let l:pos = popup_getpos(a:winid)
    if empty(l:pos)
        return
    endif
    " core_height is 0 until the popup has been drawn; fall back to maxheight.
    let l:height = get(l:pos, 'core_height', 0)
    if l:height <= 0
        let l:height = get(popup_getoptions(a:winid), 'maxheight', 10)
    endif
    let l:page = max([1, l:height - 1])
    let l:lastline = len(getbufline(winbufnr(a:winid), 1, '$'))
    let l:cur = max([1, get(popup_getoptions(a:winid), 'firstline', 1)])
    let l:new = l:cur + a:dir * l:page
    let l:new = min([max([1, l:new]), max([1, l:lastline - l:page])])
    call popup_setoptions(a:winid, {'firstline': l:new})
endfunction

function! s:show_in_preview(title, text) abort
    silent! pclose
    new
    setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
    setlocal previewwindow
    execute 'file ' . fnameescape(a:title)
    call setline(1, split(a:text, "\n"))
    setlocal nomodifiable
    nnoremap <buffer> q <C-w>q
endfunction

" Signature ------------------------------------------------------------------

" Show the call signature(s) at the cursor position in a floating window.
" The parameter the cursor is currently on is wrapped in *...*.
function! jedi#show_signature() abort
    call jedi#ensure_running()

    try
        let l:result = s:rpc('get_signature', s:current_context())
    catch
        echohl ErrorMsg
        echom v:exception
        echohl None
        return
    endtry

    if type(l:result) != v:t_list || empty(l:result)
        echo 'jedi.vim: No signature found'
        return
    endif

    call s:show_doc('Signature', join(s:signature_lines(l:result), "\n"))
endfunction

" Build one display line per signature; the parameter the cursor is
" currently on is wrapped in *...*.
function! s:signature_lines(result) abort
    let l:lines = []
    for l:s in a:result
        let l:params = get(l:s, 'params', [])
        let l:index = get(l:s, 'index', v:null)
        if l:index isnot v:null && l:index >= 0 && l:index < len(l:params)
            let l:params[l:index] = '*' . l:params[l:index] . '*'
        endif
        call add(l:lines, get(l:s, 'name', '') . '(' . join(l:params, ', ') . ')')
    endfor
    return l:lines
endfunction

" Auto signature popup while typing arguments --------------------------

let s:sig_popup = v:null
let s:sig_timer = v:null

" Called from insert-mode mappings for ( and , : debounce, then show or
" update the signature popup for the call the cursor is in.  Returns ''
" so the mapping only inserts the typed character.  Note: this also runs
" while the completion menu is visible — the signature popup sits above
" the cursor line, the completion menu below it, so they never overlap.
function! jedi#signature_trigger() abort
    if g:jedi#signature_delay <= 0
        call s:update_signature_popup()
        return ''
    endif
    call s:cancel_signature_timer()
    let s:sig_timer = timer_start(g:jedi#signature_delay,
        \ {-> s:on_signature_timer(bufnr('%'))})
    return ''
endfunction

" Close the auto signature popup (typed ) or InsertLeave).
function! jedi#signature_close() abort
    call s:cancel_signature_timer()
    call s:close_signature_popup()
    return ''
endfunction

function! s:cancel_signature_timer() abort
    if s:sig_timer isnot v:null
        call timer_stop(s:sig_timer)
        let s:sig_timer = v:null
    endif
endfunction

function! s:on_signature_timer(buf) abort
    let s:sig_timer = v:null
    " The user may have switched buffers while the timer was pending.
    if bufnr('%') != a:buf
        return
    endif
    call s:update_signature_popup()
endfunction

function! s:update_signature_popup() abort
    call s:rpc_async('get_signature', s:current_context(),
        \ function('s:on_signature_result', [bufnr('%')]))
endfunction

" Position for the signature popup: above the cursor line, so the
" completion popup menu (which always opens below the cursor) never
" overlaps it.  On the first line there is no room above; use below.
function! s:signature_popup_pos() abort
    if line('.') > 1
        return {'line': 'cursor-1', 'col': 'cursor', 'pos': 'botleft'}
    endif
    return {'line': 'cursor+1', 'col': 'cursor', 'pos': 'topleft'}
endfunction

function! s:on_signature_result(buf, response) abort
    " Only relevant while still typing in the same buffer.
    if bufnr('%') != a:buf || mode() !~# '^[iR]'
        return
    endif
    if type(a:response) != v:t_list || empty(a:response)
        call s:close_signature_popup()
        return
    endif

    let l:lines = s:signature_lines(a:response)
    if s:sig_popup isnot v:null && index(popup_list(), s:sig_popup) >= 0
        call popup_settext(s:sig_popup, l:lines)
        call popup_move(s:sig_popup, s:signature_popup_pos())
        return
    endif

    " 'mapping': 0 — while typing, all keys must go to the buffer.
    let s:sig_popup = popup_create(l:lines, extend(s:signature_popup_pos(), {
        \ 'title': 'Signature',
        \ 'border': [],
        \ 'padding': [0, 1, 0, 1],
        \ 'wrap': 1,
        \ 'mapping': 0,
        \ 'maxwidth': min([80, &columns - 4]),
        \ 'maxheight': min([30, &lines - 4]),
    \ }))
endfunction

function! s:close_signature_popup() abort
    if s:sig_popup isnot v:null
        if index(popup_list(), s:sig_popup) >= 0
            call popup_close(s:sig_popup)
        endif
        let s:sig_popup = v:null
    endif
endfunction

" Utilities ----------------------------------------------------------------

function! s:current_context() abort
    return {
        \ 'code': join(getline(1, '$'), "\n"),
        \ 'line': line('.'),
        \ 'column': col('.') - 1,
        \ 'path': expand('%:p'),
    \ }
endfunction
