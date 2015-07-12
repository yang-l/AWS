#!/usr/bin/env bash

# import file encryption library
. `cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd`/../lib/file_encryption.func

function usage {

    echo "Usage: $0 -[e|d|n] -k keyfile -i input [-o output]"

    exit 1
}

unset __ENCRYPTION__ __DECRYPTION__ __KEY_FILE__ __INPUT_FILE__ __OUTPUT_FILE__

while getopts ":ednk:i:o:h" opt; do
    case $opt in
        e)
            # encryption
            [ ! -z "$__DECRYPTION__" ] && echo "-e and -d flags cannot be used at the same time" && exit 1
            [ -z "$__ENCRYPTION__" ] && __ENCRYPTION__=True
            ;;
        d)
            # decryption
            [ ! -z "$__ENCRYPTION__" ] && echo "-e and -d flags cannot be used at the same time" && exit 1
            [ -z "$__DECRYPTION__" ] && __DECRYPTION__=True
            ;;
        n)
            # create new private key & ca certificate
            make_cert
            exit 0
            ;;
        k)
            # Key
            [ ! -f "$OPTARG" ] && echo "Invalid key file $OPTARG" && exit 1
            __KEY_FILE__=$OPTARG
            ;;
        i)
            # input file
            [ ! -f "$OPTARG" ] && echo "Invalid input file $OPTARG" && exit 1
            __INPUT_FILE__=$OPTARG
            ;;
        o)
            # output file
            __OUTPUT_FILE__=$OPTARG
            ;;
        h)
            # Help usage
            usage
            ;;
        \?)
            # Invalid options
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
        :)
            # Require an argument
            echo "Option -$OPTARG requires an argument" >&2
    esac
done

# -[e|d], -k and -i are all required
[ -z "${__ENCRYPTION__+x}" ] && [ -z "${__DECRYPTION__+x}" ] && echo "\"-e\" or \"-d\" is required" && exit 1
[ -z "${__KEY_FILE__+x}" ] && echo "\"-k\" is required" && exit 1
[ -z "${__INPUT_FILE__+x}" ] && echo "\"-i\" is required" && exit 1

if [ "$__ENCRYPTION__" ]; then
    # encyrption
    encrypt_file $__KEY_FILE__ $__INPUT_FILE__ $__OUTPUT_FILE__
fi

if [ "$__DECRYPTION__" ]; then
    # decyrption
    decrypt_file $__KEY_FILE__ $__INPUT_FILE__ $__OUTPUT_FILE__
fi

exit 0
