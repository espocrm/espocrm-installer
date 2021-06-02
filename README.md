# EspoCRM installation script

This script automatically installs EspoCRM as a Docker image with NGINX server and MySQL database.

## Run

```
wget https://raw.githubusercontent.com/espocrm/espocrm-installer/stable/install.sh
bash install.sh
```

## Run with options

```
wget https://raw.githubusercontent.com/espocrm/espocrm-installer/stable/install.sh
bash install.sh -y --mode=3 --domain=my-espocrm.com
```

## Available options

#### `-y` or `--yes`

Skip confirmation prompts during installation.

#### `--domain`

Define your domain. Ex. `--domain=my-domain.com`

#### `--mode`

Select the installation mode. See [installation modes](#installation-modes). Ex. `--mode=2`

#### `--email`

Email address for Let's Encrypt certificate. Ex. `--email=email@my-domain.com`

#### `--clean`

Clean the existing EspoCRM installation and start a new one. This option can be used if you have already installed EspoCRM. Ex. `--clean`

#### `--mysqlRootPassword`

Define your own MySQL root password instead of the automatically generated one. Ex. `--mysqlRootPassword=my-password`

#### `--mysqlPassword`

Define your own MySQL password for EspoCRM installation. Ex. `--mysqlPassword=my-password`

#### `--adminUsername`

Define a username of your EspoCRM administrator. Ex. `--adminUsername=admin`

#### `--adminPassword`

Define a password of EspoCRM administrator. Ex. `--adminPassword=admin-password`

## Installation modes

### 1. HTTP mode

This mode is recommended to use only if you don't have a domain name or want to use your IP address as a domain name.

### 2. Let's Encrypt free certificate

This certificate is a free of charge and can be used by providing an email address.

### 3. Own SSL/TLS certificate

If you need a high-security connection, you have to use your own SSL/TLS certificate. In this mode, EspoCRM will be installed with dummy certificates which should be replaced by real ones.

Post installation steps:
1. Go to your server directory `/var/www/espocrm/data/nginx/ssl/live/<YOUR_DOMAIN>/`.
2. Replace the following certificates with your own:
  - fullchain.pem
  - privkey.pem
3. Restart nginx server:

```
/var/www/espocrm/restart.sh espocrm-nginx
```

## License

This repository is published under the Apache License 2.0 license.
