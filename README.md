# EspoCRM installation script

This script automatically installs EspoCRM as a Docker image with NGINX server and MySQL database.

## Run

```
wget https://github.com/espocrm/espocrm-installer/releases/latest/download/install.sh
bash install.sh
```

## Run with options

```
wget https://github.com/espocrm/espocrm-installer/releases/latest/download/install.sh
bash install.sh -y --ssl --letsencrypt --domain=my-espocrm.com --email=email@my-domain.com
```

## Run (only for development)

```
wget -N https://raw.githubusercontent.com/espocrm/espocrm-installer/master/install.sh
bash install.sh
```

## Documentation

For more information about `options`, `installation modes` and more, see [documentation](https://github.com/espocrm/documentation/blob/master/docs/administration/installation-by-script.md).

## License

This repository is published under the Apache License 2.0 license.
