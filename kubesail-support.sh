#!/bin/bash

set -x

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
    cat /etc/pibox-release >> ${TMPFILE}
fi
if [ -f /etc/os-release ]; then
    echo -e "\n\nOS version ==============" >> ${TMPFILE}
    cat /etc/os-release >> ${TMPFILE}
fi

echo -e "\n\nKernel ==============\n $(uname -a)" >> ${TMPFILE}

echo -e "\n\nCPU model ==============" >> ${TMPFILE}
cat /proc/cpuinfo | fgrep 'model name' | uniq >> ${TMPFILE}

echo -e "\n\nMemory / load ==============" >> ${TMPFILE}
free -m >> ${TMPFILE}
uptime >> ${TMPFILE}

echo -e "\n\nkubectl version ==============" >> ${TMPFILE}
${KUBECTL} version >> ${TMPFILE}

echo -e "\n\nk3s check-config ==============" >> ${TMPFILE}
sudo k3s check-config >> ${TMPFILE}

echo -e "\n\nk3s logs ==============" >> ${TMPFILE}
journalctl -u k3s -n 25 --no-tail --no-pager >> ${TMPFILE}

echo -e "\n\nk3s --version ==============" >> ${TMPFILE}
sudo k3s --version >> ${TMPFILE}

echo -e "\n\nk3s ctr images ls ==============" >> ${TMPFILE}
sudo k3s ctr images ls >> ${TMPFILE}

echo -e "\n\nservice k3s status ==============" >> ${TMPFILE}
sudo service k3s status >> ${TMPFILE}

echo -e "\n\nls -la /etc/systemd/system/k3s.service.d/ ==============" >> ${TMPFILE}
sudo ls -al /etc/systemd/system/k3s.service.d/ >> ${TMPFILE}

echo -e "\n\nkubectl get nodes ==============" >> ${TMPFILE}
${KUBECTL} get nodes >> ${TMPFILE}

echo -e "\n\nkubectl -n kube-system get pods ==============" >> ${TMPFILE}
${KUBECTL} -n kube-system get pods >> ${TMPFILE}

echo -e "\n\nkubectl -n kubesail-agent describe pods ==============" >> ${TMPFILE}
${KUBECTL} -n kubesail-agent describe pods >> ${TMPFILE}

echo -e "\n\nkubectl -n kubesail-agent logs -l app=kubesail-agent ==============" >> ${TMPFILE}
${KUBECTL} -n kubesail-agent logs -l app=kubesail-agent --tail=-1 >> ${TMPFILE}

echo "Wrote logs to ${TMPFILE}"
gzip ${TMPFILE}

curl -s -H "Content-Type: application/json" -X POST --data-binary @${TMPFILE}.gz "https://api.kubesail.com/agent/upload-debug-logs/${KUBESAIL_AGENT_KEY}/${RANDOM_KEY}"
echo -e "\nUploaded logs to KubeSail support. Please provide the code \"${RANDOM_KEY}\" - thank you"
