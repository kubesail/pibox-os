# SPDX-FileCopyrightText: 2021 ladyada for Adafruit Industries
# SPDX-License-Identifier: MIT

# -*- coding: utf-8 -*-

### WARNING: THIS IS OUTDATED! We've rewritten this in Go. Please see https://github.com/kubesail/pibox-framebuffer/blob/main/main.go

import sys
import io
import time
import subprocess
import digitalio
import board
import requests
from PIL import Image, ImageDraw, ImageFont
import adafruit_rgb_display.st7789 as st7789
import adafruit_rgb_display.rgb as rgb

# Configuration for CS and DC pins (these are FeatherWing defaults on M0/M4):
cs_pin = digitalio.DigitalInOut(board.CE1)
dc_pin = digitalio.DigitalInOut(board.D25)
reset_pin = None

# Config for display baudrate (default max is 24mhz):
BAUDRATE = 64000000

# Setup SPI bus using hardware SPI:
spi = board.SPI()

# Create the ST7789 display:
disp = st7789.ST7789(
    spi,
    cs=cs_pin,
    dc=dc_pin,
    rst=reset_pin,
    baudrate=BAUDRATE,
    width=240,
    height=240,
    x_offset=0,
    y_offset=80,
)

# Create blank image for drawing.
# Make sure to create image with mode 'RGB' for full color.
height = disp.width  # we swap height/width to rotate it to landscape!
width = disp.height
image = Image.new("RGB", (width, height))
rotation = 180

# Get drawing object to draw on image.
draw = ImageDraw.Draw(image)

# Draw a black filled box to clear the image.
draw.rectangle((0, 0, width, height), outline=0, fill=(23, 24, 25))
disp.image(image, rotation)
# Draw some shapes.
# First define some constants to allow easy resizing of shapes.
padding = -2
top = padding
bottom = height - padding
# Move left to right keeping track of the current x position for drawing shapes.

databaseIcon = Image.open("databaseIcon.png").convert('RGB')

# Alternatively load a TTF font.  Make sure the .ttf font file is in the
# same directory as the python script!
# Some other nice fonts to try: http://www.dafont.com/bitmap.php
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 20)
fontsmall = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
fontvsmall = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)

# Turn on the backlight
backlight = digitalio.DigitalInOut(board.D22)
backlight.switch_to_output()
backlight.value = True

public_ip = 'No internet!'

def get_public_ip():
    global public_ip
    try:
        public_ip = requests.get('https://api.kubesail.com/whatsmyip', timeout=3).content.decode("utf-8")
    except:
        public_ip = 'No internet!'

# TODO: Call this every few minutes
get_public_ip()

def draw_screen():
    # Draw a black filled box to clear the image.
    draw.rectangle((0, 0, width, height), outline=0, fill=(23, 24, 25))

    # Shell scripts for system monitoring from here:
    # https://unix.stackexchange.com/questions/119126/command-to-display-memory-usage-disk-usage-and-cpu-load
    cmd = "hostname -I | cut -d' ' -f1"
    IP = subprocess.check_output(cmd, shell=True).decode("utf-8")
    # cmd = "top -bn1 | grep load | awk '{printf \"CPU %.0f%\", $(NF-2)}'"
    cmd = "top -bn1 | grep \"Cpu(s)\" | sed \"s/.*, *\([0-9.]*\)%* id.*/\\1/\" | awk '{print 100 - $1\"%\"}'"
    CPU = subprocess.check_output(cmd, shell=True).decode("utf-8")
    cmd = "free -m | awk 'NR==2{printf \"Mem %.0f%\", $3*100/$2 }'"
    MemUsage = subprocess.check_output(cmd, shell=True).decode("utf-8")
    cmd = 'df -h | awk \'$NF=="/"{printf "%d of %d GB", $3,$2}\''
    Disk = subprocess.check_output(cmd, shell=True).decode("utf-8")
    cmd = 'df -h | awk \'$NF=="/"{printf "%s", $5}\''
    DiskPct = subprocess.check_output(cmd, shell=True).decode("utf-8")
    cmd = "cat /sys/class/thermal/thermal_zone0/temp |  awk '{printf \"CPU Temp: %.1f C\", $(NF-0) / 1000}'"  # pylint: disable=line-too-long
    Temp = subprocess.check_output(cmd, shell=True).decode("utf-8")

    
    y = 0
    #draw.text((x, y), IP, font=font, fill="#FFFFFF")
   
    cpuChart = requests.get('http://localhost:8080?g0.expr=avg(rate(node_cpu_seconds_total%7Bmode%3D%22user%22%7D%5B5m%5D))&from=-30m&width=250&height=50&hideLegend=true&hideYAxis=true&hideXAxis=true&yDivisors=1&margin=0&hideGrid=true&graphOnly=true')
    cpu = Image.open(io.BytesIO(cpuChart.content)).convert('RGB')
    y += fontsmall.getsize(CPU)[1]
    image.paste(cpu, (-10, 20))
    draw.text((0, 10), "CPU " + CPU, font=fontsmall, fill="#FFFF00")
    y += 80

    memChart = requests.get('http://localhost:8080?g0.expr=%28avg_over_time%28node_memory_MemFree_bytes%5B5m%5D%29%20%2F%20avg_over_time%28node_memory_MemTotal_bytes%5B5m%5D%29%29%20%2A%20100&from=-30m&width=250&height=50&hideLegend=true&hideYAxis=true&hideXAxis=true&yDivisors=1&margin=0&hideGrid=true&graphOnly=true')
    mem = Image.open(io.BytesIO(memChart.content)).convert('RGB')
    y += fontsmall.getsize(MemUsage)[1]
    image.paste(mem, (-10, 90))
    draw.text((0, 80), MemUsage, font=fontsmall, fill="#00FF00")
    y += 90

    draw.text((110, 155), DiskPct, font=font, fill="#00FF00")
    draw.text((110, 180), Disk, font=fontvsmall, fill="#00FF00")
    image.paste(databaseIcon, (60, 155))

    y = 230 - fontvsmall.getsize(IP)[1]
    x = 238 - fontvsmall.getsize(public_ip)[0]
    draw.text((0, y), IP, font=fontvsmall, fill="#00FF00")
    draw.text((x, y), public_ip, font=fontvsmall, fill="#00FF00")

    # Display image.
    disp.image(image, rotation, 0,0)

while True:
    try:
        draw_screen()
    except:
        print("Unexpected error:", sys.exc_info()[0])
    time.sleep(2)
