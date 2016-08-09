# encoding: utf-8
module Bravo
  # The main class in Bravo. Handles WSFE method interactions.
  # Subsequent implementations will be added here (maybe).
  #
  class Bill
    # Returns the Savon::Client instance in charge of the interactions with WSFE API.
    # (built on init)
    #
    attr_reader :client

    attr_accessor :bill_type, :due_date, :date_from, :date_to, :body, :response, :invoice_type, :batch

    def initialize(attrs = {})
      opts = { wsdl: Bravo::AuthData.wsfe_url, ssl_version: :TLSv1 }.merge! Bravo.logger_options
      @client       ||= Savon.client(opts)
      @body           = { 'Auth' => Bravo::AuthData.auth_hash }
      @bill_type      = validate_bill_type(attrs[:bill_type])
      @invoice_type   = validate_invoice_type(attrs[:invoice_type])
      @batch          = attrs[:batch] || []
    end

    def inspect
      %{#<Bravo::Bill bill_type: "#{ bill_type }", due_date: "#{ due_date }", date_from: #{ date_from.inspect }, \
date_to: #{ date_to.inspect }, invoice_type: #{ invoice_type }>}
    end

    def to_hash
      { bill_type: bill_type, invoice_type: invoice_type,
        due_date: due_date, date_from: date_from, date_to: date_to, body: body }
    end

    def to_yaml
      to_hash.to_yaml
    end

    # Searches the corresponding invoice type according to the combination of
    # the seller's IVA condition and the buyer's IVA condition
    # @return [String] the document type string
    #
    def bill_type_wsfe
      Bravo::BILL_TYPE[bill_type][invoice_type]
    end

    def set_new_invoice(invoice)
      if not invoice.instance_of?(Bravo::Bill::Invoice)
        raise(NullOrInvalidAttribute.new, "invoice debe ser del tipo Bravo::Bill::Invoice")
      end

      # if Bravo::IVA_CONDITION[Bravo.own_iva_cond][invoice.iva_condition][invoice_type] != bill_type_wsfe
      #   raise(NullOrInvalidAttribute.new, "The invoice doesn't correspond to this bill type")
      # end

      @batch << invoice if invoice.validate_invoice_attributes
    end

    # Files the authorization request to AFIP
    # @return [Boolean] wether the request succeeded or not
    #
    def authorize
      setup_bill
      response = client.call(:fecae_solicitar) do |soap|
        # soap.namespaces['xmlns'] = 'http://ar.gov.afip.dif.FEV1/'
        soap.message body
      end

      setup_response(response.to_hash)
      self.authorized?
    end

    # Sets up the request body for the authorisation
    # @return [Hash] returns the request body as a hash
    #
    def setup_bill
      fecaereq = setup_request_structure
      det_request = fecaereq['FeCAEReq']['FeDetReq']['FECAEDetRequest']
      last_cbte = Bravo::Reference.next_bill_number(bill_type_wsfe)
      @batch.each_with_index do |invoice, index|
        cbte = last_cbte + index
        det_request << setup_invoice_structure(invoice, cbte)
      end
      body.merge!(fecaereq)
    end

    # Returns the result of the authorization operation
    # @return [Boolean] the response result
    #
    def authorized?
      !response.nil? && response.header_result == 'A' && invoices_result
    end

    private

    # Sets the header hash for the request
    # @return [Hash]
    #
    def header(bill_type)
      { 'CantReg' => "#{@batch.size}", 'CbteTipo' => bill_type, 'PtoVta' => Bravo.sale_point }
    end

    def invoices_result
      response.detail_response.map{|invoice| invoice[:resultado] == 'A'}.all?
    end

    # Response parser. Only works for the authorize method
    # @return [Struct] a struct with key-value pairs with the response values
    #
    # rubocop:disable Metrics/MethodLength
    def setup_response(response)
      # TODO: turn this into an all-purpose Response class
      result          = response[:fecae_solicitar_response][:fecae_solicitar_result]

      response_header = result[:fe_cab_resp]
      response_detail = result[:fe_det_resp][:fecae_det_response]

      # If there's only one invoice in the batch, put it in an array
      response_detail = response_detail.respond_to?(:to_ary) ? response_detail : [response_detail]

      response_hash = { header_result:   response_header[:resultado],
                        authorized_on:   response_header[:fch_proceso],
                        header_response: response_header,
                        detail_response: response_detail
                      }

      keys, values = response_hash.to_a.transpose

      self.response = Struct.new(*keys).new(*values)
    end
    # rubocop:enable Metrics/MethodLength

    def validate_invoice_type(type)
      if Bravo::BILL_TYPE_A.keys.include? type
        type
      else
        raise(NullOrInvalidAttribute.new, "invoice_type debe estar incluido en \
            #{ Bravo::BILL_TYPE_A.keys }")
      end
    end

    def setup_request_structure
      { 'FeCAEReq' =>
        { 'FeCabReq' => header(bill_type_wsfe),
          'FeDetReq' => {
            'FECAEDetRequest' => []
          } } }
    end

    def validate_bill_type(type)
      valid_types = Bravo::BILL_TYPE.keys
      if valid_types.include? type
        type
      else
        raise(NullOrInvalidAttribute.new,
          "El valor de iva_condition debe estar incluído en #{ valid_types }")
      end
    end

    def setup_invoice_structure(invoice, cbte)
      detail = {}
      detail['DocNro']    = invoice.document_number
      detail['ImpNeto']   = invoice.net_amount
      detail['ImpIVA']    = invoice.iva_sum
      detail['ImpTotal']  = invoice.total
      detail['CbteDesde'] = detail['CbteHasta'] = cbte
      detail['Concepto']  = Bravo::CONCEPTOS[invoice.concept],
      detail['DocTipo']   = Bravo::DOCUMENTOS[invoice.document_type],
      detail['MonId']     = Bravo::MONEDAS[invoice.currency][:codigo],
      detail['Iva'] = {
        'AlicIva' => {
          'Id' => invoice.applicable_iva_code,
          'BaseImp' => invoice.net_amount,
          'Importe' => invoice.iva_sum
        }
      }
      detail['CbteFch']     = today
      detail['ImpTotConc']  = 0.00
      detail['MonCotiz']    = 1
      detail['ImpOpEx']     = 0.00
      detail['ImpTrib']     = 0.00
      unless invoice.concept == 0
        detail.merge!('FchServDesde'  => date_from  || today,
                      'FchServHasta'  => date_to    || today,
                      'FchVtoPago'    => due_date   || today)
      end
    end

    def today
      Time.new.strftime('%Y%m%d')
    end

    class Invoice
      attr_accessor :total, :document_type, :document_number, :due_date, :aliciva_id, :date_from, :date_to,
        :iva_condition, :concept, :currency

      def initialize(attrs = {})
        @iva_condition  = validate_iva_condition(attrs[:iva_condition])
        @iva_type       = validate_iva_type(attrs[:iva_type])
        @total          = attrs[:total].round(2)|| 0.0
        @document_type  = attrs[:document_type] || Bravo.default_documento
        @currency       = attrs[:currency]      || Bravo.default_moneda
        @concept        = attrs[:concept]       || Bravo.default_concepto
      end

      # Calculates the net amount for the invoice by substracting the iva from
      # the total
      # @return [Float] the sum of both fields, or 0 if the net is 0.
      #
      def net_amount
        net = @total / (1 + applicable_iva_multiplier)
        net.round(2)
      end

      # Calculates the corresponding iva sum.
      # @return [Float] the iva sum
      #
      def iva_sum
        @iva_sum = @total - net_amount
        @iva_sum.round(2)
      end

      def validate_iva_condition(iva_cond)
        valid_conditions = Bravo::IVA_CONDITION[Bravo.own_iva_cond].keys
        if valid_conditions.include? iva_cond
          iva_cond
        else
          raise(NullOrInvalidAttribute.new,
            "El valor de iva_condition debe estar incluído en #{ valid_conditions }")
        end
      end

      def validate_iva_type(iva_type)
        valid_types = Bravo::ALIC_IVA.keys
        if valid_types.include? iva_type
          if iva_type == :iva_0 and iva_condition == :responsable_inscripto
            raise(NullOrInvalidAttribute.new,
              "En caso de responsable inscripto iva_type debe ser distinto de :iva_0")
          end
          iva_type
        else
          raise(NullOrInvalidAttribute.new,
            "El valor de iva_type debe estar incluído en #{ valid_types }")
        end
      end

      def applicable_iva
        Bravo::ALIC_IVA[@iva_type]
      end

      def applicable_iva_code
        applicable_iva[0]
      end

      def applicable_iva_multiplier
        applicable_iva[1]
      end

      def validate_invoice_attributes
        return true unless document_number.blank?
        raise(NullOrInvalidAttribute.new, "document_number debe estar presente.")
      end
    end
  end
end
