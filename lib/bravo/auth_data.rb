module Bravo
  # This class handles authorization data
  #
  class AuthData
    class << self
      attr_accessor :environment, :todays_data_file_name

      # Fetches WSAA Authorization Data to build the datafile for the day.
      # It requires the private key file and the certificate to exist and
      # to be configured as Bravo.pkey and Bravo.cert
      #
      def fetch
        raise "Archivo de llave privada no encontrado en #{Bravo.pkey}" unless File.exist?(Bravo.pkey)
        raise "Archivo certificado no encontrado en #{Bravo.cert}" unless File.exist?(Bravo.cert)

        # Login to the web service. This generates a YAML file with the login
        # token and sign.
        # FIXME: the token lasts for 12 hours, so having one file per day is
        # going to cause authentication failures if we try to login 12 hours
        # later in the same day.
        Bravo::Wsaa.login unless File.exist?(todays_data_file_name)

        YAML.load_file(todays_data_file_name).each do |k, v|
          const = k.to_s.upcase
          Bravo.remove_const(const) if Bravo.const_defined?(const)
          Bravo.const_set(const, v)
        end
      end

      # Returns the authorization hash, containing the Token, Signature and Cuit
      # @return [Hash]
      #
      def auth_hash
        fetch
        { 'Token' => Bravo::TOKEN, 'Sign' => Bravo::SIGN, 'Cuit' => Bravo.cuit }
      end

      # Returns the right wsaa url for the specific environment
      # @return [String]
      #
      def wsaa_url
        check_environment!
        Bravo::URLS[environment][:wsaa]
      end

      # Returns the right wsfe url for the specific environment
      # @return [String]
      #
      def wsfe_url
        check_environment!
        Bravo::URLS[environment][:wsfe]
      end

      # Creates the data file name for a cuit number and the current day
      # @return [String]
      #
      def todays_data_file_name
        "/tmp/bravo_#{Bravo.cuit}_#{Time.new.strftime('%Y_%m_%d')}.yml"
      end

      def check_environment!
        raise 'Environment not set' unless Bravo::URLS.keys.include? environment
      end
    end
  end
end
