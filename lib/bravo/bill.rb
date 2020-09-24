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

    attr_accessor :bill_type, :due_date, :date_from, :date_to, :body, :response,
                  :invoice_type, :batch

    def initialize(attrs = {})
      opts = { wsdl: Bravo::AuthData.wsfe_url, ssl_version: :TLSv1 }.merge! Bravo.logger_options
      @client       ||= Savon.client(opts)
      @body           = { 'Auth' => Bravo::AuthData.auth_hash }
      @bill_type      = validate_bill_type(attrs[:bill_type])
      @invoice_type   = validate_invoice_type(attrs[:invoice_type])
      @batch          = attrs[:batch] || []
    end

    def inspect
      %(#<Bravo::Bill bill_type: "#{bill_type}", due_date: "#{due_date}", date_from: #{date_from.inspect}, \
date_to: #{date_to.inspect}, invoice_type: #{invoice_type}>)
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
      unless invoice.instance_of?(Bravo::Bill::Invoice)
        raise(NullOrInvalidAttribute.new, 'invoice debe ser del tipo Bravo::Bill::Invoice')
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
      { 'CantReg' => @batch.size.to_s,
        'CbteTipo' => bill_type,
        'PtoVta' => Bravo.sale_point }
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
      result = response[:fecae_solicitar_response][:fecae_solicitar_result]

      unless result[:errors].blank?
        raise AfipError, "#{result[:errors][:err][:code]} - #{result[:errors][:err][:msg]}"
      end

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
            #{Bravo::BILL_TYPE_A.keys}")
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
              "El valor de iva_condition debe estar incluído en #{valid_types}")
      end
    end

    def setup_invoice_structure(invoice, cbte)
      detail = {}
      detail['DocNro']    = invoice.document_number
      detail['CbteDesde'] = detail['CbteHasta'] = invoice.invoice_number > 0 ? invoice.invoice_number : cbte
      detail['Concepto']  = Bravo::CONCEPTOS[invoice.concept]
      detail['DocTipo']   = Bravo::DOCUMENTOS[invoice.document_type]
      detail['MonId']     = Bravo::MONEDAS[invoice.currency][:codigo]
      detail['CbteFch']   = today
      detail['MonCotiz']  = 1
      detail['ImpNeto']   = invoice.net_amount
      detail['ImpIVA']    = invoice.iva_sum
      detail['ImpTotal']  = invoice.total_final

      unless invoice.total_gravado.zero?
        invoice.iva_detail.each do |alic_iva|
          detail['Iva'] = { 'AlicIva' => alic_iva }
        end
      end

      detail['ImpTotConc']  = 0.00
      detail['ImpOpEx']     = invoice.exempt_amount
      detail['ImpTrib']     = invoice.other_taxes

      unless invoice.concept.zero?
        detail.merge!('FchServDesde'  => date_from  || today,
                      'FchServHasta'  => date_to    || today,
                      'FchVtoPago'    => due_date   || today)
      end
    end

    def today
      Time.new.strftime('%Y%m%d')
    end

    class Invoice
      attr_accessor :total_gravado, :document_type, :document_number, :due_date,
                    :date_from, :date_to, :iva_condition, :concept,
                    :currency, :exempt_amount, :iva_detail, :other_taxes,
                    :invoice_number

      def initialize(attrs = {})
        @iva_condition   = validate_iva_condition(attrs[:iva_condition])
        @total_gravado   = attrs[:total_gravado].round(2) || 0.0
        @document_type   = attrs[:document_type]  || Bravo.default_documento
        @currency        = attrs[:currency]       || Bravo.default_moneda
        @concept         = attrs[:concept]        || Bravo.default_concepto
        @document_number = attrs[:document_number]
        @exempt_amount   = attrs[:exempt_amount] &&
                           attrs[:exempt_amount].round(2) || 0.0
        @other_taxes     = attrs[:other_taxes] &&
                           attrs[:other_taxes].round(2) || 0.0
        @iva_detail      = attrs[:iva_detail]
        @invoice_number  = attrs[:invoice_number]
      end

      # Calculates the net amount for the invoice by substracting the iva from
      # the total
      # @return [Float] the sum of both fields, or 0 if the net is 0.
      #
      def net_amount
        net = 0.00
        @iva_detail.each do |alic_iva|
          net += alic_iva['BaseImp']
        end
        net.round(2)
      end

      # Calculates the corresponding iva sum.
      # @return [Float] the iva sum
      #
      def iva_sum
        @iva_sum = @total_gravado - net_amount
        @iva_sum.round(2)
      end

      def total_final
        @total_final = @total_gravado + @exempt_amount + @other_taxes
        @total_final.round(2)
      end

      def validate_iva_condition(iva_cond)
        valid_conditions = Bravo::IVA_CONDITION[Bravo.own_iva_cond].keys
        if valid_conditions.include? iva_cond
          iva_cond
        else
          raise(NullOrInvalidAttribute.new,
                "El valor de iva_condition debe estar incluído en #{valid_conditions}")
        end
      end

      def applicable_iva
        Bravo::ALIC_IVA[@iva_type]
      end

      def validate_invoice_attributes
        return true unless document_number.blank?
        raise(NullOrInvalidAttribute.new, 'document_number debe estar presente.')
      end
    end
  end
end
