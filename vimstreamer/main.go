package main

import (
	"flag"
	"fmt"
	"image"
	"image/color/palette"
	"image/draw"
	"net"
	"os"
	"time"

	"github.com/mattn/go-mjpeg"
	"github.com/nfnt/resize"
)

var (
	addr   = flag.String("addr", "127.0.0.1:3000", "server address")
	width  = flag.Uint("w", 32, "width")
	height = flag.Uint("h", 24, "height")
	delay  = flag.Int64("d", 0, "delay")
	cmodel = flag.String("c", "plan9", "color model")
)

func main() {
	flag.Parse()

	var err error
	var conn net.Conn
	for retry := 0; retry < 3; retry++ {
		conn, err = net.Dial("tcp", *addr)
		if err == nil {
			break
		}
		time.Sleep(time.Second)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	dec := mjpeg.NewDecoder(conn, "ThisRandomString")

	q := make(chan image.Image, 2)
	go func() {
		var img image.Image
		var err error
		for {
			img, err = dec.Decode()
			if err != nil {
				break
			}

			now := time.Now().Unix()
			if len(q) == 0 {
				if *delay < 1 || now%*delay == 0 {
					q <- img
				}
			}
		}
		close(q)
	}()

	bounds := image.Rect(0, 0, int(*width), int(*height))
	var paletted *image.Paletted
	switch *cmodel {
	case "websafe":
		paletted = image.NewPaletted(bounds, palette.WebSafe)
	case "plan9":
		paletted = image.NewPaletted(bounds, palette.Plan9)
	}
	for {
		img, ok := <-q
		if !ok {
			break
		}
		img = resize.Resize(*width, *height, img, resize.Bicubic)
		switch *cmodel {
		case "websafe", "plan9":
			draw.Draw(paletted, bounds, img, image.Pt(0, 0), draw.Src)
			dx, dy := bounds.Dx(), bounds.Dy()
			for y := 0; y < dy; y++ {
				for x := 0; x < dx; x++ {
					fmt.Printf("#%02X", paletted.ColorIndexAt(x, y))
				}
				fmt.Println()
			}
		default:
			nrgba := image.NewNRGBA(bounds)
			draw.Draw(nrgba, bounds, img, image.Pt(0, 0), draw.Src)
			dx, dy := bounds.Dx(), bounds.Dy()
			for y := 0; y < dy; y++ {
				for x := 0; x < dx; x++ {
					r, g, b, _ := nrgba.At(x, y).RGBA()
					sr, sg, sb := byte(r)/16, byte(g)/16, byte(b)/16
					fmt.Printf("#%X%X%X", sr, sg, sb)
				}
				fmt.Println()
			}
		}
		fmt.Println("\x0c")
		os.Stdout.Sync()
	}
}
