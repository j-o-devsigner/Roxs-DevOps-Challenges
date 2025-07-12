# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # Configuración de la caja base
  config.vm.box = "ubuntu/focal64"

  # Configuración de la red
  config.vm.network "forwarded_port", guest: 80, host: 4999 # Vote
  config.vm.network "forwarded_port", guest: 3000, host: 5000 # Worker
  config.vm.network "forwarded_port", guest: 3001, host: 5001 # Result
  
  # Configuración de la memoria y CPU
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "2048"
  end

  # Configuración de Ansible
  config.vm.provision "ansible_local" do |ansible|
    ansible.playbook = "provisioning/playbook.yml"
  end

  # Lanzar las aplicaciones después de que Ansible termine.
  config.vm.provision "shell", path: "scripts/setup.sh"
end
