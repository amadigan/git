#!/bin/zsh
# SPDX-License-Identifier: CC0-1.0

zmodload zsh/zutil
# Create a new keychain
typeset -gA opts

# options -k keychain_name -p p12_password_env_var -c codesign_p12_env_var -i installer_p12_env_var

zparseopts -D -E -A opts k:: p:: c:: i::

KEYCHAIN_NAME="${opts[-k]}"
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_NAME}"
security set-keychain-settings -lut 21600 "${KEYCHAIN_NAME}"
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_NAME}"
security list-keychains -s "${KEYCHAIN_NAME}" $(security list-keychains -d user | tr -d '"')

# Import certificates into the new keychain
echo "${(P)opts[-c]}" | base64 --decode > code_signing_cert.p12
security import code_signing_cert.p12 -k "${KEYCHAIN_NAME}" -P "${(P)opts[-p]}" -T /usr/bin/codesign
rm code_signing_cert.p12
echo "${(P)opts[-i]}" | base64 --decode > installer_signing_cert.p12
security import installer_signing_cert.p12 -k "${KEYCHAIN_NAME}" -P "${(P)opts[-p]}" -T /usr/bin/productbuild
rm installer_signing_cert.p12

# Set key partition list
security set-key-partition-list -S apple-tool:,apple: -s -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_NAME}"
security list-keychains -s "${KEYCHAIN_NAME}" $(security list-keychains -d user | tr -d '"')
security default-keychain -s "${KEYCHAIN_NAME}"

# Find identities
CODE_SIGNING_IDENTITY=$(security find-identity -v -p codesigning "${KEYCHAIN_NAME}" | awk 'NR == 1{print $2}')
PKG_SIGNING_IDENTITY=$(security find-identity -v "${KEYCHAIN_NAME}" | grep Installer | awk 'NR == 1{print $2}')
echo "CODE_SIGNING_IDENTITY=$CODE_SIGNING_IDENTITY"
echo "PKG_SIGNING_IDENTITY=$PKG_SIGNING_IDENTITY"
echo "CODE_SIGNING_IDENTITY=$CODE_SIGNING_IDENTITY" >> ${1}
echo "PKG_SIGNING_IDENTITY=$PKG_SIGNING_IDENTITY" >> ${1}
