# encoding: utf-8
require 'bundler/setup'
require 'bravo/version'
require 'bravo/constants'
require 'savon'
require 'bravo/core_ext/hash'
require 'bravo/core_ext/string'
require 'bravo/exceptions'

module Bravo
  # Exception Class for missing or invalid attributes
  #
  class NullOrInvalidAttribute < StandardError; end

  # Exception Class for missing or invalid certificate
  #
  class MissingCertificate < StandardError; end

  # This class handles the logging options
  #
  class Logger < Struct.new(:log, :pretty_xml, :level)
    # @param opts [Hash] receives a hash with keys `log`, `pretty_xml` (both
    # boolean) or the desired log level as `level`

    def initialize(opts = {})
      self.log = opts[:log] || false
      self.pretty_xml = opts[:pretty_xml] || log
      self.level = opts[:level] || :debug
    end

    # @return [Hash] returns a hash with the proper logging optios for Savon.
    def logger_options
      { log: log, pretty_print_xml: pretty_xml, log_level: level }
    end
  end

  autoload :Authorizer,   'bravo/authorizer'
  autoload :AuthData,     'bravo/auth_data'
  autoload :Bill,         'bravo/bill'
  autoload :Constants,    'bravo/constants'
  autoload :Wsaa,         'bravo/wsaa'
  autoload :Reference,    'bravo/reference'

  extend self

  attr_accessor :cuit, :sale_point, :default_documento, :pkey, :cert,
                :default_concepto, :default_moneda, :own_iva_cond, :openssl_bin,
                :data_class, :enable_multitenantcy

  class << self
    # Receiver of the logging configuration options.
    # @param opts [Hash] pass a hash with `log`, `pretty_xml` and `level` keys
    # to set them.
    def logger=(opts)
      @logger ||= Logger.new(opts)
    end

    # Sets the logger options to the default values or returns the previously
    # set logger options
    # @return [Logger]
    def logger
      @logger ||= Logger.new
    end

    # Returns the formatted logger options to be used by Savon.
    def logger_options
      logger.logger_options
    end

    def data_class=(dclass)
      @data_class = dclass.constantize
    end

    def cert
      if enable_multitenantcy
        data_class.send(@cert)
      else
        @cert
      end
    end

    def pkey
      if enable_multitenantcy
        data_class.send(@pkey)
      else
        @pkey
      end
    end

    def default_documento
      if enable_multitenantcy
        data_class.send(@default_documento)
      else
        @default_documento
      end
    end

    def default_concepto
      if enable_multitenantcy
        data_class.send(@default_concepto)
      else
        @default_concepto
      end
    end

    def cuit
      if enable_multitenantcy
        data_class.send(@cuit)
      else
        @cuit
      end
    end

    def sale_point
      if enable_multitenantcy
        data_class.send(@sale_point)
      else
        @sale_point
      end
    end

    def default_moneda
      if enable_multitenantcy
        data_class.send(@default_moneda)
      else
        @default_moneda
      end
    end

    def own_iva_cond
      if enable_multitenantcy
        data_class.send(@own_iva_cond)
      else
        if Bravo::IVA_CONDITION.key?(@own_iva_cond)
          @own_iva_cond
        else
          raise(NullOrInvalidAttribute.new,
                "El valor de  own_iva_cond: (#{iva_cond_symbol}) es inválido.")
        end
      end
    end
    
    def reload_const(const, value)
      remove_const(const) if const_defined?(const)
      const_set(const, value)
    end
  end
end
