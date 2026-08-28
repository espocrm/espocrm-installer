# EspoCRM installation script

This script automatically installs EspoCRM as a Docker image with NGINX server and MariaDB database.

## Run

```
wget https://github.com/espocrm/espocrm-installer/releases/latest/download/install.sh
sudo bash install.sh
```

## Run with options

```
wget https://github.com/espocrm/espocrm-installer/releases/latest/download/install.sh
sudo bash install.sh -y --ssl --letsencrypt --domain=my-espocrm.com --email=email@my-domain.com
```

You can also specify a particular EspoCRM version to install:

```
sudo bash install.sh --version=8.4.2
```

If no version is specified, the latest version will be installed.

## Run (only for development)

```
wget -N https://raw.githubusercontent.com/espocrm/espocrm-installer/master/install.sh
sudo bash install.sh
```

## Documentation

For more information about `options`, `installation modes` and more, see [documentation](https://docs.espocrm.com/administration/installation-by-script/).

## License

This repository is published under the Apache License 2.0 license.
