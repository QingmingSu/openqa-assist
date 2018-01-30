#!/bin/bash

OPENQA_CLI="/usr/share/openqa/script/client"
OPENQARC="/home/${USER}/.openqarc"
HOST="https://openqa.suse.de"
ARCHES="aarch64 x86_64 ppc64le s390x"
DRY_RUN=0

usage()
{
    cat <<-EOF
Usage:
$0 <-i iso | -b build> <-k key> <-s secret> [-H host] [-d] [-h]
    -i iso      The iso image to test, multi isos can be specified with: -i 1.iso -i 2.iso
    -b build    The daily build to test, only one build number should be specified
    -k key      The api key to access openQA webUI
    -s secret   The api secret to access openQA webUI
    -H host     The openQA webUI host, default is o.s.d
    -d          Dry run, just print the command line
    -h          Print this help info

The key and secret can be defined in ~/.openqarc, like:
$ cat ~/.openqarc
KEY=1234567890ABCDEF
SECRET=1234567890ABCDEF
EOF
}

fetch_openqa_iso_list()
{
    openqa_assets_iso_url="${HOST}/assets/iso/"
    isos_html="/tmp/isos.html"
    [ -f "$isos_html" ] && rm -f $isos_html
    curl -sSf -o $isos_html $openqa_assets_iso_url || return 1
    return 0
}

validate_iso_images()
{
    fetch_openqa_iso_list || return 1
    for iso in $ISOS; do
        if !(grep -q ">$iso<" $isos_html); then
            echo "ERROR: No such iso in openQA assets: $iso"
            return 1
        fi
    done
    return 0
}

get_iso_by_build_no()
{
    fetch_openqa_iso_list || return 1
    failed=0
    isos_all=$(grep "Build${BUILD}" $isos_html | xargs -n 1 | grep href | cut -d'=' -f2 | cut -d'>' -f1 | grep "iso$" | xargs)
    for iso in $isos_all; do
        [[ "$iso" =~ "Server-DVD"|"Desktop-DVD"|"Installer-DVD" ]] && ISOS+=" $iso"
    done
    ISOS=$(echo $ISOS | sed 's/^\ *//g')
    if [ -n "$ISOS" ]; then
        echo "ISOS: $ISOS"
        for arch in $ARCHES; do
            media_no=$(echo $ISOS | xargs -n 1 | grep "$arch" | wc -l)
            if [[ $media_no -eq 0 ]]; then
                echo "WARNING: No iso image is found for $arch"
            fi
            if [[ $media_no -gt 1 ]]; then
                failed=1
                echo "ERROR: Multi iso images are found for $arch, please specify iso with option '-i':"
                echo "$ISOS" | xargs -n 1 | grep $arch
            fi
        done
    else
        echo "ERROR: No iso image is found for Build $BUILD"
        return 1
    fi
    [ $failed -eq 1 ] && return 1
    return 0
}

get_var()
{
    n=$1
    echo $iso | cut -d'-' -f${n}
}

trigger_tests()
{
    failed=0
    for iso in $ISOS; do
        # reset variables in every loop
        openqa_post_iso="$OPENQA_CLI --host ${HOST} --apikey ${KEY} --apisecret ${SECRET} isos post"
        distri=""
        version=""
        sp=""
        prod=""
        media=""
        flavor=""
        arch=""
        build=""
        opts=""
        index=1

        distri=$(get_var $index | tr 'A-Z' 'a-z')
        index=$(($index + 1))
        version=$(get_var $index)
        index=$(($index + 1))
        if [ $distri == "sle" ]; then
            sp=$(get_var $index)
            [[ $sp =~ SP* ]] && version+="-$sp" && index=$(($index + 1))
            prod=$(get_var $index)
            case $prod in
                Server) ;;
                Desktop) ;;
                Installer) ;;
                *) echo "ERROR: Invalid product name: $prod"; exit 1;;
            esac
            index=$(($index + 1))
        elif [ x"$distri" == "xopensuse" ]; then
            if [ x"$version" == "xLeap" ]; then
                prod='Leap'
                version=$(get_var $index)
                index=$(($index + 1))
            fi
        fi
        media=$(get_var $index)
        if [ x"$media" = "xDVD" ]; then
            :
        elif [ x"$media" = "xMINI" ]; then
            index=$(($index + 1))
            media+=$(get_var $index)
        else
            echo "Unknown media type: $media"
            exit 1
        fi
        if [ $distri == "sle" ]; then
            flavor="$prod-$media-POST"
        else
            flavor="$media"
        fi
        index=$(($index + 1))
        arch=$(get_var $index)
        index=$(($index + 1))
        if [[ x"$distri" == 'xsle' || x"$prod" == 'xLeap' ]]; then
            build=$(get_var $index | sed 's/Build//g')
            if ! (echo $ISO | grep -q "GM"); then
                opts="BETA=1"
            fi
        elif [[ x"$distri" == 'xopensuse' && x"$version" == 'xTumbleweed' ]]; then
            build=$(get_var $index | sed 's/Snapshot//g')
        fi
        openqa_post_iso="$openqa_post_iso ISO=${iso} DISTRI=${distri} VERSION=${version} FLAVOR=${flavor} ARCH=${arch} BUILD=${build} $opts"
        echo $openqa_post_iso
        if [ $DRY_RUN -ne 1 ]; then 
            eval $openqa_post_iso
            if [ $? -ne 0 ]; then
                echo "ERROR: Failed to trigger tests by posting $iso"
                failed=1
            fi
        fi
    done
    [ $failed -eq 1 ] && return 1
    return 0
}

# Read vars from ~/.openqarc, might be overwritten by commandline parameters
[ -f "$OPENQARC" ] && source "$OPENQARC"

while getopts "i:b:k:s:H:dh" opt; do
    case $opt in 
        i) ISOS+=" $OPTARG";;
        b) BUILD="$OPTARG";;
        k) KEY="$OPTARG";;
        s) SECRET="$OPTARG";;
        H) HOST="$OPTARG";;
        d) DRY_RUN=1;;
        h) usage; exit 0;;
        ?) usage; exit 1;;
    esac
done

[[ -n "$ISOS" && -n "$BUILD" ]] && { echo "ERROR: the '-b' option can't be used together with '-i'"; exit 1; }
if [ -n "$ISOS" ]; then
    validate_iso_images || exit 1
elif [ -n "$BUILD" ]; then
    get_iso_by_build_no || exit 1
else
    echo "ERROR: either option '-i' or '-b' should be specified"
    exit 1
fi

[[ -z "$KEY" ]] && { echo "ERROR: the api key is not defined"; exit 1; }
[[ -z "$SECRET" ]] && { echo "ERROR: the api secret is not defined"; exit 1; }

trigger_tests || exit 1
exit 0
