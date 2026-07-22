" jedi.vim - Asynchronous Python completion and navigation via jedi
" Maintainer:   jedi.vim contributors
" Version:      0.1.0

if exists('g:loaded_jedi')
    finish
endif
let g:loaded_jedi = 1

" Configuration defaults ---------------------------------------------------

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

augroup jedi_vim_auto
    autocmd!
    autocmd FileType python call jedi#init()
augroup END

" Commands -----------------------------------------------------------------

command! -nargs=? JediEnable  call jedi#enable(<q-args>)
command! -nargs=0 JediDisable call jedi#disable()
command! -nargs=0 JediInstall call jedi#install()
command! -nargs=0 JediGoto    call jedi#goto()
command! -nargs=0 JediDoc     call jedi#show_documentation()
command! -nargs=0 JediSignature call jedi#show_signature()
