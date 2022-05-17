#!/bin/bash

TMPFILE="$(mktemp)"
RANDOM_KEY=$(echo $RANDOM | md5sum | head -c 20; echo)
KUBESAIL_AGENT_KEY="$(sudo kubectl -n kubesail-agent get pods -o yaml | fgrep KUBESAIL_AGENT_KEY -A1 | tail -n1 | awk '{print $2}')"
if [ -z "${KUBESAIL_AGENT_KEY}" ]; then
  KUBESAIL_AGENT_KEY="no-agent"
fi

if [ -f /etc/pibox-release ]; then
    echo -e "\n\nPiBox version ==============" >> ${TMPFILE}
    cat /etc/pibox-release >> ${TMPFILE}
fi
if [ -f /etc/os-release ]; then
    echo -e "\n\nOS version ==============" >> ${TMPFILE}
    cat /etc/os-release >> ${TMPFILE}
fi

echo -e "\n\nKernel ==============\n $(uname -a)" >> ${TMPFILE}

echo -e "\n\nkubectl version ==============" >> ${TMPFILE}
sudo kubectl version >> ${TMPFILE}

echo -e "\n\nk3s check-config ==============" >> ${TMPFILE}
sudo k3s check-config >> ${TMPFILE}

echo -e "\n\nkubectl get nodes ==============" >> ${TMPFILE}
sudo kubectl get nodes >> ${TMPFILE}

echo -e "\n\nkubectl -n kube-system get pods ==============" >> ${TMPFILE}
sudo kubectl -n kube-system get pods >> ${TMPFILE}

echo -e "\n\nkubectl -n kube-system describe traefik ==============" >> ${TMPFILE}
sudo kubectl -n kube-system describe pod -l "app.kubernetes.io/name=traefik"

echo -e "\n\nkubectl -n kube-system logs traefik ==============" >> ${TMPFILE}
sudo kubectl -n kube-system logs -l "app.kubernetes.io/name=traefik"

echo -e "\n\nkubectl -n kube-system describe svclb-traefik ==============" >> ${TMPFILE}
sudo kubectl -n kube-system describe pods -l app=svclb-traefik

echo -e "\n\nkubectl -n kube-system logs svclb-traefik ==============" >> ${TMPFILE}
sudo kubectl -n kube-system logs -l app=svclb-traefik -c "lb-port-443"

echo -e "\n\nkubectl -n kubesail-agent describe pods ==============" >> ${TMPFILE}
sudo kubectl -n kubesail-agent describe pods >> ${TMPFILE}

echo -e "\n\nkubectl -n kubesail-agent logs -l app=kubesail-agent ==============" >> ${TMPFILE}
sudo kubectl -n kubesail-agent logs -l app=kubesail-agent --tail=-1 >> ${TMPFILE}

echo "Wrote logs to ${TMPFILE}"
gzip ${TMPFILE}

curl -s -H "Content-Type: application/json" -X POST --data-binary @${TMPFILE}.gz "https://api.kubesail.com/agent/upload-debug-logs/${KUBESAIL_AGENT_KEY}/${RANDOM_KEY}"
echo -e "\nUploaded logs to KubeSail support. Please provide the code \"${RANDOM_KEY}\" - thank you"
