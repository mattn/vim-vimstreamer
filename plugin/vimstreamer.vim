if !executable('gst-launch-1.0')
  finish
endif

command! -nargs=* -complete=customlist,vimstreamer#complete VimStreamer call vimstreamer#start(<f-args>)
command! -nargs=0 WebCam call vimstreamer#start('ksvideosrc', 'device-index=0')
if exists("*browse")
  command! VimStreamerBrowse call vimstreamer#browse()
endif
command! -nargs=1 -complete=file VimStreamerOpen call vimstreamer#open(<q-args>)
