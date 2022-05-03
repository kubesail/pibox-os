if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

FB_VERSION=v8
FB_PATH=/opt/kubesail/pibox-framebuffer-$FB_VERSION
if [[ ! -f $FB_PATH ]]; then
    curl --connect-timeout 10 -sLo $FB_PATH https://github.com/kubesail/pibox-framebuffer/releases/download/$FB_VERSION/pibox-framebuffer
    chmod +x $FB_PATH
    rm /opt/kubesail/pibox-framebuffer
    ln -s $FB_PATH /opt/kubesail/pibox-framebuffer
fi
chown -R kubesail-agent: /opt/kubesail/
ls -alh /opt/kubesail/pibox-framebuffer
