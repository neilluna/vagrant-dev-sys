require "pathname"
require "yaml"

module Vagrant_Dev_Sys
  PROJECT_DIR = Pathname.new(__FILE__).dirname.relative_path_from(Pathname.getwd)
  CONFIG_FILE = "config.yml"
  CONFIG_PATH = PROJECT_DIR + CONFIG_FILE

  # Vagrantfile API/syntax version. Do not change this unless you know what you're doing!
  VAGRANTFILE_API_VERSION = "2"

  # Configure the VMs.
  def self.configure
    if !(CONFIG_PATH).file?
      puts "Error: #{CONFIG_PATH} is missing."
      exit!
    end

    config_file = YAML.load_file(CONFIG_PATH)
    virtual_machines = get_array(nil, config_file, "virtual_machines", default: [])

    Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
      virtual_machines.each do |options|
        hostname = get_string(nil, options, "hostname", required: true)
        autostart = get_boolean(hostname, options, "autostart", default: false)
        provider = get_string(hostname, options, "provider", default: "virtualbox")

        if provider == "digitalocean"
          configure_digitalocean(hostname, config, options, autostart)
        elsif provider == "virtualbox"
          configure_virtualbox(hostname, config, options, autostart)
        else
          raise ArgumentError, "#{hostname}: Unsupported provider '#{provider}'."
        end
      end  # virtual_machines.each do |options|
    end  # Vagrant.configure ...  do |config|
  end  # def self.configure

  # Configure a DigitalOcean VM.
  def self.configure_digitalocean(hostname, config, options, autostart)
    digitalocean = get_hash(hostname, options, "digitalocean", required: true)
    options["user"] = "root"
    options["group"] = "root"

    config.vm.define hostname, autostart: autostart do |sys|
      sys.ssh.private_key_path = get_string(hostname, digitalocean, "private_key_file", required: true)
      sys.vm.box = "digital_ocean"
      sys.vm.hostname = hostname
      sys.vm.provider "digital_ocean" do |provider|
        provider.image = get_string(hostname, digitalocean, "image", default: "ubuntu-26-04-x64")
        provider.region = get_string(hostname, digitalocean, "region", default: "nyc2")
        provider.size = get_string(hostname, digitalocean, "size", default: "s-2vcpu-4gb")
        provider.ssh_key_name = get_string(hostname, digitalocean, "ssh_key_name", required: true)
        provider.token = get_string(hostname, digitalocean, "api_token", required: true)
      end  # sys.vm.provider ... do |provider|

      synced_directories(hostname, sys, options)
      provision(hostname, sys, options)
    end  # config.vm.define ... do |sys|
  end  # def self.configure_digitalocean()

  # Configure a VirtualBox VM.
  def self.configure_virtualbox(hostname, config, options, autostart)
    virtualbox = get_hash(hostname, options, "virtualbox", default: {})
    options["user"] = "vagrant"
    options["group"] = "vagrant"

    config.vm.define hostname, autostart: autostart do |sys|
      sys.vm.box = get_string(hostname, virtualbox, "box", default: "bento/ubuntu-26.04")
      sys.vm.hostname = hostname
      sys.vm.provider "virtualbox" do |provider|
        provider.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
        provider.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
        provider.gui = get_boolean(hostname, virtualbox, "gui", default: false)
        provider.memory = get_integer(hostname, virtualbox, "memory", default: 4096)
      end  # sys.vm.provider ... do |provider|

      disk_size = get_string(hostname, virtualbox, "disk_size", default: "default")
      if disk_size != "default"
        sys.disksize.size = disk_size  # Reboot the VM for the change to take effect.
      end

      network = get_hash(hostname, virtualbox, "network", default: {})
      configure_virtualbox_network(hostname, sys, network)

      update_guest_additions = get_boolean(hostname, virtualbox, "update_guest_additions", default: false)
      config.vbguest.auto_update = update_guest_additions
      if update_guest_additions
        sys.vm.provision "shell", reboot: true
      end

      synced_directories(hostname, sys, options)
      provision(hostname, sys, options)
    end  # config.vm.define ... do |sys|
  end  # def self.configure_virtualbox()

  # Configure a VirtualBox VM network.
  def self.configure_virtualbox_network(hostname, sys, network)
    forwarded_ports = get_array(hostname, network, "forwarded_ports", default: [])
    forwarded_ports.each do |port|
      auto_correct = get_boolean(hostname, port, "auto_correct", default: false)
      protocol = get_string(hostname, port, "protocol", default: "tcp")
      sys.vm.network "forwarded_port",
        auto_correct: auto_correct,
        guest: get_integer(hostname, port, "remote", required: true),
        host: get_integer(hostname, port, "host", required: true),
        protocol: protocol
    end  # forwarded_ports.each do |port|

    if network.key?("private_network")
      private_network = get_hash(hostname, network, "private_network")
      ip = get_string(hostname, private_network, "ip", required: true)
      if ip == "dhcp"
        sys.vm.network "private_network", type: "dhcp"
      else
        sys.vm.network "private_network", ip: ip
      end
    elsif network.key?("public_network")
      public_network = get_hash(hostname, network, "public_network")
      interfaces = get_array(hostname, public_network, "interfaces", default: [])
      ip = get_string(hostname, public_network, "ip", required: true)
      if ip == "dhcp"
        if interfaces.empty?
          sys.vm.network "public_network"
        else
          sys.vm.network "public_network", bridge: interfaces
        end
      else  # ip is an ip address
        if interfaces.empty?
          sys.vm.network "public_network", ip: ip
        else
          sys.vm.network "public_network", ip: ip, bridge: interfaces
        end
      end  # if ip == "dhcp" else ip is an ip address
    end  # if network.key?("private_network") elsif network.key?("public_network")

    if network.key?("usable_port_range")
      usable_port_range = get_hash(hostname, network, "usable_port_range")
      start = get_integer(hostname, usable_port_range, "start", required: true)
      stop = get_integer(hostname, usable_port_range, "stop", required: true)
      sys.vm.usable_port_range = (start..stop)
    end
  end  # def self.configure_virtualbox_network()

  # Get an array option from the given options hash.
  # If the key is missing, and it is required, then raise a KeyError.
  # If the key is missing, and it is not required, then return the default value or nil.
  # If the key is present, but the value is missing, then raise an ArgumentError.
  # If the value is not an array, then raise a TypeError.
  # Otherwise, return the array value with its nil elements removed.
  def self.get_array(prefix, opts, key, required: false, default: nil)
    prefix = prefix.to_s.empty? ? "" : "#{prefix}: "
    value = get_option(prefix, opts, key, required, default)
    return value if value.nil?
    raise TypeError, "#{prefix}Value for '#{key}' must be a sequence, not a #{value.class}" unless value.is_a?(Array)
    value.compact
  end

  # Get a boolean option from the given options hash.
  # If the key is missing, and it is required, then raise a KeyError.
  # If the key is missing, and it is not required, then return the default value or nil.
  # If the key is present, but the value is missing, then raise an ArgumentError.
  # If the value is not a boolean, then raise a TypeError.
  # Otherwise, return the boolean value.
  def self.get_boolean(prefix, opts, key, required: false, default: nil)
    prefix = prefix.to_s.empty? ? "" : "#{prefix}: "
    value = get_option(prefix, opts, key, required, default)
    return value if value.nil?
    raise TypeError,
      "#{prefix}Value for '#{key}' must be a boolean, not a #{value.class}" unless value == true || value == false
    value
  end

  # Get a hash option from the given options hash.
  # If the key is missing, and it is required, then raise a KeyError.
  # If the key is missing, and it is not required, then return the default value or nil.
  # If the key is present, but the value is missing, then raise an ArgumentError.
  # If the value is not a hash, then raise a TypeError.
  # Otherwise, return the hash value.
  def self.get_hash(prefix, opts, key, required: false, default: nil)
    prefix = prefix.to_s.empty? ? "" : "#{prefix}: "
    value = get_option(prefix, opts, key, required, default)
    return value if value.nil?
    raise TypeError, "#{prefix}Value for '#{key}' must be a mapping, not a #{value.class}" unless value.is_a?(Hash)
    value
  end

  # Get an integer option from the given options hash.
  # If the key is missing, and it is required, then raise a KeyError.
  # If the key is missing, and it is not required, then return the default value or nil.
  # If the key is present, but the value is missing, then raise an ArgumentError.
  # If the value is not an integer, then raise a TypeError.
  # Otherwise, return the integer value.
  def self.get_integer(prefix, opts, key, required: false, default: nil)
    prefix = prefix.to_s.empty? ? "" : "#{prefix}: "
    value = get_option(prefix, opts, key, required, default)
    return value if value.nil?
    raise TypeError, "#{prefix}Value for '#{key}' must be an integer, not a #{value.class}" unless value.is_a?(Integer)
    value
  end

  # Get an option from the given options hash.
  # If the key is missing, and it is required, then raise a KeyError.
  # If the key is missing, and it is not required, then return the default value or nil.
  # If the key is present, but the value is missing, then raise an ArgumentError.
  # Otherwise, return the value.
  def self.get_option(prefix, opts, key, required, default)
    raise KeyError, "#{prefix}Missing required key: '#{key}'" if !opts.key?(key) && required
    return nil if !opts.key?(key) && !required && default.nil?
    return default if !opts.key?(key) && !required && !default.nil?
    value = opts[key]
    raise ArgumentError, "#{prefix}Missing value for '#{key}'" if value.nil?
    value
  end

  # Get a string option from the given options hash.
  # If the key is missing, and it is required, then raise a KeyError.
  # If the key is missing, and it is not required, then return the default value or nil.
  # If the key is present, but the value is missing, then raise an ArgumentError.
  # If the value is not a string, then raise a TypeError.
  # Otherwise, return the string value.
  def self.get_string(prefix, opts, key, required: false, default: nil)
    prefix = prefix.to_s.empty? ? "" : "#{prefix}: "
    value = get_option(prefix, opts, key, required, default)
    return value if value.nil?
    raise TypeError, "#{prefix}Value for '#{key}' must be a string, not a #{value.class}" unless value.is_a?(String)
    value
  end

  # Provisioning a VM.
  def self.provision(hostname, sys, options)
    provision = get_hash(hostname, options, "provision", default: {})

    dirs = get_array(hostname, provision, "dirs", default: [])
    dirs.each do |dir|
      host = get_string(hostname, dir, "host", required: true)
      remote = get_string(hostname, dir, "remote", required: true)
      dir_mode = get_string(hostname, dir, "dir_mode")
      file_mode = get_string(hostname, dir, "file_mode")

      sys.vm.provision "file", source: host, destination: remote
      if dir_mode
        command = "find #{remote} -type d -exec chmod #{dir_mode}" + ' {} \;'
        sys.vm.provision "shell", inline: command
      end
      if file_mode
        command = "find #{remote} -type f -exec chmod #{file_mode}" + ' {} \;'
        sys.vm.provision "shell", inline: command
      end
    end  # dirs.each do |dir|

    files = get_array(hostname, provision, "files", default: [])
    files.each do |file|
      host = get_string(hostname, file, "host", required: true)
      remote = get_string(hostname, file, "remote", required: true)
      file_mode = get_string(hostname, file, "file_mode")

      sys.vm.provision "file", source: host, destination: remote
      if file_mode
        command = "chmod #{file_mode} #{remote}"
        sys.vm.provision "shell", inline: command
      end
    end  # files.each do |file|

    sys.vm.provision "shell" do |shell|
      shell.keep_color = true
      shell.path = "provision.sh"

      shell.env = {
        "DEV_SYS_USER" => options["user"],
        "DEV_SYS_GROUP" => options["group"]
      }

      ansible_dev_sys = get_hash(hostname, options, "ansible_dev_sys", required: false, default: {})
      if ansible_dev_sys.key?("dir")
        shell.env["ANSIBLE_DEV_SYS_DIR"] = get_string(hostname, ansible_dev_sys, "dir")
      elsif ansible_dev_sys.key?("version")
        shell.env["ANSIBLE_DEV_SYS_VERSION"] = get_string(hostname, ansible_dev_sys, "version")
      end
      tags = get_array(hostname, ansible_dev_sys, "tags", default: ["always"])
      shell.env["ANSIBLE_DEV_SYS_TAGS"] = tags.join(" ")

      bash_environment = get_hash(hostname, options, "bash_environment", required: false, default: {})
      if bash_environment.key?("dir")
        shell.env["BASH_ENVIRONMENT_DIR"] = get_string(hostname, bash_environment, "dir")
      elsif bash_environment.key?("version")
        shell.env["BASH_ENVIRONMENT_VERSION"] = get_string(hostname, bash_environment, "version")
      end
    end  # sys.vm.provision "shell"
  end  # def self.provision()

  # Define the synced folder and method.
  def self.synced_directories(hostname, sys, options)
    sys.vm.synced_folder ".", "/vagrant", disabled: true

    synced_directories = get_array(hostname, options, "synced_directories", default: [])
    synced_directories.each do |directory|
      host = get_string(hostname, directory, "host", required: true)
      remote = get_string(hostname, directory, "remote", required: true)
      sys.vm.synced_folder host, remote,
        type: "rsync",
        create: "true",
        rsync__args: ["-lrtz"],
        rsync__exclude: [".claude/", ".git/", ".gitignore", ".vscode/"],
        rsync__verbose: "true"
    end  # synced_directories.each do |directory|
  end  # def self.synced_directories()
end  # module Vagrant_Dev_Sys

Vagrant_Dev_Sys.configure
