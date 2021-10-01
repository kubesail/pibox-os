# Raspberry Pi Hardware Based PWM Fan Control

This is a fork of https://gist.github.com/alwynallan/1c13096c4cd675f38405702e89e0c536 for use with the KubeSail PiBox

```bash
git clone https://github.com/kubesail/pibox-os.git
cd pibox-os/pwm-fan
tar zxvf bcm2835-1.68.tar.gz
cd bcm2835-1.68
./configure
make
sudo make install
cd ..
make
sudo make install
```

To stress-test for 3 minutes:

```bash
sudo apt install -y git stress-ng
stress-ng -c 4 -t 3m -q & watch -n1 cat /run/pi_fan_hwpwm.state
```

And Ctrl+C when done.
