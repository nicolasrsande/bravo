# Bravo
![Travis status](https://travis-ci.org/xguz/bravo.png)

 Por ahora idéntica a leanucci/bravo, solo he modificado el ejemplo de este Readme, que fallaba debido a que faltaba el campo document_number / DocNro.


Bravo permite la obtenci&oacute;n del C.A.E. (C&oacute;digo de Autorizaci&oacute;n Electr&oacute;nico) por medio del Web Service de Facturaci&oacute;n Electr&oacute;nica provisto por AFIP.


## Requisitos

Para poder autorizar comprobantes mediante el WSFE, AFIP requiere de ciertos pasos detallados a continuación:

* Generar una clave privada para la aplicación.
* Generar un CSR (Certificate Signing Request) utilizando el número de CUIT que emitirá los comprobantes y la clave privada del paso anterior. Se deberá enviar a AFIP el CSR para obtener el Certificado X.509 que se utilizará en el proceso de autorización de comprobantes.
	* Para el entorno de Testing, se debe enviar el X.509 por email a _webservices@afip.gov.ar_.
	* Para el entorno de Producción, el trámite se hace a través del portal [AFIP](http://www.afip.gov.ar)
* El certificado X.509 y la clave privada son utilizados por Bravo para obtener el token y signature a incluir en el header de autenticacion en cada request que hagamaos a los servicios de AFIP.


### OpenSSL

Para cumplir con los requisitos de encriptación del [Web Service de Autenticación y Autorización](http://www.afip.gov.ar/ws/WSAA/README.txt) (WSAA), Bravo requiere [OpenSSL](http://openssl.org) en cualquier versión posterior a la 1.0.0a.

Como regla general, basta correr desde la línea de comandos ```openssl cms```

Si el comando ```cms``` no está disponible, se debe actualizar OpenSSL.

### Certificados

AFIP exige para acceder a sus Web Services, la utilización del WSAA. Este servicio se encarga de la autorización y autenticación de cada request hecho al web service.

Una vez instalada la version correcta de OpenSSL, podemos generar la clave privada y el CSR.

* [Documentación WSAA](http://www.afip.gov.ar/ws/WSAA/Especificacion_Tecnica_WSAA_1.2.0.pdf)
* [Cómo generar el CSR](https://gist.github.com/leanucci/7520622)


## Uso

Luego de haber obtenido el certificado X.509, podemos comenzar a utilizar Bravo en el entorno para el cual sirve el certificado.

### Configuración

Bravo no asume valores por defecto, por lo cual hay que configurar de forma explícita todos los parámetros:

* ```pkey``` ruta a la clave privada
* ```cert``` ruta al certificado X.509
* ```cuit``` el número de CUIT para el que queremos emitir los comprobantes
* ```sale_point``` el punto de venta a utilizar (ante la duda consulte a su contador)
* ```default_concepto, default_documento y default_moneda``` estos valores pueden configurarse para no tener que pasarlos cada vez que emitamos un comprobante, ya que no suelen cambiar entre comprobantes emitidos por el mismo vendedor.
* ```own_iva_cond``` condicion propia ante el IVA
* ```openssl_bin``` path al ejecutable de OpenSSL


Ejemplo de configuración tomado del spec_helper de Bravo:

```ruby

require 'bravo'

# Set up Bravo defaults/config.
Bravo.pkey                  = 'spec/fixtures/certs/pkey'
Bravo.cert                  = 'spec/fixtures/certs/cert'
Bravo.cuit                  = '20085617517'
Bravo.sale_point            = '0004'
Bravo.default_concepto      = 'Servicios'
Bravo.default_moneda        = :peso
Bravo.own_iva_cond          = :responsable_inscripto
Bravo.openssl_bin           = '/usr/bin/openssl'
Bravo::AuthData.environment = :test
Bravo.logger.log = true

```

### Emisión de comprobantes

Para emitir un comprobante, basta con:

* instanciar la clase `Bill`,
* instanciar al menos una clase Bill::Invoice
* pasarle los parámetros típicos del comprobante, como si lo llenásemos a mano,
* llamar el método `authorize`, para que el WSFE autorice el comprobante que acabamos de 'llenar':

#### Ejemplo

Luego de configurar Bravo, autorizamos una factura:

* Comprobante: Factura
* Tipo: 'B'
* A: consumidor final
* Total: $ 100 (si fuera una factura tipo A, este valor es el neto, y Bravo calcula el IVA correspondiente)


Código de ejemplo para la configuración anterior:

```ruby

puts "Let's issue a Factura for 100 ARS to a Consumidor Final"

# Creamos un Bill de tipo Factura B
bill_b = Bravo::Bill.new(bill_type: :bill_b,
                         invoice_type: :invoice)

# Creamos un Invoice y pasamos total, tipo de documento, condición de IVA
# del receptor y porcentaje de IVA a aplicar. (0% o 21% para consumidor final)
invoice = Bravo::Bill::Invoice.new(total: 100.0,
                                   document_type: 'DNI',
                                   iva_condition: :consumidor_final,
                                   iva_type: :iva_21)
# Agregamos DNI o CUIT
invoice.document_number = '36025649'

# Agregamos este Invoice al Bill
bill_b.set_new_invoice(invoice)

# Enviamos la solicitud a la AFIP
bill_b.authorize

puts "Authorization result = #{ bill_b.authorized? }"
puts "Authorization response."
puts bill_b.response

```

## TODO list

* ~~rdoc~~
* mensajes de error m&aacute;s completos


## Agradecimientos

* Emilio Tagua por sus consejos y contribuciones.

Copyright (c) 2010 Leandro Marcucci  & Vurbia Technologies International Inc. See LICENSE.txt for further details.
