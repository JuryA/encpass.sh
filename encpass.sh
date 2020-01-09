#!/bin/sh
################################################################################
# Filename: encpass.sh
# Description: This script allows a user to encrypt a password (or any other
#              secret) at runtime and then use it, decrypted, within another
#              script. This prevents shoulder surfing passwords and avoids
#              storing the password in plain text, which could inadvertently
#              be sent to or discovered by an individual at a later date.
#
#              This script generates an AES 256 bit symmetric key for each
#              script (or user-defined label) that stores secrets.  This key
#              will then be used to encrypt all secrets for that script or
#              label.  encpass.sh sets up a directory (.encpass) under the
#              user's home directory where keys and secrets will be stored.
#
#              Subsequent calls to retrieve a secret will not prompt for a
#              secret to be entered as the file with the encrypted value
#              already exists.
#
# Author: Xan Nick
#
# Usage: . ./encpass.sh
#        ...
#        $password=$(get_secret)
################################################################################

checks() {
	if [ -n "$ENCPASS_CHECKS" ]; then
		return
	fi

	if [ ! -x "$(command -v openssl)" ]; then
		echo "Error: OpenSSL is not installed or not accessible in the current path." \
		"Please install it and try again." >&2
		exit 1
	fi

	ENCPASS_HOME_DIR=$(get_abs_filename ~)/.encpass

	if [ ! -d "$ENCPASS_HOME_DIR" ]; then
		mkdir -m 700 "$ENCPASS_HOME_DIR"
		mkdir -m 700 "$ENCPASS_HOME_DIR/keys"
		mkdir -m 700 "$ENCPASS_HOME_DIR/secrets"
	fi

	if [ -n "$1" ] && [ -n "$2" ]; then
		LABEL=$1
		SECRET_NAME=$2
	elif [ -n "$1" ]; then
		LABEL=$(basename "$0")
		SECRET_NAME=$1
	else
		LABEL=$(basename "$0")
		SECRET_NAME="password"
	fi

	ENCPASS_CHECKS=1
}

generate_private_key() {
	KEY_DIR="$ENCPASS_HOME_DIR/keys/$LABEL"

	if [ ! -d "$KEY_DIR" ]; then
		mkdir -m 700 "$KEY_DIR"
	fi

	if [ ! -f "$KEY_DIR/private.key" ]; then
		(umask 0377 && printf "%s" "$(openssl rand -hex 32)" > "$KEY_DIR/private.key")
	fi
}

get_private_key_abs_name() {
	PRIVATE_KEY_ABS_NAME="$ENCPASS_HOME_DIR/keys/$LABEL/private.key"

	if [ ! -f "$PRIVATE_KEY_ABS_NAME" ]; then
		generate_private_key
	fi
}

get_secret_abs_name() {
	SECRET_ABS_NAME="$ENCPASS_HOME_DIR/secrets/$LABEL/$SECRET_NAME.enc"

	if [ ! -f "$SECRET_ABS_NAME" ]; then
		set_secret "$1" "$2"
	fi
}

get_secret() {
	checks "$1" "$2"
	get_private_key_abs_name
	get_secret_abs_name "$1" "$2"

	dd if="$SECRET_ABS_NAME" ibs=1 skip=32 2> /dev/null | openssl enc -aes-256-cbc \
	-d -a -iv "$(head -c 32 "$SECRET_ABS_NAME")" -K "$(cat "$PRIVATE_KEY_ABS_NAME")"
}

set_secret() {
	checks "$1" "$2"
	get_private_key_abs_name
	SECRET_DIR="$ENCPASS_HOME_DIR/secrets/$LABEL"

	if [ ! -d "$SECRET_DIR" ]; then
		mkdir -m 700 "$SECRET_DIR"
	fi

	echo "Enter $SECRET_NAME:" >&2
	stty -echo
	read -r SECRET
	stty echo
	echo "Confirm $SECRET_NAME:" >&2
	stty -echo
	read -r CSECRET
	stty echo
	if [ "$SECRET" = "$CSECRET" ]; then
		printf "%s" "$(openssl rand -hex 16)" > \
		"$SECRET_DIR/$SECRET_NAME.enc"

		echo "$SECRET" | openssl enc -aes-256-cbc -e -a -iv \
		"$(cat "$SECRET_DIR/$SECRET_NAME.enc")" -K \
		"$(cat "$ENCPASS_HOME_DIR/keys/$LABEL/private.key")" 1>> \
		"$SECRET_DIR/$SECRET_NAME.enc_" \
		&& mv "$SECRET_DIR/$SECRET_NAME.enc_" "$SECRET_DIR/$SECRET_NAME.enc"
	else
		echo "Error: secrets do not match.  Please try again." >&2
		exit 1
	fi
}

get_abs_filename() {
	# $1 : relative filename
	filename=$1
	parentdir=$(dirname "${filename}")

	if [ -d "${filename}" ]; then
	        # shellcheck disable=SC2005
		echo "$(cd "${filename}" && pwd)"
	elif [ -d "${parentdir}" ]; then
		echo "$(cd "${parentdir}" && pwd)/$(basename "${filename}")"
	fi
}
