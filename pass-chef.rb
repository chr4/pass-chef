#!/usr/bin/env ruby
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
# Author: Chris Aumann <me@chr4.org>
#

require 'json'
require 'yaml'
require 'boson/runner'
require 'tempfile'

class GenerateRunner < Boson::Runner
  # Path to pass binary
  @@pass = 'pass'

  YAML::load_file('config.yaml').each do |data_bag_name, config|
    # Add default configuration options, unless already set
    config['password_store_dir'] ||= '.'
    config['data_bag_secret'] ||= "/etc/chef/#{data_bag_name}_data_bag_secret"
    config['description'] ||= "Create/Upload encrypted data bag for #{data_bag_name}"

    # Define Boson options
    desc config['description']
    option 'id',     type: :string, desc: 'Data bag id (defaults to item)'
    option 'target', type: :array,  desc: 'Target user@host[,user2@host2] to upload data_bag_secret to'

    # Dynamically create method for each data_bag in config
    define_method(data_bag_name) do |item, options|
      ENV['PASSWORD_STORE_DIR'] = config['password_store_dir']
      # Retrieve all requested items from password store
      data_bag = populate_hash(data_bag_name, config['data_bag'], item)

      if data_bag.empty?
        puts 'No data bag elements found.'
        return
      end

      # Use item as id, unless --id is given, or manually specified in yaml
      data_bag['id'] ||= options['id'] ? options['id'] : item

      # Generate a data_bag_secret unless it is already present
      generate_data_bag_secret(data_bag_name, item) unless File.exist?("#{data_bag_name}/#{item}/data_bag_secret.gpg")

      # Update/Create encrypted data bag from password store information
      update_data_bag(data_bag_name, item, data_bag)

      # Copy data_bag_secret to target servers
      Array(options['target']).each do |target|
        copy_data_bag_secret(data_bag_name, item, target, config['data_bag_secret'])
      end
    end

  end

private

  # Populate a hash with the corresponding password store items
  def populate_hash(data_bag_name, hash, item)
    res = {}
    hash.each do |key, value|
      # Recursivly process hashes
      if value.is_a?(Hash)
        res[key] = populate_hash(data_bag_name, value, item)
      else
        # Replace %s in value string with the current item.
        # Discard stderr, as we might not find all items.
        # For example, we're looking for all kinds of SSH keys, but only use the ones found.
        res[key] = `#{@@pass} show #{data_bag_name}/#{value % item} 2> /dev/null`.chomp
      end
    end

    # Reject empty keys
    res.reject { |_, v| v.empty? }
  end

  # Generate a data_bag_secret using OpenSSL,
  # store it in password store as "target/data_bag_secret"
  def generate_data_bag_secret(data_bag_name, target, length=512)
    system("#{@@pass} insert --multiline #{target}/data_bag_secret <(openssl rand -base64 #{length})")
  end

  # Generate a passphrase,
  # store it in password store as "target.passphrase"
  def generate_passphrase(data_bag_name, target, length=20)
    system("#{@@pass} generate --no-symbols #{target}.passphrase #{length}")
  end

  # Generate JSON from password store information,
  # then encrypt it using the corresponding data_bag_secret
  # and upload data bag to Chef server
  def update_data_bag(data_bag_name, item, element)
    secret = `#{@@pass} show #{data_bag_name}/#{item}/data_bag_secret`.chomp

    # Remove empty keys from hashes
    element.reject! { |_, v| v.empty? } if element.is_a?(Hash)

    # Generate temporary .json file
    tempfile = Tempfile.new(%w(knife-generate .json))
    tempfile.write(JSON.pretty_generate(element))
    tempfile.close

    system("knife data bag from file #{data_bag_name} #{tempfile.path} --secret '#{secret}'")
  end

  # Copy the data_bag_secret of "item" to the target server
  def copy_data_bag_secret(data_bag_name, item, target, file='/etc/chef/encrypted_data_bag_secret')
    secret = `#{@@pass} show #{data_bag_name}/#{item}/data_bag_secret`.chomp
    puts "Copying data_bag_secret to #{target}:#{file}"
    system("ssh #{target} \"echo '#{secret}' |sudo tee #{file} > /dev/null && sudo chmod 00600 #{file} && sudo chown root:root #{file}\"")
  end
end

GenerateRunner.start
