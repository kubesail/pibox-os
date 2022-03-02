
Vagrant.configure("2") do |config|

  config.vm.provider "virtualbox" do |vb|
    vb.gui = false
    vb.memory = "4086"
  end

  config.vm.box = "generic/ubuntu2004"

  config.vm.synced_folder "./", "/vagrant", disabled: false

  config.vm.provision "shell", inline: <<-SHELL
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update -yqq && sudo apt-get install -yqq bash curl pigz git net-tools software-properties-common
    sudo apt-get install -yqq \
        kpartx \
        qemu-user-static \
        git \
        wget \
        curl \
        vim \
        unzip \
        gcc

    # Download specific Go version
    echo "Removing existing Go packages and installing Go"
    [[ -e /tmp/go ]] && rm -rf /tmp/go*
    sudo apt-get remove -yqq 'golang-*'
    cd /tmp
    wget -q https://go.dev/dl/go1.16.14.linux-amd64.tar.gz
    tar xf go1.16.14.linux-amd64.tar.gz
    cp -r go /usr/lib/go-1.16
    rm -rf /tmp/go*

    # Set GO paths for vagrant user
    echo 'export GOROOT=/usr/lib/go-1.16
    export GOPATH=$HOME/work
    export PATH=$PATH:$GOROOT/bin:$GOPATH/bin' | tee -a /home/vagrant/.profile

    # Also set them while we work:
    export GOROOT=/usr/lib/go-1.16
    export GOPATH=$HOME/work
    export PATH=$PATH:$GOROOT/bin:$GOPATH/bin

    PACKER_VERSION="1.7.10"

    # Download and install packer
    [[ -e /tmp/packer ]] && rm -rf /tmp/packer*
    wget https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip \
        -q -O /tmp/packer_${PACKER_VERSION}_linux_amd64.zip
    cd /tmp
    unzip -u packer_${PACKER_VERSION}_linux_amd64.zip
    cp -v packer /usr/local/bin
    rm -rf /tmp/packer*
    cd ..

    mkdir -p $GOPATH/src/github.com/solo-io/
    cd $GOPATH/src/github.com/solo-io/
    git clone https://github.com/solo-io/packer-plugin-arm-image
    cd packer-plugin-arm-image
    go mod download
    go build
    mv -v packer-plugin-arm-image /home/vagrant/
  SHELL
end
