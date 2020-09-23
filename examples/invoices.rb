require 'bravo'
require 'pp'

# Set up Bravo defaults/config.
Bravo.pkey              = 'spec/fixtures/certs/testing.pkey'
Bravo.cert              = 'spec/fixtures/certs/testing.cert'
Bravo.cuit              = '20085617517'
Bravo.sale_point        = 4
Bravo.default_concepto  = 'Servicios'
Bravo.default_moneda    = :peso
Bravo.own_iva_cond      = :responsable_inscripto
Bravo.openssl_bin       = 'openssl'
Bravo::AuthData.environment = :test
Bravo.logger.log = true

puts 'Issuing a Factura A for 1000 ARS to a Responsable Inscripto '\
     'with 10.5% of IVA'

bill_a = Bravo::Bill.new(bill_type: :bill_a, invoice_type: :invoice)

invoice = Bravo::Bill::Invoice.new(total_gravado: 4400.0,
                                   invoice_number: 4534,
                                   document_type: 'CUIT',
                                   document_number: '30711543267',
                                   iva_condition: :responsable_inscripto,
                                   iva_detail: [{"Id"=>6, "BaseImp"=>3619.91, "Importe"=>380.09 },
                                                {"Id"=>4, "BaseImp"=>3619.91, "Importe"=>380.09 }])

bill_a.set_new_invoice(invoice)

bill_a.authorize

puts "Authorization result = #{bill_a.authorized?}"
puts 'Authorization response.'
pp bill_a.response

########################################################

puts 'Issuing a Recibo B for 100 ARS to a Consumidor Final'

bill_b = Bravo::Bill.new(bill_type: :bill_b, invoice_type: :receipt)

# Un Consumidor Final no necesita tener discriminado el IVA, por eso, iva_type
# puede estar en :iva_o o en :iva_21
invoice = Bravo::Bill::Invoice.new(total: 100.0,
                                   document_type: 'DNI',
                                   document_number: '36025649',
                                   iva_condition: :consumidor_final,
                                   iva_type: :iva_0)

bill_b.set_new_invoice(invoice)

bill_b.authorize

puts "Authorization result = #{bill_b.authorized?}"
puts 'Authorization response.'
pp bill_b.response
