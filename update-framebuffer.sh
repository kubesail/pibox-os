#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

echo "stopping pibox-framebuffer service"
service pibox-framebuffer stop

architecture="arm64"
case $(uname -m) in
  x86_64) architecture="amd64" ;;
  arm)    dpkg --print-architecture | grep -q "arm64" && architecture="arm64" || architecture="arm" ;;
esac
FB_VERSION=v13
FB_PATH=/opt/kubesail/pibox-framebuffer-$FB_VERSION
rm -vf $FB_PATH
echo "downloading pibox-framebuffer $FB_VERSION"
if [[ ! -f $FB_PATH ]]; then
    curl --connect-timeout 10 -sLo $FB_PATH https://github.com/kubesail/pibox-framebuffer/releases/download/$FB_VERSION/pibox-framebuffer-linux-${architecture}-$FB_VERSION
    chmod +x $FB_PATH
    rm /opt/kubesail/pibox-framebuffer
    ln -s $FB_PATH /opt/kubesail/pibox-framebuffer
fi
chown -R kubesail-agent: /opt/kubesail/
ls -alh /opt/kubesail/pibox-framebuffer
echo "starting pibox-framebuffer service"
service pibox-framebuffer start
