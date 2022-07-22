# PiBox OS

[Download the latest version](https://github.com/kubesail/pibox-os/releases)

This repository contains scripts and kernel modules used to modify Raspberry Pi OS in order to take full advantage of the PiBox hardware.

## The whole script

This script installs everything (PWM, screen, k3s, and KubeSail agent)

```bash
curl -s https://raw.githubusercontent.com/kubesail/pibox-os/main/provision-os.sh | sudo bash
```

## PWM Fan Support

To make the fan quiet and only spin as fast as necessary, we install a service that sends the correct signal to the fan using the Pi's hardware PWM controller. See the [pwm-fan](pwm-fan) directory for details.

## LCD display

We developed a display service that draws stats and other useful info to the display. To install it:

```bash
# Clone PiBox OS repo
git clone https://github.com/kubesail/pibox-os.git

# Enable Display Driver
pushd pibox-os/st7789_module
make
mv /lib/modules/"$(uname -r)"/kernel/drivers/staging/fbtft/fb_st7789v.ko /lib/modules/"$(uname -r)"/kernel/drivers/staging/fbtft/fb_st7789v.BACK
mv fb_st7789v.ko /lib/modules/"$(uname -r)"/kernel/drivers/staging/fbtft/fb_st7789v.ko
popd
dtc --warning no-unit_address_vs_reg -I dts -O dtb -o /boot/overlays/drm-minipitft13.dtbo pibox-os/overlays/minipitft13-overlay.dts
cat <<EOF >> /boot/config.txt
dtoverlay=spi0-1cs
dtoverlay=dwc2,dr_mode=host
hdmi_force_hotplug=1
dtoverlay=drm-minipitft13,rotate=0,fps=60
EOF

# Download pibox-framebuffer binary
sudo bash pibox-framebuffer/update-framebuffer.sh
```

Then you can follow the instructions here for drawing your own images to the screen https://github.com/kubesail/pibox-framebuffer#pibox-framebuffer

