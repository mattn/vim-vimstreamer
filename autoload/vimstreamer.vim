let s:bin = expand('<sfile>:h:h') . '/vimstreamer/vimstreamer'
if has('win32')
  let s:bin = fnamemodify(s:bin, ':p:gs!/!\\!') . '.exe'
endif

function! s:zoomIn()
  let l:fsize = substitute(&guifont, '^.*:h\([^:]*\).*$', '\1', '')
  let l:fsize += 1
  let l:guifont = substitute(&guifont, ':h\([^:]*\)', ':h' . l:fsize, '')
  let &guifont = l:guifont
endfunction

" guifont size - 1
function! s:zoomOut()
  let l:fsize = substitute(&guifont, '^.*:h\([^:]*\).*$', '\1', '')
  let l:fsize -= 1
  let l:guifont = substitute(&guifont, ':h\([^:]*\)', ':h' . l:fsize, '')
  let &guifont = l:guifont
endfunction

function! vimstreamer#complete(arglead, cmdline, cmdpos)
  let ret = []
  let args = split(a:cmdline[:a:cmdpos], '\s', 1)[1:-2]
  if len(args) == 0
    let mx = '^\S\+:\s\+\zs\S\+\ze:'
    for i in split(system('gst-inspect-1.0'), "\n")
      if i !~ mx
        continue
      endif
      let src = matchstr(i, mx)
      if src !~ 'src$'
        continue
      endif
      call add(ret, src)
    endfor
  else
    let lines = split(system('gst-inspect-1.0 ' . args[0]), "\n")
    let pos = index(lines, 'Element Properties:')
    if pos >= 0
      let lines = lines[pos+1:]
    endif
    let mx = '^\s\+\zs\S\+\ze\s\+:'
    for i in lines
      if i !~ mx
        continue
      endif
      call add(ret, matchstr(i, mx))
    endfor
  endif
  return filter(ret, 'stridx(v:val,a:arglead)==0')
endfunction

function! vimstreamer#open(f)
  let f = 'filesrc location=' . fnameescape(fnamemodify(a:f, ':p:gs!\\!/!'))
  call vimstreamer#start(f)
endfunction

function! vimstreamer#browse()
  let f = browse(0, 'play', '.', '')
  if empty(f)
    return
  endif
  let f = 'filesrc location=' . fnameescape(fnamemodify(f, ':p:gs!\\!/!'))
  call vimstreamer#start(f)
endfunction

function! vimstreamer#start(...)
  if has_key(s:, 'server_job')
    echom "Now Runninng..."
    return
  endif

  if !filereadable(s:bin)
    echom "Building server..."
    call system(printf('cd "%s" && go get -u -d && go build', fnamemodify(s:bin, ':h')))
  endif

  silent new __VimStreamer__
  only!
  setlocal buftype=nofile bufhidden=wipe
  let cmodel = get(g:, 'vimstreamer_colormodel', 'websafe')
  if index(['plan9', 'websafe', '4096'], cmodel) == -1
    let cmodel = '4096'
  endif
  let &ft='vimstreamer_' . cmodel
  let [
  \ s:old_guifont,
  \ s:old_linespace,
  \ s:old_lazyredraw,
  \ s:old_columns,
  \ s:old_lines,
  \ s:old_renderoptions,
  \ _
  \] = [
  \ &guifont,
  \ &linespace,
  \ &lazyredraw,
  \ &columns,
  \ &lines,
  \ &renderoptions,
  \ 0
  \]
  autocmd BufWipeout __VimStreamer__ call vimstreamer#stop()

  if has('gui_running')
    if has('win32')
      "set guifont=MS_Gothic:h4 linespace=4 nolazyredraw columns=195 lines=52 renderoptions=
      set guifont=Terminal:h4 linespace=4 nolazyredraw columns=195 lines=52 renderoptions=
    else
      set guifont=Courier\ 10\ Pitch\ 2 linespace=4 lazyredraw columns=195 lines=52
    endif
    nnoremap + :<c-u>call <SID>zoomIn()<cr>
    nnoremap - :<c-u>call <SID>zoomOut()<cr>
  endif

  nnoremap q :<c-u>bw<cr>

  let s:buf = ''
  let args = [&shell, &shellcmdflag, join(['gst-launch-1.0']+a:000+[
  \  '!', 'decodebin',
  \  '!', 'videoscale',
  \  '!', 'video/x-raw,width=320,height=240',
  \  '!', 'jpegenc',
  \  '!', 'multipartmux',
  \  '!', 'tcpserversink', 'host=127.0.0.1', 'port=3000'
  \ ], ' ')]
  let s:gstreamer_job = job_start(args, {
  \ 'out_cb': function('s:err_cb'),
  \ 'err_cb': function('s:err_cb')
  \})
  let s:server_job = job_start([s:bin, '-w=64', '-h=48', '-c=' . cmodel], {
  \ 'out_cb': function('s:out_cb'),
  \ 'err_cb': function('s:err_cb')
  \})
  let s:timer = timer_start(60, {->execute('redraw', 1)}, {'repeat': -1})
endfunction

function! vimstreamer#stop()
  if has_key(s:, 'gstreamer_job')
    call job_stop(s:gstreamer_job)
    unlet s:gstreamer_job
  endif
  if has_key(s:, 'server_job')
    call job_stop(s:server_job)
    unlet s:server_job
  endif
  if has_key(s:, 'timer')
    call timer_stop(s:timer)
    unlet s:timer
  endif
  let [
  \ &guifont,
  \ &linespace,
  \ &lazyredraw,
  \ &columns,
  \ &lines,
  \ &renderoptions,
  \ _
  \] = [
  \ s:old_guifont,
  \ s:old_linespace,
  \ s:old_lazyredraw,
  \ s:old_columns,
  \ s:old_lines,
  \ s:old_renderoptions,
  \ 0
  \]
endfunction

function! s:err_cb(ch, msg)
  for m in split(a:msg, "\n")
    echomsg m
  endfor
endfunction

function! s:out_cb(ch, msg)
  let s:buf .= a:msg . "\n"
  let pos = stridx(s:buf, "\x0c")
  if pos >= 0
    let mode = mode()
    let oldnr = winnr()
    let winnr = bufwinnr('__VimStreamer__')
    if winnr == -1
      return
    endif
    if oldnr != winnr
      silent! exec winnr.'wincmd w'
    endif
    let s = split(s:buf[:pos-1], "\n")
    silent! call setline(1, s)
    let s:buf = s:buf[pos+1:]
    if oldnr != winnr
      silent! exec oldnr.'wincmd w'
    endif
    if mode =~# '[sSvV]'
      silent! normal gv
    endif
    if mode !~# '[cC]'
      "redraw
      "call timer_start(10, {->execute('redraw', 1)})
    endif
  endif
endfunction
