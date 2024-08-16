# This script adds IPs of tor exit nodes to registration_blocklist to prevent the registration of accounts via tor.
# The prosody module module_register_limits must be activated and the option register_blocklist { } must be present in the prosody config.
# https://prosody.im/doc/modules/mod_register_limits
#
# After executing the script reload the modules with mod_reload_modules or restart the prosody server.
# https://modules.prosody.im/mod_reload_modules
#
# The list of https://www.dan.me.uk/torlist/?exit can be fetched every 30 minutes. Else the website owner may block your server.
