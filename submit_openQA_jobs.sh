#!/bin/bash

OPENQA_CLI="/usr/share/openqa/script/client"
ENTRY="isos"
METHOD="post"
OPENQA_ISO_DIR="/var/lib/openqa/factory/iso"
VARS=""
DRY_RUN=0

usage()
{
    cat <<-EOF
Usage: $0 <-i ISO> [-t ENTRY] [-a ADDON] [-e ENVFILE] [-d] [-h]
    -i ISO      The ISO image to test. 
    -a ADDON    The ADDON image to test. 
                Multi ADDONs can be specified by: -a sdk.iso -a we.iso
    -t ENTRY    Top level entry type: jobs, workers, isos (default: isos)
    -e ENVFILE  ENV file contains environment variables. 
                Multi files can be specified by: -e 1.env -e 2.env
    -d          Dry run, just print the command line.
    -h          Print this help info
For example:
    # To trigger job group:
    $0 -i SLE-12-SP2-Server-DVD-x86_64-Build2141-Media1.iso -a SLE-12-SP2-WE-DVD-x86_64-Build0400-Media1.iso

    # To trigger single job:
    ./submit_openQA_jobs.sh -i SLE-12-SP3-Server-DVD-x86_64-GM-DVD1.iso -t jobs -e tests/install/create_hdd_sle12sp3.env
EOF
}

while getopts "i:t:a:e:dh" opt; do
    case $opt in
        i) ISO="$OPTARG";;
        t) ENTRY="$OPTARG";;
        a) ADDONS+=" $OPTARG";;
        e) ENVFILES+=" $OPTARG";;
        d) DRY_RUN=1;;
        h) usage; exit 0;;
        ?) echo "Invalid option: -$opt"; usage; exit 1;;
    esac
done

# Parse ISO
[ -n "$ISO" ] || { echo "ERROR: ISO MUST be specified!"; exit 1; }
if [ -f "$ISO" ]; then
    iso_path=$ISO
    ISO=$(basename $ISO)
    if [ ! -f "$OPENQA_ISO_DIR/$ISO" ]; then
        cp $iso_path $OPENQA_ISO_DIR || \
        echo "ERROR: The ISO image [$ISO] doesn't exist in $OPENQA_ISO_DIR, and failed to copy" && exit 1
    fi
fi

get_var()
{
    n=$1
    echo $ISO | cut -d'-' -f${n}
}

index=1
dist=$(get_var $index)
DISTRI=$(echo $dist | tr 'A-Z' 'a-z')
index=$(($index + 1))
VERSION=$(get_var $index)
index=$(($index + 1))
if [ $DISTRI == "sle" ]; then
    sp=$(get_var $index)
    [[ $sp =~ SP* ]] && VERSION+="-$sp" && index=$(($index + 1))
    prod=$(get_var $index)
    case $prod in
        Server) ;;
        Desktop) ;;
        Installer) ;;
        *) echo "ERROR: Invalid product name: $prod"; exit 1;;
    esac
    index=$(($index + 1))
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
if [ $DISTRI == "sle" ]; then
    FLAVOR="$prod-$media"
else
    FLAVOR="$media"
fi
index=$(($index + 1))
ARCH=$(get_var $index)
index=$(($index + 1))
if [ $DISTRI == "sle" ]; then
    BUILD=$(get_var $index | sed 's/Build//g')
    if ! (echo $ISO | grep -q "GM"); then
        VARS="BETA=1"
    fi
elif [ $DISTRI == "opensuse" ]; then
    BUILD=$(get_var $index | sed 's/Snapshot//g')
fi

# Parse ENTRY
case $ENTRY in
    isos) ;;
    jobs) ;;
    workers) echo "Unsupported entry: $ENTRY"; exit 2;;
    *) echo "ERROR: Invalid entry: $ENTRY"; exit 1;;
esac

# Parse ADDONS
addon_no=0
for addon in $ADDONS; do
    addon_no=$(($addon_no + 1))
    addon_name=$(echo $addon | sed "s/$dist-$VERSION-\(.*\)-DVD-.*/\1/g")   
    addons_all+=" $(echo $addon_name | tr 'A-Z' 'a-z')"
    addon_build=$(echo $addon | sed "s/.*${ARCH}-\(.*\)-.*/\1/" | sed 's/Build//g')
    VARS+=" BUILD_$addon_name=$addon_build ISO_$addon_no=$addon"
    if ! (echo $addon_build | grep -q "GM"); then
        VARS+=" BETA_$addon_name=1"
    fi
done
addons_all=$(echo $addons_all | sed 's/\ *//g') 
[ $addon_no -ne 0 ] && VARS+=" ADDONS=\'$addons_all\'"
 
# Parse ENVFILES in add included configs 
envs_all=""
for myenv in $ENVFILES; do
    myenv_abs=$(readlink -f $myenv)
    [ ! -f "$myenv_abs" ] && echo "ERROR: No such file: $myenv" && exit 1
    myenv_inc=""
    for x in `grep '^#INCLUDE' $myenv_abs`; do
        [ x$x == "#INCLUDE" ] && continue
        if [ -f "$x" ]; then
            myenv_inc+=" $(readlink -f $x)"
        fi
    done
    envs_all+=" $myenv_inc $myenv_abs"
done
# Read vars from env files
for env in $envs_all; do
    #source $myenv
    VARS+=" $(cat $env | grep -v '^#' | xargs)"
done

BASE_CMD="$OPENQA_CLI $ENTRY $METHOD ISO=$ISO DISTRI=$DISTRI VERSION=$VERSION FLAVOR=$FLAVOR ARCH=$ARCH BUILD=$BUILD"
if [ $DISTRI == "sle" ]; then
    BASE_CMD="$BASE_CMD BUILD_SLE=$BUILD"
fi
CMD=$(eval echo $BASE_CMD $VARS)
echo $CMD
if [ $DRY_RUN -eq 0 ]; then
    eval $CMD
fi

