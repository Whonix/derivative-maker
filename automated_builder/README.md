# Automated Builder

The `automated_builder` folder contains ansible plays in order to streamline Whonix build automation. Github actions triggers a script that runs an ansible suite. The suite does the following core things

1. Automatically creates a Debian VPS in DigitalOcean
2. Installs VirtualBox on the VPS, and packages required to run the builder
3. Builds the Whonix Workstation and Gateway VMs on the VPS

When a tag is pushed, the automated builder does a full build, with an XFCE GUI installed. This build runs the [Whonix™ Automated Test Suite](https://github.com/Mycobee/whonix_automated_test_suite) (called WATS for short) on the Workstation from the VPS using VBoxManage.

When a commit is pushed, the automated builder runs a headless build and verifies the `derivative-maker` build scripts work. WATS does not run.

## Setup
### VM Setup
1. A Digital Ocean account must be set up with a valid API token in order to use the Automated Builder

### Environment variables
In the github repository settings, the variable `ANSIBLE_VAULT_PASSWORD` must be set to encrypt `automated_builder/vars/main.yml`

In the event you want to help maintain this piece, but don't have the password and want to use your own runner server, `automated_builder/vars/main.yml` has the following variables

```
DO_API_TOKEN: # Put your API token here
SSH_KEY: |
  # Put the Ansible user's configured private key here
SSH_PUBLIC_KEY: |
  # Put the ansible user's configured public key here
VNC_PASSWORD: # Put password for VNC here
```

then run `ansible-vault decrypt automated_builder/vars/main.yml` and enter a password to use in your fork. Enter it as your `ANSIBLE_VAULT_PASSWORD` as mentioned above
