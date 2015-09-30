pass-chef
==============

Small script (configurable by a YAML file), to manage Chef encrypted data bags with
[pass](http://passwordstore.org)

# Description

When using Chefs encrypted data bags, it's a challenge howto syncronize the (unencrypted) JSON files
containing the sensitive information between admin users.
There's some approaches on howto solve this, including encrypted git repositories, which is usually
a big mess.

- Store sensitive information in [pass](http://passwordstore.org) (an encrypted, multiuser key-value store using GPG)
- Generate (if required) `data_bag_secrets` automatically (and store them in pass as well)
- Generate Chef data bags from pass information, and syncronize them with the Chef server
- Upload the required `data_bag_secrets` to the servers that need to decrypt the information using
  SSH

# Usage

## Initial setup

Let's say you want to store your SSL certificates securely. First, git clone this repository into
your Chef kitchen.

```shell
$ cd chef-repo
$ git clone https://github.com/chr4/pass-chef.git secrets
$ cd secrets
$ bundle install
```

Create a basic configuraton file `config.yaml` for our certificate datastore

```yaml
certificates:
  data_bag:
    cert: "%s/server.crt"
    key: "%s/server.key"
```

Now, create a directory and the pass store for your certificates

```shell
$ mkdir certificates
$ cd certificates
$ export PASSWORD_STORE_DIR=.
$ pass init you@example.com # Optionally add more recipients
$ pass git init # Optional
```

For convenience, I recommend to set the `PASSWORD_STORE_DIR` variable automatically when changing to
this directory. You can do so using a tool like [direnv](http://direnv.net/)

```shell
$ cat .direnv
# Use current directory to store passwords
export PASSWORD_STORE_DIR=.

# When GPG_AGENT_INFO is set, pass gives the following error message:
# gpg: malformed GPG_AGENT_INFO environment variable
unset GPG_AGENT_INFO
```

*Note*: Unsetting `GPG_AGNET_INFO` helps in case you get the following error: `gpg: malformed GPG_AGENT_INFO environment variable`

## Store your certificate in pass

```shell
$ cat mycert.key |pass insert --multiline www.example.com.key
$ cat mycert.crt |pass insert --multiline www.example.com.crt
```

```shell
$ ./generate certificate www.example.com
Updated data_bag_item[certificates:www.example.com]
```

This will generate (and use) `www.example.com/data_bag_secret` to encrypt your data bag.
The `data_bag_secret` can automatically be uploaded to one or more servers using the `--tagret`
parameter to the remote machines `/etc/chef/certificate_data_bag_secret`. "sudo" is required on the
remote machine.

```shell
$ ./generate certificate www.example.com --target 1.app.example.com,2.app.example.com
Updated data_bag_item[certificates:www.example.com]
Copying data_bag_secret to 1.app.example.com
Copying data_bag_secret to 2.app.example.com
```

When generating/uploading a data bag, you can also specify the data bag id manually by using the
`--id` parameter

```shell
$ ./pass-chef certificates www.example.com --id example
Updated data_bag_item[certificates:example]
```

To share the password store between multiple machines, you best rely on the integrated git support.
For more information, see the [official website](http://passwordstore.org).

That's it! You now have your certificates stored encrypted in pass, and you can update your
data bags and manage the `data_bag_secrets` conveniently!


## Advanced configuration

Of course, you can handle multiple pass stores using the same configuration, as well as adapt
the generation process to your need.

To use a custom path to your password store, set/ change the `PASSWORD_STORE_DIR` environment
variable accordingly, or set it in the `config.yaml`:

```yaml
certificates:
  password_store_dir: 'mycustomdir'
```

When creating the data bag, you can use `%s` as a placeholder for the item name

```yaml
ssh_keypairs:
  # Manually specify password store directory
  password_store_dir: "mydir"

  # Add a description (displayed when using "./pass-chef help"
  description: "Generate ssh keypairs"

  # Customize the data_bag_secret filename. When using the --target flag,
  # the script will upload the data_bag_secret to the remote machine
  data_bag_secret: /etc/chef/my_data_bag_secret

  # Specify how the data bag hash looks like
  # The "%s" placeholder will be replaced with the item name
  #
  # When using "./pass-chef ssh_keypairs example",
  # the script will look for the ssh private and public keys in the pass store
  #
  # - example/id_rsa
  # - example/id_rsa.pub
  # - example/id_ed25519
  # - example/id_ed25519.pub
  #
  # If an element is not found in the pass store, it will be skipped.
  data_bag:
    keychain:
      id_rsa: "%s/id_rsa"
      id_rsa.pub: "%s/id_rsa.pub"
      id_ed25519: "%s/id_ed25519"
      id_ed25519.pub: "%s/id_ed25519.pub"
```

See the [example config.yaml](https://github.com/chr4/pass-chef/blob/master/config.yaml.example)
for further details.
