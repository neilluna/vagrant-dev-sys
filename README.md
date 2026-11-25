# vagrant-dev-sys

Version 0.2.0

Create and provision one or more virtual machines. These VMs will not be production quality. They are intended to be development environments. VMs are provisioned with [ansible-dev-sys](https://github.com/neilluna/ansible-dev-sys).

## Prerequisites

In order to use vagrant-dev-sys, you must have the following:

- VirtualBox installed.
  - VBoxManage.exe must be in the PATH.
- A DigitalOcean account and API token, if you are creating the VM on DigitalOcean.
- Vagrant installed.

Once Vagrant is installed, please install the following Vagrant plugins:

```
vagrant-digitalocean
vagrant-disksize
vagrant-vbguest
vagrant_reboot_linux
```

## Use:

1. Copy `sample.config.yaml` to `config.yaml`. Edit `config.yaml` with your parameters.
1. Use the standard Vagrant commands ("status", "up", "ssh", "destroy") to manage your VMs.
