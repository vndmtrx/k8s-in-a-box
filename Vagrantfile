# -*- mode: ruby -*-
# vi: set ft=ruby :

# Para executar no LibVirt sem precisar de senha de root:
# - sudo usermod -a -G libvirt $(whoami)
# - sudo usermod -a -G kvm $(whoami)
# - sudo usermod -a -G libvirt-qemu $(whoami)

ENV["VAGRANT_DEFAULT_PROVIDER"] = "libvirt"
PROJETO = "k8sbox"

# Definição dos nodes com seus IPs e recursos
nodes = {
  "loadbalancer1" => { "ip" => "172.24.0.21", "memory" => 512,  "cpus" => 1 },
  "manager1"      => { "ip" => "172.24.0.31", "memory" => 2048, "cpus" => 2 },
  "manager2"      => { "ip" => "172.24.0.32", "memory" => 2048, "cpus" => 2 },
  "manager3"      => { "ip" => "172.24.0.33", "memory" => 2048, "cpus" => 2 },
  "worker1"       => { "ip" => "172.24.0.41", "memory" => 4096, "cpus" => 2 },
  "worker2"       => { "ip" => "172.24.0.42", "memory" => 4096, "cpus" => 2 }
}

# Definição das linhas do /etc/hosts das máquinas, baseado na informação dos nodes, acima
entradas_cluster = nodes.map do |nome, specs|
  "#{specs["ip"]} #{nome}.#{PROJETO}.local"
end.join("\n")

Vagrant.configure("2") do |config|
  # Gera a chave SSH se não existir
  unless File.exist?('id_ed25519') && File.exist?('id_ed25519.pub')
    system('ssh-keygen -t ed25519 -f id_ed25519 -N "" >/dev/null 2>&1')
    puts "Nova chave SSH gerada."
  end

  # Lê o conteúdo da chave pública
  pubkey = File.read('id_ed25519.pub').strip rescue ""

  # Remove as chaves após destruir todas as VMs
  config.trigger.after :destroy do |trigger|
    trigger.ruby do |env, machine|
      if File.exist?('id_ed25519')
        File.delete('id_ed25519')
        File.delete('id_ed25519.pub')
        puts "Chave SSH removida."
      end
    end
  end

  # Imagem a ser utilizada
  config.vm.box = "almalinux/10"
  config.vm.post_up_message = ""
  config.ssh.insert_key = false
  #config.vm.synced_folder "./", "/vagrant", type: "virtiofs",  mount_options: ["noseclabel"]
  config.vm.synced_folder "./", "/vagrant", disabled: true

  # Configuração comum para todas as VMs (LibVirt)
  config.vm.provider :libvirt do |libvirt|
    libvirt.driver = "kvm"
    libvirt.memorybacking :source, :type => "memfd"
    libvirt.memorybacking :access, :mode => "shared"

    libvirt.cpu_mode = "host-model"
    libvirt.nested = true

    libvirt.nic_model_type = "virtio"
    libvirt.management_network_name = "vagrant"
    libvirt.management_network_address = "192.168.250.0/24"
    libvirt.management_network_mode = "none"
    libvirt.management_network_autostart = true
  end

  nodes.each do |nome_no, specs|
    config.vm.define nome_no do |node|
      node.vm.hostname = nome_no
      node.vm.network "private_network", ip: specs["ip"],
        libvirt__network_name: "#{PROJETO}_mgmt",
        libvirt__forward_mode: "nat",
        libvirt__dhcp_enabled: false

      # Sobrescreve as configurações de memória e CPU para cada VM
      node.vm.provider :libvirt do |libvirt_host|
        libvirt_host.default_prefix = "#{PROJETO}_"
        libvirt_host.memory = specs["memory"]
        libvirt_host.cpus = specs["cpus"]
      end

      # Adiciona a chave pública se ela não existir
      if !pubkey.empty?
        node.vm.provision "shell" do |s|
          s.inline = <<-SHELL
            PUBKEY="#{pubkey}"
            if ! grep -q "$PUBKEY" /home/vagrant/.ssh/authorized_keys; then
              echo "$PUBKEY" >> /home/vagrant/.ssh/authorized_keys
              echo "Chave SSH adicionada."
            else
              echo "A chave SSH já existe no arquivo authorized_keys."
            fi
          SHELL
        end
      end

      # Ajustes manuais na rede das VMs
      node.vm.provision "shell" do |net|
        net.inline = <<-SHELL
          (
            # --- Ajustes padrões da conexão do Vagrant ---
            nmcli con mod eth0 connection.autoconnect yes
            nmcli con mod eth0 connection.autoconnect-priority -999
            nmcli con mod eth0 ipv4.route-metric 500
            nmcli con mod eth0 ipv4.ignore-auto-dns yes
            nmcli con mod eth0 ipv4.never-default yes
            nmcli con mod eth0 ipv6.method ignore
            nmcli con down eth0 && nmcli con up eth0

            # --- Remove conexões automáticas, se existirem ---
            nmcli -t -f NAME con show | grep -qx "System eth1" && nmcli con delete "System eth1"

            # --- Cria conexão persistente net_mgmt se não existir ---
            nmcli -t -f NAME con show | grep -qx "net_mgmt" || \
              nmcli con add type ethernet con-name net_mgmt ifname eth1 \
                ipv4.method manual \
                ipv4.addresses "#{specs["ip"]}/24" \
                ipv4.gateway "172.24.0.1" \
                ipv4.route-metric "50" \
                ipv4.dns "1.1.1.1,8.8.8.8" \
                ipv6.method ignore \
                ipv4.dns-search "#{PROJETO}.local"
            
            # --- Ativa a conexão ---
            nmcli con up net_mgmt
          ) > /dev/null
          echo "Provisionamento de rede concluído."
        SHELL
      end
    end
  end
end
