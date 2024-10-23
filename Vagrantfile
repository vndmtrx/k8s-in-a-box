# -*- mode: ruby -*-
# vi: set ft=ruby :

# Para executar no LibVirt sem precisar de senha de root:
# - sudo usermod -a -G libvirt $(whoami)
# - sudo usermod -a -G kvm $(whoami)

Vagrant.configure("2") do |config|
  # Imagem a ser utilizada
  config.vm.box = "debian/bookworm64"

  config.vm.synced_folder ".", "/vagrant", type: "rsync", rsync__exclude: [".git/", ".vagrant/"]

  # Configuração comum para todas as VMs (VirtualBox)
  config.vm.provider "virtualbox" do |v|
    v.memory = 2048
    v.cpus = 2
    v.default_nic_type = "virtio"
  end

  # Configuração comum para todas as VMs (LibVirt)
  config.vm.provider :libvirt do |libvirt|
    libvirt.memory = 2048
    libvirt.cpus = 2
  end

  nodes = {
    "k8s-lb" => "172.24.0.11",
    "k8s-manager1" => "172.24.0.21",
    "k8s-worker1" => "172.24.0.31",
    "k8s-worker2" => "172.24.0.32"
  }

  nodes.each do |node_name, ip|
    config.vm.define node_name do |node|
      node.vm.hostname = node_name
      node.vm.network "private_network", ip: ip

      # Adiciona a chave pública se ela não existir
      node.vm.provision "shell" do |s|
        ssh_pub_key = File.readlines("./id_ed25519.pub").first.strip
        s.inline = <<-SHELL
          if ! grep -q "#{ssh_pub_key}" /home/vagrant/.ssh/authorized_keys; then
            echo #{ssh_pub_key} >> /home/vagrant/.ssh/authorized_keys
            echo "Chave SSH adicionada."
          else
            echo "A chave SSH já existe no arquivo authorized_keys."
          fi
        SHELL
      end
    end
  end
end
