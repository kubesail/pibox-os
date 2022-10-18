#!/bin/bash

TMPFILE="$(mktemp)"
KUBECTL="sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl"
RANDOM_KEY=$(echo $RANDOM | md5sum | head -c 20; echo)
KUBESAIL_AGENT_KEY="$(${KUBECTL} -n kubesail-agent get pods -o yaml | fgrep KUBESAIL_AGENT_KEY -A1 | tail -n1 | awk '{print $2}')"
if [ -z "${KUBESAIL_AGENT_KEY}" ]; then
  KUBESAIL_AGENT_KEY="no-agent"
fi

echo "Support script starting - this may take a moment."

if [ -f /etc/pibox-release ]; then
    echo -e "\n\nPiBox version ==============" >> ${TMPFILE}
    sudo cat /etc/pibox-release >> ${TMPFILE}
fi
if [ -f /etc/os-release ]; then
    echo -e "\n\nOS version ==============" >> ${TMPFILE}
    sudo cat /etc/os-release >> ${TMPFILE}
fi

echo -e "\n\nKernel ==============\n $(uname -a)" >> ${TMPFILE}

echo -e "\n\nCPU model ==============" >> ${TMPFILE}
sudo cat /proc/cpuinfo | fgrep 'model' | uniq >> ${TMPFILE}

echo -e "\n\nMemory / load / file-nr ==============" >> ${TMPFILE}
sudo free -m >> ${TMPFILE}
sudo uptime >> ${TMPFILE}
sudo cat /proc/sys/fs/file-nr

echo -e "\n\nls -al /opt/kubesail ==============" >> ${TMPFILE}
sudo ls -al /opt/kubesail/ >> ${TMPFILE}

echo -e "\n\nls -al /var/lib/rancher/k3s/ ==============" >> ${TMPFILE}
sudo ls -al /var/lib/rancher/k3s/ >> ${TMPFILE}

echo -e "\n\ngrep rancher /etc/fstab ==============" >> ${TMPFILE}
sudo grep rancher /etc/fstab >> ${TMPFILE}

echo -e "\n\nfindmnt -s ==============" >> ${TMPFILE}
sudo findmnt -s >> ${TMPFILE}

echo -e "\n\nfindmnt /var/lib/rancher ==============" >> ${TMPFILE}
sudo findmnt /var/lib/rancher >> ${TMPFILE}

echo -e "\n\ndf -h ==============" >> ${TMPFILE}
sudo df -h | egrep -v "(containerd|kubernetes|overlay)" >> ${TMPFILE}

echo -e "\n\nsystemctl status var-lib-rancher.mount ==============" >> ${TMPFILE}
sudo systemctl status var-lib-rancher.mount >> ${TMPFILE}

echo -e "\n\nkubectl version ==============" >> ${TMPFILE}
${KUBECTL} version >> ${TMPFILE}

echo -e "\n\nk3s check-config ==============" >> ${TMPFILE}
sudo k3s check-config >> ${TMPFILE}

echo -e "\n\nk3s logs ==============" >> ${TMPFILE}
sudo journalctl -u k3s -n 25 --no-tail --no-pager >> ${TMPFILE}

echo -e "\n\nk3s --version ==============" >> ${TMPFILE}
sudo k3s --version >> ${TMPFILE}

# echo -e "\n\nk3s ctr images ls ==============" >> ${TMPFILE}
# sudo k3s ctr images ls >> ${TMPFILE}

echo -e "\n\nservice k3s status ==============" >> ${TMPFILE}
sudo service k3s status >> ${TMPFILE}

echo -e "\n\nls -la /etc/systemd/system/k3s.service.d/ ==============" >> ${TMPFILE}
sudo ls -al /etc/systemd/system/k3s.service.d/ >> ${TMPFILE}

echo -e "\n\nkubectl get nodes ==============" >> ${TMPFILE}
${KUBECTL} get nodes >> ${TMPFILE}

echo -e "\n\nkubectl get pods -A ==============" >> ${TMPFILE}
${KUBECTL} get pods -A >> ${TMPFILE}

echo -e "\n\nkubectl -n kubesail-agent describe pods ==============" >> ${TMPFILE}
${KUBECTL} -n kubesail-agent describe pods >> ${TMPFILE}

echo -e "\n\nkubectl -n kubesail-agent logs -l app=kubesail-agent ==============" >> ${TMPFILE}
${KUBECTL} -n kubesail-agent logs -l app=kubesail-agent --tail=-1 >> ${TMPFILE}

echo -e "\n\njournalctl -u pibox-framebuffer -n 200 ==============" >> ${TMPFILE}
sudo journalctl -u pibox-framebuffer -n 200 >> ${TMPFILE}

echo -e "\n\nlvdisplay ==============" >> ${TMPFILE}
sudo lvdisplay >> ${TMPFILE}

echo -e "\n\npvdisplay ==============" >> ${TMPFILE}
sudo pvdisplay >> ${TMPFILE}

echo -e "\n\nifconfig ==============" >> ${TMPFILE}
sudo ifconfig >> ${TMPFILE}

sudo kubectl get pods -A | grep Unknown && {
  read -p "It looks like there is an issue we know how to fix automatically. Run fix-it script? [y/n] " yn
  if [[ $yn =~ ^[Yy]$ ]]
  then
    for i in $(sudo k3s ctr c ls | awk '{print $1}'); do sudo k3s ctr c rm $i; done
    sudo service k3s restart
    echo "All done - things should be back up and running in just a moment"
  fi
}

sudo kubectl get namespaces kubesail-agent || {
  read -p "It looks like the KubeSail agent may not be installed properly. Would you like to fix it? [y/n] " yn
  if [[ $yn =~ ^[Yy]$ ]]
  then
    sudo kubectl create -f https://api.kubesail.com/byoc
    echo "QR Code should appear in just a few moments"
  fi
}

GREEN="\e[32m"
ENDCOLOR="\e[0m"

echo -e "\n${GREEN}NOTE:${ENDCOLOR}"
echo "We can create a secure remote-access session to your PiBox to help you debug your issue."
read -p "Would you like to enable this? [y/n]" yn
kubesail_tmate="none"
if [[ $yn =~ ^[Yy]$ ]]
then
  sudo apt --yes install tmate
  tmate -F > /tmp/tmate-${RANDOM_KEY} &
  sleep 3
  kubesail_tmate=$(cat /tmp/tmate-${RANDOM_KEY} | base64 -w 0)
fi

echo -e "\nPlease enter your email address, Discord username, or some other way for us to reach you."
read -p "This will only be used by support staff to respond to this help request: " email
sudo echo -e "\n\nEMAIL: $email" >> ${TMPFILE}

echo "Wrote logs to ${TMPFILE}"
gzip ${TMPFILE}

curl -s -H "Content-Type: application/json" -H "x-kubesail-tmate: ${kubesail_tmate}" -H "x-kubesail-logs-ident: ${email}" -X POST --data-binary @${TMPFILE}.gz "https://api.kubesail.com/agent/upload-debug-logs/${KUBESAIL_AGENT_KEY}/${RANDOM_KEY}"
echo -e "\nUploaded logs to KubeSail support. Please provide the code \"${RANDOM_KEY}\" - thank you"


