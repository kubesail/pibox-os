# Warning, this DELETES ALL DATA IN K3s!!
# This script is useful if you have very large disks and are okay hard-resetting things
sudo /usr/local/bin/k3s-uninstall.sh
sudo service k3s stop
sudo killall containerd-shim
sudo umount /var/lib/rancher
sudo wipefs -af /dev/pibox-group/k3s
sudo lvremove /dev/pibox-group/k3s
sudo vgreduce --removemissing pibox-group
sudo vgremove pibox-group
sudo pvremove /dev/sda1
sudo pvremove /dev/sdb1
sudo wipefs -a /dev/sda1
sudo wipefs -a /dev/sdb1
sudo sfdisk --delete /dev/sda 1
sudo sfdisk --delete /dev/sdb 1
sudo wipefs -a /dev/sda
sudo wipefs -a /dev/sdb
sudo parted /dev/sda – mklabel gpt
sudo parted /dev/sda – mkpart primary 0% 100%
sudo parted /dev/sdb – mklabel gpt
sudo parted /dev/sdb – mkpart primary 0% 100%
VG_GROUP_NAME="pibox-group"
sudo vgcreate "${VG_GROUP_NAME}" /dev/sda1 /dev/sdb1
sudo lvcreate -n k3s -l "100%FREE" "${VG_GROUP_NAME}"
sudo mkfs.ext4 -F -m 0 -b 4096 "/dev/${VG_GROUP_NAME}/k3s"
sudo tune2fs -O fast_commit "/dev/${VG_GROUP_NAME}/k3s"
sudo e2fsck -p -f "/dev/${VG_GROUP_NAME}/k3s"
sudo mount /var/lib/rancher
## At this point, your disks are ready! Let's re-install k3s:
curl --connect-timeout 10 --retry 5 --retry-delay 3 -L https://get.k3s.io | INSTALL_K3S_CHANNEL=stable INSTALL_K3S_EXEC="server --cluster-cidr=172.31.10.0/24 --no-deploy traefik --disable=traefik --kubelet-arg container-log-max-files=3 --kubelet-arg container-log-max-size=10Mi" sh
# and re-install KubeSail agent:
sudo kubectl create -f https://api.kubesail.com/byoc