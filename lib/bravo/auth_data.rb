module Bravo

  # This class handles authorization data
  #
  class AuthData

    class << self
      SECURITY_OFFSET = 3600

      attr_accessor :environment, :todays_data_file_name

      # Fetches WSAA Authorization Data to build the datafile for the day.
      # It requires the private key file and the certificate to exist and
      # to be configured as Bravo.pkey and Bravo.cert
      #
      def fetch
        raise "Archivo de llave privada no encontrado en #{ Bravo.pkey }" unless File.exist?(Bravo.pkey)
        raise "Archivo certificado no encontrado en #{ Bravo.cert }" unless File.exist?(Bravo.cert)

        Bravo::Wsaa.login unless File.exist?(todays_data_file_name) && !access_ticket_expired?

        YAML.load_file(todays_data_file_name).each do |k, v|
          name = k.to_s.upcase
          Bravo.const_set(name, v) unless Bravo.const_defined?(name) && Bravo.const_get(name) == v
        end
      end

      # Returns the authorization hash, containing the Token, Signature and Cuit
      # @return [Hash]
      #
      def auth_hash
        fetch unless include_token_and_sign? && !access_ticket_expired?
        { 'Token' => Bravo::TOKEN, 'Sign' => Bravo::SIGN, 'Cuit' => Bravo.cuit }
      end

      def include_token_and_sign?
        Bravo.constants.include?(:TOKEN) && Bravo.constants.include?(:SIGN)
      end

      def access_ticket_expired?
        return true unless Bravo.constants.include?(:EXPIRE_AT)
        expire_at = Bravo::EXPIRE_AT.to_time
        Time.now + SECURITY_OFFSET >= expire_at
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
        "/tmp/bravo_#{ Bravo.cuit }_#{ Time.new.strftime('%Y_%m_%d') }.yml"
      end

      def check_environment!
        raise 'Environment not set.' unless Bravo::URLS.keys.include? environment
      end
    end
  end
end
