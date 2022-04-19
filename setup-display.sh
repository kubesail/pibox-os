#!/bin/bash
pudhd st7789_module
make
mv /lib/modules/"$(uname -r)"/kernel/drivers/staging/fbtft/fb_st7789v.ko /lib/modules/"$(uname -r)"/kernel/drivers/staging/fbtft/fb_st7789v.BACK
mv fb_st7789v.ko /lib/modules/"$(uname -r)"/kernel/drivers/staging/fbtft/fb_st7789v.ko
popd
dtc --warning no-unit_address_vs_reg -I dts -O dtb -o /boot/overlays/drm-minipitft13.dtbo overlays/minipitft13-overlay.dts
sed -i 's/$/ fbcon=map:1/' /boot/cmdline.txt
cat <<EOF >> /boot/config.txt
dtoverlay=spi0-1cs
dtoverlay=dwc2,dr_mode=host
hdmi_force_hotplug=1
framebuffer_priority=2
dtoverlay=drm-minipitft13,rotate=0,fps=60
EOF