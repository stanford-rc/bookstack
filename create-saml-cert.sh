#!/bin/sh
# vim: ts=4 sw=4 noet

# This generates a self-signed certificate that is suitable for use in a SAML
# SP.  It uses a 2048-bit RSA private key, and the certificate has a lifetime
# of 2 years minus 1 day.
#
# The key and cert should be put into Vault, so that they can be loaded when
# Bookstack starts.  Once Bookstack is running in SAML mode, you can get the
# SAML SP metadata (which will include this cert), to load into the IdP.
#
# NOTE: The SP metadata has its own expiration date.  You'll need to ensure
# that expiration date is updated.


# To ensure we don't overwrite files, include a random number in the filenames.
RANDOM_NUMBER=${RANDOM}
OPENSSL_CONFIG="openssl-${RANDOM_NUMBER}.cnf"
CSR_FILE="csr-${RANDOM_NUMBER}.pem"
KEY_FILE="key-${RANDOM_NUMBER}.pem"
CERT_FILE="cert-${RANDOM_NUMBER}.pem"

# Do the work!
echo "Configuring OpenSSL..."
cat - >${OPENSSL_CONFIG} <<EOF
[ req ]
prompt              = no
days                = 729
distinguished_name  = req_dn
req_extensions      = req_ext

[ req_dn ]
countryName = US
stateOrProvinceName = California
localityName        = Stanford
organizationName    = Stanford University
commonName          = bookstack
emailAddress        = srcc-support@stanford.edu

[ req_ext ]
basicConstraints    = CA:false
extendedKeyUsage    = serverAuth
EOF

echo "Creating Key, Certificate Request, and Certificate..."
openssl req -config ${OPENSSL_CONFIG} -new -newkey rsa:2048 -nodes -outform PEM --keyout ${KEY_FILE} -out ${CSR_FILE}
openssl x509 -req -in ${CSR_FILE} -key ${KEY_FILE} -inform PEM -days 729 -out ${CERT_FILE} -outform PEM
EXPIRATION_DATE=$(openssl x509 -in ${CERT_FILE} -noout -enddate | cut -d= -f2)

echo "Cleaning up..."
rm -f ${OPENSSL_CONFIG} ${CSR_FILE}

echo "All done!"
echo
echo "The self-signed certificate is at ${CERT_FILE}"
echo "The private key is at ${KEY_FILE}"
echo
echo "To write this out to Vault, try something like this:"
echo "  vault kv put /secret/projects/uit-rc-bookstack/saml key=@${KEY_FILE} cert=@${CERT_FILE}"
echo
echo "NOTE: The certificate's expiration date is ${EXPIRATION_DATE}."
echo "Make sure your metadata expires around this time."
exit 0
