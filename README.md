Make developer key:

```bash
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
```

Get exact device ID for device from device folder name:

```bash
$ ls ~/.Garmin/ConnectIQ/Devices/
venu441mm
```

Memory and resolution limits etc are in
`~/.Garmin/ConnectIQ/Devices/venu441mm/compiler.json`
