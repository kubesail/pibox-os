#!/bin/bash
git clone https://github.com/kubesail/pibox-os.git /tmp/pibox-os
pushd /tmp/pibox-os/st7789_module
make
mv /lib/modules/"$(uname -r)"/kernel/drivers/staging/fbtft/fb_st7789v.ko /lib/modules/"$(uname -r)"/kernel/drivers/staging/fbtft/fb_st7789v.BACK
mv fb_st7789v.ko /lib/modules/"$(uname -r)"/kernel/drivers/staging/fbtft/fb_st7789v.ko
popd
dtc --warning no-unit_address_vs_reg -I dts -O dtb -o /boot/overlays/drm-minipitft13.dtbo /tmp/pibox-os/overlays/minipitft13-overlay.dts
#Console serial
sed -i 's/console=tty1 //' /boot/cmdline.txt
systemctl disable getty@tty1.service
cat <<EOF >> /boot/config.txt
dtoverlay=spi0-1cs
dtoverlay=dwc2,dr_mode=host
hdmi_force_hotplug=1
dtoverlay=drm-minipitft13,rotate=0,fps=60
EOF