#!/bin/bash
set -x

FB_VERSION="v$(curl --connect-timeout 10 -L https://raw.githubusercontent.com/kubesail/pibox-framebuffer/main/VERSION.txt)"
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

if [[ -f /etc/os-release ]]; then
  if grep Debian /etc/os-release; then
    apt-get install -yqq lvm2
  fi
fi

set -e

if [[ -f /etc/systemd/system/pibox-framebuffer.service ]]; then
  echo "stopping pibox-framebuffer service"
  service pibox-framebuffer stop
fi

architecture="arm64"
case $(uname -m) in
  x86_64) architecture="amd64" ;;
  arm)    dpkg --print-architecture | grep -q "arm64" && architecture="arm64" || architecture="arm" ;;
esac

FB_PATH=/opt/kubesail/pibox-framebuffer-$FB_VERSION
mkdir -p /opt/kubesail/
echo "downloading pibox-framebuffer $FB_VERSION"

if [[ ! -f $FB_PATH ]]; then
    curl --connect-timeout 10 -sLo $FB_PATH https://github.com/kubesail/pibox-framebuffer/releases/download/$FB_VERSION/pibox-framebuffer-linux-${architecture}-$FB_VERSION
    chmod +x $FB_PATH
fi

if [[ -f /opt/kubesail/pibox-framebuffer ]]; then
  rm -v /opt/kubesail/pibox-framebuffer
fi

if [[ ! -f /opt/kubesail/pibox-framebuffer ]]; then
  ln -vs $FB_PATH /opt/kubesail/pibox-framebuffer
fi

chown -R kubesail-agent: /opt/kubesail/ || true

if [[ ! -f /etc/systemd/system/pibox-framebuffer.service ]]; then
  cat <<'EOF' > /etc/systemd/system/pibox-framebuffer.service
[Unit]
Requires=multi-user.target
After=multi-user.target
[Service]
ExecStart=/opt/kubesail/pibox-framebuffer
Restart=always
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable pibox-framebuffer.service
fi

echo "starting pibox-framebuffer service"
service pibox-framebuffer start
